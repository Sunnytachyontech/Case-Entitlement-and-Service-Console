public without sharing class CaseAnalyticsBatch implements Database.Batchable<SObject> {

    /**
     * Historical SLA analytics batch.
     * Uses Database.Batchable (Apex Cursor pattern) for large populations.
     * 
     * Processes closed/resolved cases and computes:
     *   - Was response SLA met?
     *   - Was resolution SLA met?
     *   - Variance in minutes (positive = early, negative = late)
     *   - Actual response and resolution times in minutes
     * 
     * Results stored in Case_Analytics__c — one record per case.
     * 
     * Run from Developer Console:
     *   Database.executeBatch(new CaseAnalyticsBatch(), 200);
     * 
     * Or schedule:
     *   CaseAnalyticsBatch.scheduleDaily();
     */

    public Database.QueryLocator start(Database.BatchableContext ctx) {
        // Cursor: only fetch closed cases with severity and SLA times stamped
        return Database.getQueryLocator([
            SELECT Id, Severity__c, Status, CreatedDate,
                   Response_Due_on__c, Resolution_due_on__c,
                   ClosedDate,
                   AccountId, Account.Coverage_Plan__r.Name,
                   Total_wait_time_minutes__c
            FROM Case
            WHERE Status IN ('Closed', 'Resolved')
            AND Severity__c != null
            AND Response_Due_on__c != null
            AND Resolution_due_on__c != null
            ORDER BY CreatedDate ASC
        ]);
    }

    public void execute(Database.BatchableContext ctx, List<Case> scope) {

        // Collect case IDs to check for existing analytics records
        Set<Id> caseIds = new Set<Id>();
        for (Case c : scope) {
            caseIds.add(c.Id);
        }

        // Query existing analytics records for upsert
        Map<Id, Case_Analytics__c> existingAnalytics = new Map<Id, Case_Analytics__c>();
        for (Case_Analytics__c ca : [
            SELECT Id, Case__c
            FROM Case_Analytics__c
            WHERE Case__c IN :caseIds
        ]) {
            existingAnalytics.put(ca.Case__c, ca);
        }

        List<Case_Analytics__c> toUpsert = new List<Case_Analytics__c>();
        DateTime now = System.now();

        for (Case c : scope) {
            try {
                Case_Analytics__c analytics;

                // Reuse existing record or create new
                if (existingAnalytics.containsKey(c.Id)) {
                    analytics = existingAnalytics.get(c.Id);
                } else {
                    analytics = new Case_Analytics__c();
                    analytics.Case__c = c.Id;
                }

                // Denormalized fields for reporting
                analytics.Severity__c = c.Severity__c;
                analytics.Coverage_Plan__c = c.Account.Coverage_Plan__r.Name;
                analytics.Computed_Date__c = now;

                // Determine actual response time
                // Response = time from case creation to first status change from New
                // Approximation: use CreatedDate to Response_Due_on__c target to derive
                // For simplicity, if case was responded to (Status != New at close),
                // we measure from CreatedDate to when SLA was set (severity assigned)
                // Since we lack exact response timestamp, use SLA deadline minus target as proxy

                // Calculate resolution time
                DateTime closedAt = c.ClosedDate;
                if (closedAt == null) {
                    closedAt = now; // fallback for resolved but not closed
                }

                // Actual resolution minutes = CreatedDate to ClosedDate minus wait time
                Decimal waitMinutes = c.Total_wait_time_minutes__c != null 
                                      ? c.Total_wait_time_minutes__c : 0;
                Long totalResolutionMillis = closedAt.getTime() - c.CreatedDate.getTime();
                Integer actualResolutionMinutes = (Integer)(totalResolutionMillis / 60000) - (Integer)waitMinutes;
                analytics.Actual_Resolution_Minutes__c = actualResolutionMinutes;

                // Resolution variance = deadline minus actual close time
                // Positive = closed before deadline (met), Negative = closed after deadline (breached)
                Long resolutionVarianceMillis = c.Resolution_due_on__c.getTime() - closedAt.getTime();
                Integer resolutionVarianceMinutes = (Integer)(resolutionVarianceMillis / 60000);
                analytics.Resolution_Variance_Minutes__c = resolutionVarianceMinutes;
                analytics.Resolution_Met__c = (resolutionVarianceMinutes >= 0);

                // Response variance = was response deadline met?
                // If case was closed before response deadline, response was definitely met
                // If response deadline already passed, it was breached
                Long responseVarianceMillis = c.Response_Due_on__c.getTime() - closedAt.getTime();
                Integer responseVarianceMinutes = (Integer)(responseVarianceMillis / 60000);

                // Actual response minutes approximation
                // Since severity assignment = SLA start, actual response = SLA target - variance
                // If response deadline is in the future relative to close, response was met
                analytics.Response_Variance_Minutes__c = responseVarianceMinutes;
                analytics.Response_Met__c = (responseVarianceMinutes >= 0);

                // Actual response time = time from creation to response (approximate)
                // Using CreatedDate to (Response_Due_on__c - variance) as proxy
                if (responseVarianceMinutes >= 0) {
                    // Response was met — actual time < target
                    Long actualResponseMillis = c.Response_Due_on__c.getTime() - 
                                                 (responseVarianceMinutes * 60000L) - 
                                                 c.CreatedDate.getTime();
                    analytics.Actual_Response_Minutes__c = (Integer)(actualResponseMillis / 60000);
                } else {
                    // Response was breached — actual time > target
                    analytics.Actual_Response_Minutes__c = actualResolutionMinutes; // worst case
                }

                toUpsert.add(analytics);

            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 
                    'CaseAnalyticsBatch failed for Case ' + c.Id + ': ' + e.getMessage());
            }
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
        }
    }

    public void finish(Database.BatchableContext ctx) {
        // Publish event to notify dashboard that analytics are refreshed
        CaseEventPublisher.publishEvent(null, 'Analytics_Refreshed', 'SLA analytics batch completed');
        System.debug('CaseAnalyticsBatch completed successfully');
    }

    /**
     * Schedule to run daily at 2 AM.
     * Call once from Developer Console:
     *   CaseAnalyticsBatch.scheduleDaily();
     */
    public static void scheduleDaily() {
        String cronExp = '0 0 2 * * ?';
        String jobName = 'Case Analytics Daily';

        List<CronTrigger> existing = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name = :jobName 
            AND State != 'DELETED'
        ];

        if (existing.isEmpty()) {
            System.schedule(jobName, cronExp, new CaseAnalyticsScheduler());
        }
    }

    /**
     * Unschedule all analytics jobs.
     */
    public static void unscheduleAll() {
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE 'Case Analytics%'
            AND State != 'DELETED'
        ];
        for (CronTrigger ct : jobs) {
            System.abortJob(ct.Id);
        }
    }
}