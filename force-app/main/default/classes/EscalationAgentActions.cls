public without sharing class EscalationAgentActions {

    /**
     * Summarize escalations on a case.
     * Agent calls this when customer asks "have there been any escalations on my case?"
     */
    @InvocableMethod(label='Get Case Escalations' description='Returns all escalation records for a given case number')
    public static List<EscalationSummaryResponse> getCaseEscalations(List<EscalationSummaryRequest> requests) {
        List<EscalationSummaryResponse> responses = new List<EscalationSummaryResponse>();

        for (EscalationSummaryRequest req : requests) {
            EscalationSummaryResponse res = new EscalationSummaryResponse();

            try {
                // First find the case
                List<Case> cases = [
                    SELECT Id, CaseNumber
                    FROM Case
                    WHERE CaseNumber = :req.caseNumber
                    LIMIT 1
                ];

                if (cases.isEmpty()) {
                    res.message = 'No case found with number ' + req.caseNumber + '.';
                    res.success = false;
                    res.escalationCount = 0;
                    responses.add(res);
                    continue;
                }

                Id caseId = cases[0].Id;

                // Query escalations
                List<Escalation__c> escalations = [
                    SELECT Id, Name, Escalation_Type__c, Escalation_Status__c,
                           Triggered_on__c, Triggered_by_rule__c, Notes__c
                    FROM Escalation__c
                    WHERE Case__c = :caseId
                    ORDER BY Triggered_on__c DESC
                    LIMIT 20
                ];

                res.success = true;
                res.caseNumber = req.caseNumber;
                res.escalationCount = escalations.size();

                if (escalations.isEmpty()) {
                    res.message = 'No escalations found for case ' + req.caseNumber + '. Your case is on track.';
                    res.escalationDetails = '';
                } else {
                    // Build a readable summary
                    String details = '';
                    Integer openCount = 0;

                    for (Escalation__c esc : escalations) {
                        details += esc.Name + ': ';
                        details += esc.Escalation_Type__c + ' — ';
                        details += 'Status: ' + esc.Escalation_Status__c;
                        if (esc.Triggered_on__c != null) {
                            details += ' — Triggered: ' + esc.Triggered_on__c.format();
                        }
                        if (String.isNotBlank(esc.Notes__c)) {
                            details += ' — Note: ' + esc.Notes__c;
                        }
                        details += '\n';

                        if (esc.Escalation_Status__c == 'Open' || esc.Escalation_Status__c == 'In Progress') {
                            openCount++;
                        }
                    }

                    res.escalationDetails = details;
                    res.openEscalationCount = openCount;
                    res.message = 'Case ' + req.caseNumber + ' has ' + escalations.size() + ' escalation(s). ';
                    res.message += openCount + ' are currently open.';
                }

            } catch (Exception e) {
                res.success = false;
                res.message = 'Unable to retrieve escalation details. Please try again.';
                res.escalationCount = 0;
            }

            responses.add(res);
        }

        return responses;
    }

    // Request wrapper
    public class EscalationSummaryRequest {
        @InvocableVariable(label='Case Number' required=true)
        public String caseNumber;
    }

    // Response wrapper
    public class EscalationSummaryResponse {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;

        @InvocableVariable(label='Case Number')
        public String caseNumber;

        @InvocableVariable(label='Escalation Count')
        public Integer escalationCount;

        @InvocableVariable(label='Open Escalation Count')
        public Integer openEscalationCount;

        @InvocableVariable(label='Escalation Details')
        public String escalationDetails;
    }
}