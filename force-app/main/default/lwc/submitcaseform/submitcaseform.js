import { LightningElement, wire } from 'lwc';
import submitNewCase from '@salesforce/apex/PortalCaseController.submitNewCase';
import getFormPicklists from '@salesforce/apex/PortalCaseController.getFormPicklists';

export default class SubmitCaseForm extends LightningElement {

    // Form field values
    subject = '';
    description = '';
    caseReason = '';
    caseOrigin = '';
    caseType = '';

    // Picklist options — loaded from Apex
    typeOptions = [];
    reasonOptions = [];
    originOptions = [];

    // UI state
    errorMessage = '';
    isLoading = false;
    isSuccess = false;
    caseNumber = '';

    // Load picklist values on component init
    @wire(getFormPicklists)
    wiredPicklists({ error, data }) {
        if (data) {
            this.typeOptions = data.typeOptions;
            this.reasonOptions = data.reasonOptions;
            this.originOptions = data.originOptions;

            // Set default origin to Web if available
            const webOption = data.originOptions.find(opt => opt.value === 'Web');
            if (webOption) {
                this.caseOrigin = 'Web';
            }
        } else if (error) {
            this.errorMessage = 'Unable to load form options. Please refresh the page.';
        }
    }

    // Computed button label
    get buttonLabel() {
        return this.isLoading ? 'Submitting...' : 'Submit Case';
    }

    // Field change handlers
    handleSubjectChange(event) {
        this.subject = event.target.value;
    }

    handleDescriptionChange(event) {
        this.description = event.target.value;
    }

    handleTypeChange(event) {
        this.caseType = event.detail.value;
    }

    handleReasonChange(event) {
        this.caseReason = event.detail.value;
    }

    handleOriginChange(event) {
        this.caseOrigin = event.detail.value;
    }

    // Form validation
    validateForm() {
        const inputs = [...this.template.querySelectorAll('lightning-input, lightning-textarea')];
        let allValid = inputs.reduce((validSoFar, inputField) => {
            inputField.reportValidity();
            return validSoFar && inputField.checkValidity();
        }, true);

        if (!allValid) {
            return false;
        }

        if (!this.subject || this.subject.trim() === '') {
            this.errorMessage = 'Subject is required.';
            return false;
        }

        if (!this.description || this.description.trim() === '') {
            this.errorMessage = 'Description is required.';
            return false;
        }

        return true;
    }

    // Submit handler — calls Apex directly, no LDS
    async handleSubmit() {
        this.errorMessage = '';

        if (!this.validateForm()) {
            return;
        }

        this.isLoading = true;

        try {
            const result = await submitNewCase({
                subject: this.subject,
                description: this.description,
                caseReason: this.caseReason,
                caseOrigin: this.caseOrigin || 'Web',
                caseType: this.caseType
            });

            this.caseNumber = result.caseNumber;
            this.isSuccess = true;
            this.isLoading = false;

        } catch (error) {
            this.errorMessage = error.body?.message || 'An unexpected error occurred. Please try again.';
            this.isLoading = false;
        }
    }

    // Reset form for another case
    handleReset() {
        this.subject = '';
        this.description = '';
        this.caseReason = '';
        this.caseOrigin = 'Web';
        this.caseType = '';
        this.errorMessage = '';
        this.isSuccess = false;
        this.caseNumber = '';
    }
}