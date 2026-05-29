public without sharing class SupportAgentActions {

    /**
     * Get case status and basic details.
     * Agent calls this when customer asks "what is my case status?"
     */
    @InvocableMethod(label='Get Case Status' description='Returns case status, severity, owner, and SLA details for a given case number')
    public static List<CaseStatusResponse> getCaseStatus(List<CaseStatusRequest> requests) {
        List<CaseStatusResponse> responses = new List<CaseStatusResponse>();

        for (CaseStatusRequest req : requests) {
            CaseStatusResponse res = new CaseStatusResponse();

            try {
                List<Case> cases = [
                    SELECT Id, CaseNumber, Subject, Status, Severity__c, Priority,
                           Response_Due_on__c, Resolution_due_on__c,
                           Owner.Name, Account.Name, Contact.Name,
                           Description, Major_Incident__c,
                           Waiting_since__c, Total_wait_time_minutes__c,
                           CreatedDate
                    FROM Case
                    WHERE CaseNumber = :req.caseNumber
                    LIMIT 1
                ];

                if (cases.isEmpty()) {
                    res.message = 'No case found with number ' + req.caseNumber + '.';
                    res.success = false;
                    responses.add(res);
                    continue;
                }

                Case c = cases[0];
                DateTime now = System.now();

                res.success = true;
                res.caseNumber = c.CaseNumber;
                res.subject = c.Subject;
                res.status = c.Status;
                res.severity = c.Severity__c;
                res.ownerName = c.Owner.Name;
                res.accountName = c.Account.Name;
                res.createdDate = String.valueOf(c.CreatedDate);

                // SLA information
                if (c.Response_Due_on__c != null) {
                    res.responseDue = String.valueOf(c.Response_Due_on__c);
                    if (now > c.Response_Due_on__c) {
                        res.responseStatus = 'Breached';
                    } else {
                        Long minutesRemaining = (c.Response_Due_on__c.getTime() - now.getTime()) / 60000;
                        res.responseStatus = minutesRemaining + ' minutes remaining';
                    }
                } else {
                    res.responseStatus = 'Not yet set — awaiting severity assignment';
                }

                if (c.Resolution_due_on__c != null) {
                    res.resolutionDue = String.valueOf(c.Resolution_due_on__c);
                    if (now > c.Resolution_due_on__c) {
                        res.resolutionStatus = 'Breached';
                    } else {
                        Long minutesRemaining = (c.Resolution_due_on__c.getTime() - now.getTime()) / 60000;
                        res.resolutionStatus = minutesRemaining + ' minutes remaining';
                    }
                } else {
                    res.resolutionStatus = 'Not yet set — awaiting severity assignment';
                }

                // Waiting status
                if (c.Status == 'Waiting') {
                    res.blockingReason = 'Case is currently waiting for customer response since ' + String.valueOf(c.Waiting_since__c);
                } else if (c.Status == 'New') {
                    res.blockingReason = 'Case is new and awaiting agent pickup.';
                } else {
                    res.blockingReason = 'Case is being actively worked on.';
                }

                // Build summary message
                res.message = 'Case ' + c.CaseNumber + ' (' + c.Subject + ') is currently ' + c.Status + '.';
                if (c.Severity__c != null) {
                    res.message += ' Severity: ' + c.Severity__c + '.';
                }
                if (c.Owner.Name != null) {
                    res.message += ' Assigned to: ' + c.Owner.Name + '.';
                }

            } catch (Exception e) {
                res.success = false;
                res.message = 'Unable to retrieve case details. Please try again.';
            }

            responses.add(res);
        }

        return responses;
    }

    // Request wrapper
    public class CaseStatusRequest {
        @InvocableVariable(label='Case Number' required=true)
        public String caseNumber;
    }

    // Response wrapper
    public class CaseStatusResponse {
        @InvocableVariable(label='Success')
        public Boolean success;

        @InvocableVariable(label='Message')
        public String message;

        @InvocableVariable(label='Case Number')
        public String caseNumber;

        @InvocableVariable(label='Subject')
        public String subject;

        @InvocableVariable(label='Status')
        public String status;

        @InvocableVariable(label='Severity')
        public String severity;

        @InvocableVariable(label='Owner Name')
        public String ownerName;

        @InvocableVariable(label='Account Name')
        public String accountName;

        @InvocableVariable(label='Created Date')
        public String createdDate;

        @InvocableVariable(label='Response Due')
        public String responseDue;

        @InvocableVariable(label='Response Status')
        public String responseStatus;

        @InvocableVariable(label='Resolution Due')
        public String resolutionDue;

        @InvocableVariable(label='Resolution Status')
        public String resolutionStatus;

        @InvocableVariable(label='Blocking Reason')
        public String blockingReason;
    }
}