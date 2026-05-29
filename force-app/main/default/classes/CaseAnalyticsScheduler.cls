public without sharing class CaseAnalyticsScheduler implements Schedulable {

    /**
     * Schedulable wrapper for CaseAnalyticsBatch.
     * Executes the batch with a scope of 200 records per chunk.
     */
    public void execute(SchedulableContext ctx) {
        Database.executeBatch(new CaseAnalyticsBatch(), 200);
    }
}