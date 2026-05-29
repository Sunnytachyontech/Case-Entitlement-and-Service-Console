public without sharing class CaseEventPublisher {

    /**
     * Publishes a Case_Event__e platform event.
     * 
     * Used by:
     *   - SlaBreachQueueable (when escalation created)
     *   - CaseTriggerHandler (when severity assigned, status changed)
     *   - CaseAnalyticsBatch (when analytics refresh completes)
     * 
     * The command center LWC subscribes to these events via empApi
     * and refreshes its data automatically.
     */
    public static void publishEvent(Id caseId, String eventType, String message) {
        Case_Event__e evt = new Case_Event__e();
        evt.Case_Id__c = caseId != null ? String.valueOf(caseId) : '';
        evt.Event_Type__c = eventType;
        evt.Message__c = message;

        EventBus.publish(evt);
    }

    /**
     * Publish multiple events in one call (bulkified).
     */
    public static void publishEvents(List<Case_Event__e> events) {
        if (events != null && !events.isEmpty()) {
            EventBus.publish(events);
        }
    }
}