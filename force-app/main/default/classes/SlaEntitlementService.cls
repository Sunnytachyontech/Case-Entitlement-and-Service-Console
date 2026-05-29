public with sharing class SlaEntitlementService {

    /**
     * Stamps Response_Due_on__c and Resolution_due_on__c on cases
     * based on the account's Coverage Plan and the case severity.
     * 
     * Called by the trigger handler when:
     *   - Severity is assigned for the first time (null → value)
     *   - Severity is changed (S3 → S1)
     * 
     * Bulkified — handles multiple cases in one transaction.
     * Uses before update context — modifies Trigger.new directly, no extra DML.
     */
    public static void stampSlaTargets(List<Case> cases, Map<Id, Case> oldMap) {

        // Step 1 — collect AccountIds from all cases that need SLA stamping
        Set<Id> accountIds = new Set<Id>();
        List<Case> casesToProcess = new List<Case>();

        for (Case c : cases) {
            Case oldCase = oldMap.get(c.Id);

            // Only process if severity changed (null → value, or value → different value)
            if (c.Severity__c != null && c.Severity__c != oldCase.Severity__c) {
                accountIds.add(c.AccountId);
                casesToProcess.add(c);
            }
        }

        if (casesToProcess.isEmpty()) {
            return;
        }

        // Step 2 — query all relevant accounts with their coverage plans in one SOQL
        Map<Id, Account> accountMap = new Map<Id, Account>([
            SELECT Id, Coverage_Plan__c,
                   Coverage_Plan__r.S1__c,
                   Coverage_Plan__r.S1_Resolution__c,
                   Coverage_Plan__r.S2_Response_Minutes__c,
                   Coverage_Plan__r.S2_Resolution_Minutes__c,
                   Coverage_Plan__r.S3_Response_Minutes__c,
                   Coverage_Plan__r.S3_Resolution_Minutes__c,
                   Coverage_Plan__r.S4_Response_Minutes__c,
                   Coverage_Plan__r.S4_Resolution_Minutes__c,
                   Coverage_Plan__r.User__c
            FROM Account
            WHERE Id IN :accountIds
        ]);

        // Step 3 — for each case, resolve SLA targets and stamp
        DateTime now = DateTime.now();

        for (Case c : casesToProcess) {
            Account acc = accountMap.get(c.AccountId);

            // Guard: account must have a coverage plan
            if (acc == null || acc.Coverage_Plan__c == null) {
                continue;
            }

            // Resolve response and resolution minutes based on severity
            Integer responseMinutes = getResponseMinutes(acc, c.Severity__c);
            Integer resolutionMinutes = getResolutionMinutes(acc, c.Severity__c);

            if (responseMinutes == null || resolutionMinutes == null) {
                continue;
            }

            // Stamp SLA deadlines — clock starts from NOW (when rep assigns severity)
            c.Response_Due_on__c = now.addMinutes(responseMinutes);
            c.Resolution_due_on__c = now.addMinutes(resolutionMinutes);

            // Assign rep from coverage plan if one is configured
            /*
            Now assignment is done to a queue according to account's coverage plan and this is done by Record triggered flow
            if (acc.Coverage_Plan__r.User__c != null) {
                c.OwnerId = acc.Coverage_Plan__r.User__c;
            }
            */
        }
    }

    /**
     * Returns the response target in minutes for a given severity level.
     */
    private static Integer getResponseMinutes(Account acc, String severity) {
        switch on severity {
            when 'S1' { return safeInteger(acc.Coverage_Plan__r.S1__c); }
            when 'S2' { return safeInteger(acc.Coverage_Plan__r.S2_Response_Minutes__c); }
            when 'S3' { return safeInteger(acc.Coverage_Plan__r.S3_Response_Minutes__c); }
            when 'S4' { return safeInteger(acc.Coverage_Plan__r.S4_Response_Minutes__c); }
            when else  { return null; }
        }
    }

    /**
     * Returns the resolution target in minutes for a given severity level.
     */
    private static Integer getResolutionMinutes(Account acc, String severity) {
        switch on severity {
            when 'S1' { return safeInteger(acc.Coverage_Plan__r.S1_Resolution__c); }
            when 'S2' { return safeInteger(acc.Coverage_Plan__r.S2_Resolution_Minutes__c); }
            when 'S3' { return safeInteger(acc.Coverage_Plan__r.S3_Resolution_Minutes__c); }
            when 'S4' { return safeInteger(acc.Coverage_Plan__r.S4_Resolution_Minutes__c); }
            when else  { return null; }
        }
    }

    /**
     * Safely converts a Decimal field to Integer.
     */
    private static Integer safeInteger(Decimal value) {
        return value != null ? value.intValue() : null;
    }
}