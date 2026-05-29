public with sharing class SlaBreachQueueable implements Queueable {

    private List<Id> caseIdsToProcess;
    private List<Id> remainingCaseIds;

    public SlaBreachQueueable(List<Id> caseIdsToProcess, List<Id> remainingCaseIds) {
        this.caseIdsToProcess = caseIdsToProcess;
        this.remainingCaseIds = remainingCaseIds;
    }

    public void execute(QueueableContext ctx) {

        List<Case> cases = [
            SELECT Id, Status, Severity__c,
                   Response_Due_on__c, Resolution_due_on__c,
                   AccountId, ContactId, OwnerId
            FROM Case
            WHERE Id IN :caseIdsToProcess
        ];

        // Guard: check existing open escalations to avoid duplicates
        Map<String, Escalation__c> existingEscalations = new Map<String, Escalation__c>();
        List<Escalation__c> existingRecords = [
            SELECT Id, Case__c, Escalation_Type__c
            FROM Escalation__c
            WHERE Case__c IN :caseIdsToProcess
            AND Escalation_Status__c IN ('Open', 'In Progress')
        ];
        for (Escalation__c esc : existingRecords) {
            String key = esc.Case__c + '-' + esc.Escalation_Type__c;
            existingEscalations.put(key, esc);
        }

        DateTime now = System.now();
        List<Escalation__c> newEscalations = new List<Escalation__c>();
        List<Case_Event__e> events = new List<Case_Event__e>();

        for (Case c : cases) {
            try {
                if (c.Status == 'Closed' || c.Status == 'Waiting') {
                    continue;
                }

                // Check response breach
                if (c.Response_Due_on__c != null
                    && now > c.Response_Due_on__c
                    && c.Status == 'New') {

                    String key = c.Id + '-SLA Breach - Response';
                    if (!existingEscalations.containsKey(key)) {
                        newEscalations.add(createEscalation(
                            c.Id,
                            'SLA Breach - Response',
                            'Response SLA breached. Deadline was ' + c.Response_Due_on__c.format()
                        ));

                        // Publish event for command center
                        Case_Event__e evt = new Case_Event__e();
                        evt.Case_Id__c = String.valueOf(c.Id);
                        evt.Event_Type__c = 'Escalation_Created';
                        evt.Message__c = 'Response SLA breached for case';
                        events.add(evt);
                    }
                }

                // Check resolution breach
                if (c.Resolution_due_on__c != null
                    && now > c.Resolution_due_on__c
                    && c.Status != 'Resolved') {

                    String key = c.Id + '-SLA Breach - Resolution';
                    if (!existingEscalations.containsKey(key)) {
                        newEscalations.add(createEscalation(
                            c.Id,
                            'SLA Breach - Resolution',
                            'Resolution SLA breached. Deadline was ' + c.Resolution_due_on__c.format()
                        ));

                        Case_Event__e evt = new Case_Event__e();
                        evt.Case_Id__c = String.valueOf(c.Id);
                        evt.Event_Type__c = 'Escalation_Created';
                        evt.Message__c = 'Resolution SLA breached for case';
                        events.add(evt);
                    }
                }

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'SLA breach check failed for Case ' + c.Id + ': ' + e.getMessage());
            }
        }

        if (!newEscalations.isEmpty()) {
            insert newEscalations;
        }

        // Publish all events
        if (!events.isEmpty()) {
            CaseEventPublisher.publishEvents(events);
        }

        // Chain to next chunk
        if (!remainingCaseIds.isEmpty()) {
            List<Id> nextChunk = new List<Id>();
            List<Id> stillRemaining = new List<Id>();

            for (Integer i = 0; i < remainingCaseIds.size(); i++) {
                if (i < 50) {
                    nextChunk.add(remainingCaseIds[i]);
                } else {
                    stillRemaining.add(remainingCaseIds[i]);
                }
            }

            if (!Test.isRunningTest()) {
                System.enqueueJob(new SlaBreachQueueable(nextChunk, stillRemaining));
            }
        }
    }

    private Escalation__c createEscalation(Id caseId, String escalationType, String note) {
        return new Escalation__c(
            Case__c                = caseId,
            Escalation_Type__c     = escalationType,
            Triggered_on__c        = System.now(),
            Triggered_by_rule__c   = 'SLA Monitor - Auto Detection',
            Escalation_Status__c   = 'Open',
            Notes__c               = note
        );
    }
}