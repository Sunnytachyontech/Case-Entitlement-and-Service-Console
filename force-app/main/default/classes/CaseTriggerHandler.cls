public without sharing class CaseTriggerHandler {

    // Map of Coverage Plan Name to Queue Id
    private static final Map<String, Id> PLAN_QUEUE_MAP = new Map<String, Id>{
        'Standard' => '00GNS00000kdhCI2AY',
        'Pro'      => '00GNS00000kdr3Z2AQ',
        'Elite'    => '00GNS00000kdr0L2AQ',
        'Max'      => '00GNS00000kdr1x2AA'
    };

    /**
     * Called on before insert.
     * Assigns the case to the correct queue based on the account's coverage plan.
     */
    public static void onBeforeInsert(List<Case> newCases) {

        Set<Id> accountIds = new Set<Id>();
        for (Case c : newCases) {
            if (c.AccountId != null) {
                accountIds.add(c.AccountId);
            }
        }

        if (accountIds.isEmpty()) {
            return;
        }

        Map<Id, Account> accountMap = new Map<Id, Account>([
            SELECT Id, Coverage_Plan__c, Coverage_Plan__r.Name
            FROM Account
            WHERE Id IN :accountIds
        ]);

        for (Case c : newCases) {
            if (c.AccountId == null) {
                continue;
            }

            Account acc = accountMap.get(c.AccountId);
            if (acc == null || acc.Coverage_Plan__c == null) {
                continue;
            }

            String planName = acc.Coverage_Plan__r.Name;
            if (PLAN_QUEUE_MAP.containsKey(planName)) {
                c.OwnerId = PLAN_QUEUE_MAP.get(planName);
            }
        }
    }

    /**
     * Called on after insert.
     * Enqueues OmniChannelRouter to push cases to available agents.
     * Publishes platform event for new case creation.
     */
    public static void onAfterInsert(List<Case> newCases) {

        List<Id> queueOwnedCaseIds = new List<Id>();
        List<Case_Event__e> events = new List<Case_Event__e>();

        for (Case c : newCases) {
            if (c.OwnerId != null && String.valueOf(c.OwnerId).startsWith('00G')) {
                queueOwnedCaseIds.add(c.Id);
            }

            // Publish event for new case
            Case_Event__e evt = new Case_Event__e();
            evt.Case_Id__c = String.valueOf(c.Id);
            evt.Event_Type__c = 'Case_Created';
            evt.Message__c = 'New case created';
            events.add(evt);
        }

        if (!queueOwnedCaseIds.isEmpty() && !System.isBatch() && !System.isFuture()) {
            System.enqueueJob(new OmniChannelRouter(queueOwnedCaseIds));
        }

        // Publish events
        if (!events.isEmpty()) {
            CaseEventPublisher.publishEvents(events);
        }
    }

    /**
     * Called on before update.
     * Routes to SLA service on severity change.
     * Handles Waiting status clock pause/resume.
     */
    public static void onBeforeUpdate(List<Case> newCases, Map<Id, Case> oldMap) {

        List<Case> severityChangedCases = new List<Case>();

        for (Case c : newCases) {
            Case oldCase = oldMap.get(c.Id);

            if (c.Severity__c != null && c.Severity__c != oldCase.Severity__c) {
                severityChangedCases.add(c);
            }

            if (c.Status == 'Working' && oldCase.Status != 'Working') {
                c.Waiting_since__c = System.now();
            }

            if (oldCase.Status == 'Working' && c.Status != 'Working') {
                if (c.Waiting_since__c != null) {
                    Long millisInWaiting = System.now().getTime() - c.Waiting_since__c.getTime();
                    Integer minutesInWaiting = (Integer)(millisInWaiting / 60000);

                    Decimal currentWaitTime = c.Total_wait_time_minutes__c != null 
                                              ? c.Total_wait_time_minutes__c : 0;
                    c.Total_wait_time_minutes__c = currentWaitTime + minutesInWaiting;

                    if (c.Response_Due_on__c != null) {
                        c.Response_Due_on__c = c.Response_Due_on__c.addMinutes(minutesInWaiting);
                    }
                    if (c.Resolution_due_on__c != null) {
                        c.Resolution_due_on__c = c.Resolution_due_on__c.addMinutes(minutesInWaiting);
                    }

                    c.Waiting_since__c = null;
                }
            }
        }

        if (!severityChangedCases.isEmpty()) {
            SlaEntitlementService.stampSlaTargets(severityChangedCases, oldMap);
        }
    }

    /**
     * Called on after update.
     * Publishes platform events for severity and status changes.
     */
    public static void onAfterUpdate(List<Case> newCases, Map<Id, Case> oldMap) {

        List<Case_Event__e> events = new List<Case_Event__e>();

        for (Case c : newCases) {
            Case oldCase = oldMap.get(c.Id);

            // Severity assigned or changed
            if (c.Severity__c != null && c.Severity__c != oldCase.Severity__c) {
                Case_Event__e evt = new Case_Event__e();
                evt.Case_Id__c = String.valueOf(c.Id);
                evt.Event_Type__c = 'Severity_Assigned';
                evt.Message__c = 'Severity set to ' + c.Severity__c;
                events.add(evt);
            }

            // Status changed
            if (c.Status != oldCase.Status) {
                Case_Event__e evt = new Case_Event__e();
                evt.Case_Id__c = String.valueOf(c.Id);
                evt.Event_Type__c = 'Status_Changed';
                evt.Message__c = 'Status changed from ' + oldCase.Status + ' to ' + c.Status;
                events.add(evt);

                // Special event for case resolved/closed
                if (c.Status == 'Closed' || c.Status == 'Resolved') {
                    Case_Event__e resolvedEvt = new Case_Event__e();
                    resolvedEvt.Case_Id__c = String.valueOf(c.Id);
                    resolvedEvt.Event_Type__c = 'Case_Resolved';
                    resolvedEvt.Message__c = 'Case ' + c.Status;
                    events.add(resolvedEvt);
                }
            }
        }

        if (!events.isEmpty()) {
            CaseEventPublisher.publishEvents(events);
        }
    }
}