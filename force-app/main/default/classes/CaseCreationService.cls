public without sharing class CaseCreationService {

    // Request wrapper — what the LWC sends in
    public class NewCaseRequest {
        @AuraEnabled public String subject;
        @AuraEnabled public String description;
        @AuraEnabled public String caseReason;
        @AuraEnabled public String caseOrigin;
        @AuraEnabled public String caseType;
    }

    // Response wrapper — what the LWC gets back
    public class NewCaseResponse {
        @AuraEnabled public String caseNumber;
        @AuraEnabled public String message;

        public NewCaseResponse(String caseNumber) {
            this.caseNumber = caseNumber;
            this.message = 'Your case has been raised successfully.';
        }
    }

    public static NewCaseResponse createCase(NewCaseRequest req) {

        // Step 1 — resolve identity: logged-in user → ContactId → AccountId
        User u = [
            SELECT ContactId, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        // Guard: portal user must have a Contact
        if (u.ContactId == null) {
            throw new AuraHandledException(
                'Your account is not fully set up. Please contact support.'
            );
        }

        // Step 2 — build the Case record
        Case c = new Case();
        c.Subject     = req.subject;
        c.Description = req.description;
        c.Reason      = req.caseReason;
        c.Origin      = req.caseOrigin;
        c.Type        = req.caseType;
        c.ContactId   = u.ContactId;
        c.AccountId   = u.Contact.AccountId;
        c.Status      = 'New';

        // Step 3 — insert (trigger fires here — EntitlementService stamps SLA)
        insert c;

        // Step 4 — return only the CaseNumber
        Case inserted = [
            SELECT CaseNumber FROM Case WHERE Id = :c.Id
        ];
        return new NewCaseResponse(inserted.CaseNumber);
    }
}