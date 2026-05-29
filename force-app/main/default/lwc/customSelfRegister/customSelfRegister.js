import { LightningElement, api } from 'lwc';
import selfRegister from '@salesforce/apex/LightningSelfRegisterController.selfRegister';
import { NavigationMixin } from 'lightning/navigation';

export default class CustomSelfRegister extends NavigationMixin(LightningElement) {

    // Form field variables
    companyName = '';
    firstName = '';
    lastName = '';
    email = '';
    password = '';
    confirmPassword = '';

    
    errorMessage = '';
    isLoading = false;
    isSuccess = false;

    // Configurable properties from Experience Builder
    @api loginUrl = '/login';
    @api startUrl = '/s/';
    @api regConfirmUrl = '/s/login/SelfRegisterConfirm';

    
    get buttonLabel() {
        return this.isLoading ? 'Creating Account...' : 'Sign Up';
    }

    // Field change handlers
    handleCompanyNameChange(event) {
        this.companyName = event.target.value;
    }

    handleFirstNameChange(event) {
        this.firstName = event.target.value;
    }

    handleLastNameChange(event) {
        this.lastName = event.target.value;
    }

    handleEmailChange(event) {
        this.email = event.target.value;
    }

    handlePasswordChange(event) {
        this.password = event.target.value;
    }

    handleConfirmPasswordChange(event) {
        this.confirmPassword = event.target.value;
    }

    // Form validation
    validateForm() {
        const allValid = [...this.template.querySelectorAll('lightning-input')]
            .reduce((validSoFar, inputField) => {
                inputField.reportValidity();
                return validSoFar && inputField.checkValidity();
            }, true);

        if (!allValid) {
            return false;
        }

        if (this.password !== this.confirmPassword) {
            this.errorMessage = 'Passwords do not match.';
            return false;
        }

        if (this.password.length < 8) {
            this.errorMessage = 'Password must be at least 8 characters.';
            return false;
        }

        return true;
    }

    /* Registration handler
    async is used as await is used to call the Apex method, this method's response or answer is needed to move on to next part
    */
    async handleRegister() {
        this.errorMessage = '';

        if (!this.validateForm()) {
            return;
        }

        this.isLoading = true;

        try {
            const result = await selfRegister({
                firstname: this.firstName,
                lastname: this.lastName,
                email: this.email,
                password: this.password,
                confirmPassword: this.confirmPassword,
                accountId: null,
                regConfirmUrl: this.regConfirmUrl,
                extraFields: null,
                startUrl: this.startUrl,
                includePassword: true,
                companyName: this.companyName
            });

            if (result) {
                // selfRegister returns an error message string on failure
                this.errorMessage = result;
                this.isLoading = false;
            } else {
                // null result means success — the controller handles redirect
                this.isSuccess = true;
                this.isLoading = false;
            }
        } catch (error) {
            this.errorMessage = error.body?.message || 'An unexpected error occurred. Please try again.';
            this.isLoading = false;
        }
    }
}