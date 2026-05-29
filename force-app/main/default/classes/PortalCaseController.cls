public with sharing class PortalCaseController {

    // Identity wrapper for the LWC
    public class UserIdentity {
        @AuraEnabled public String contactId;
        @AuraEnabled public String accountId;
    }

    // Picklist option wrapper
    public class PicklistOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;

        public PicklistOption(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    // All picklist values needed by the form
    public class FormPicklists {
        @AuraEnabled public List<PicklistOption> typeOptions;
        @AuraEnabled public List<PicklistOption> reasonOptions;
        @AuraEnabled public List<PicklistOption> originOptions;
    }

    /*
    getUserIdentity is for fetching the logged in user's account and contact information 
    */
    @AuraEnabled(cacheable=true)
    public static UserIdentity getUserIdentity() {
        User u = [
            SELECT ContactId, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
        ];

        UserIdentity identity = new UserIdentity();
        identity.contactId = u.ContactId;
        identity.accountId = u.Contact.AccountId;
        return identity;
    }

    @AuraEnabled(cacheable=true)
    public static FormPicklists getFormPicklists() {
        FormPicklists result = new FormPicklists();

        result.typeOptions = getPicklistValues('Case', 'Type');
        result.reasonOptions = getPicklistValues('Case', 'Reason');
        result.originOptions = getPicklistValues('Case', 'Origin');

        return result;
    }

    private static List<PicklistOption> getPicklistValues(String objectName, String fieldName) {
        List<PicklistOption> options = new List<PicklistOption>();

        Schema.DescribeSObjectResult objDescribe = Schema.getGlobalDescribe().get(objectName).getDescribe();
        Schema.DescribeFieldResult fieldDescribe = objDescribe.fields.getMap().get(fieldName).getDescribe();

        for (Schema.PicklistEntry entry : fieldDescribe.getPicklistValues()) {
            if (entry.isActive()) {
                options.add(new PicklistOption(entry.getLabel(), entry.getValue()));
            }
        }

        return options;
    }

    @AuraEnabled
    public static CaseCreationService.NewCaseResponse submitNewCase(
        String subject,
        String description,
        String caseReason,
        String caseOrigin,
        String caseType
    ) {
        try {
            if (String.isBlank(subject)) {
                throw new AuraHandledException('Subject is required.');
            }
            if (String.isBlank(description)) {
                throw new AuraHandledException('Description is required.');
            }

            CaseCreationService.NewCaseRequest req = new CaseCreationService.NewCaseRequest();
            req.subject     = subject;
            req.description = description;
            req.caseReason  = caseReason;
            req.caseOrigin  = caseOrigin;
            req.caseType    = caseType;

            return CaseCreationService.createCase(req);

        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            throw new AuraHandledException(
                e.getMessage()
            );
        }
    }
}