public with sharing class SlaMonitorScheduled implements Schedulable {

    /**
     * Runs on a cron schedule every 5 minutes.
     * Queries all active cases that have SLA deadlines stamped.
     * Chunks them into groups of 50 and enqueues a Queueable for each chunk.
     * 
     * This class is a pure dispatcher — no business logic, no breach detection.
     */
    public void execute(SchedulableContext ctx) {

        // Query active cases that have SLA times stamped and are not in Waiting or terminal state
        List<Case> activeCases = [
            SELECT Id
            FROM Case
            WHERE (Response_Due_on__c != null OR Resolution_due_on__c != null)
            AND Status != 'Closed'
            AND Status != 'Waiting'
            AND Severity__c != null
            LIMIT 10000
        ];

        if (activeCases.isEmpty()) {
            return;
        }

        // Collect case IDs
        List<Id> caseIds = new List<Id>();
        for (Case c : activeCases) {
            caseIds.add(c.Id);
        }

        
        List<Id> firstChunk = new List<Id>();
        List<Id> remainingIds = new List<Id>();

        for (Integer i = 0; i < caseIds.size(); i++) {
            if (i < 50) {
                firstChunk.add(caseIds[i]);
            } else {
                remainingIds.add(caseIds[i]);
            }
        }

        // Enqueue the first chunk — it will chain to process remaining chunks
        if (!firstChunk.isEmpty()) {
            System.enqueueJob(new SlaBreachQueueable(firstChunk, remainingIds));
        }
    }

    /**
     * Utility method to schedule this job.
     * Call once from Developer Console:
     *   SlaMonitorScheduled.scheduleJob();
     */
    public static void scheduleJob() {
        // Schedule to run every 5 minutes using multiple cron jobs
        for (Integer i = 0; i < 60; i += 5) {
            String jobName = 'SLA Monitor - Minute ' + i;
            String cronExp = '0 ' + i + ' * * * ?';
            
            // Check if already scheduled to avoid duplicates
            List<CronTrigger> existing = [
                SELECT Id FROM CronTrigger 
                WHERE CronJobDetail.Name = :jobName 
                AND State != 'DELETED'
            ];
            
            if (existing.isEmpty()) {
                System.schedule(jobName, cronExp, new SlaMonitorScheduled());
            }
        }
    }

    /**
     * Utility method to unschedule all SLA monitor jobs.
     * Call from Developer Console:
     *   SlaMonitorScheduled.unscheduleAll();
     */
    public static void unscheduleAll() {
        List<CronTrigger> jobs = [
            SELECT Id FROM CronTrigger 
            WHERE CronJobDetail.Name LIKE 'SLA Monitor%'
            AND State != 'DELETED'
        ];
        for (CronTrigger ct : jobs) {
            System.abortJob(ct.Id);
        }
    }
}