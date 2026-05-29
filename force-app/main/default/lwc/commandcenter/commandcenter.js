import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { subscribe, unsubscribe, onError } from 'lightning/empApi';
import getDashboardData from '@salesforce/apex/CommandCenterController.getDashboardData';

const ESCALATION_COLUMNS = [
    {
        label: 'Case', fieldName: 'caseNumber', type: 'button',
        typeAttributes: { label: { fieldName: 'caseNumber' }, variant: 'base', name: 'view_case' }
    },
    { label: 'Severity', fieldName: 'severity', type: 'text' },
    { label: 'Account', fieldName: 'accountName', type: 'text' },
    { label: 'Type', fieldName: 'escalationType', type: 'text' },
    { label: 'Status', fieldName: 'escalationStatus', type: 'text' },
    { label: 'Triggered On', fieldName: 'triggeredOn', type: 'date',
        typeAttributes: { month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' }
    },
    { label: 'Notes', fieldName: 'notes', type: 'text' }
];

const CASE_COLUMNS = [
    {
        label: 'Case', fieldName: 'caseNumber', type: 'button',
        typeAttributes: { label: { fieldName: 'caseNumber' }, variant: 'base', name: 'view_case' }
    },
    { label: 'Subject', fieldName: 'subject', type: 'text' },
    { label: 'Severity', fieldName: 'severity', type: 'text' },
    { label: 'Status', fieldName: 'status', type: 'text' },
    { label: 'Account', fieldName: 'accountName', type: 'text' },
    { label: 'Owner', fieldName: 'ownerName', type: 'text' },
    { label: 'Response Due', fieldName: 'responseDue', type: 'date',
        typeAttributes: { month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' }
    },
    { label: 'Resolution Due', fieldName: 'resolutionDue', type: 'date',
        typeAttributes: { month: 'short', day: '2-digit', hour: '2-digit', minute: '2-digit' }
    }
];

const COMPLIANCE_COLUMNS = [
    { label: 'Group', fieldName: 'groupName', type: 'text' },
    { label: 'Total Cases', fieldName: 'totalCases', type: 'number' },
    { label: 'Response Met', fieldName: 'responseMet', type: 'number' },
    { label: 'Resolution Met', fieldName: 'resolutionMet', type: 'number' },
    { label: 'Response %', fieldName: 'responseCompliancePct', type: 'number',
        typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 }
    },
    { label: 'Resolution %', fieldName: 'resolutionCompliancePct', type: 'number',
        typeAttributes: { minimumFractionDigits: 1, maximumFractionDigits: 1 }
    }
];

export default class CommandCenter extends NavigationMixin(LightningElement) {

    // Data
    @track openEscalations = [];
    @track breachedCases = [];
    @track criticalWatchlist = [];
    @track snapshot = null;
    @track complianceByPlan = [];
    @track complianceBySeverity = [];

    // UI state
    isLoading = true;
    lastRefreshed = '';

    // Column definitions
    escalationColumns = ESCALATION_COLUMNS;
    caseColumns = CASE_COLUMNS;
    complianceColumns = COMPLIANCE_COLUMNS;

    // Platform event subscription
    subscription = null;
    channelName = '/event/Case_Event__e';

    // Computed properties for conditional rendering
    get hasEscalations() {
        return this.openEscalations && this.openEscalations.length > 0;
    }

    get hasBreachedCases() {
        return this.breachedCases && this.breachedCases.length > 0;
    }

    get hasCriticalCases() {
        return this.criticalWatchlist && this.criticalWatchlist.length > 0;
    }

    get hasComplianceByPlan() {
        return this.complianceByPlan && this.complianceByPlan.length > 0;
    }

    get hasComplianceBySeverity() {
        return this.complianceBySeverity && this.complianceBySeverity.length > 0;
    }

    // Lifecycle hooks
    connectedCallback() {
        this.loadDashboardData();
        this.subscribeToPlatformEvents();
    }

    disconnectedCallback() {
        this.unsubscribeFromPlatformEvents();
    }

    // Load all dashboard data
    async loadDashboardData() {
        this.isLoading = true;

        try {
            const data = await getDashboardData();

            this.openEscalations = data.openEscalations || [];
            this.breachedCases = data.breachedCases || [];
            this.criticalWatchlist = data.criticalWatchlist || [];
            this.snapshot = data.todaySnapshot || null;
            this.complianceByPlan = data.complianceByPlan || [];
            this.complianceBySeverity = data.complianceBySeverity || [];

            this.lastRefreshed = new Date().toLocaleTimeString();

        } catch (error) {
            console.error('Failed to load dashboard data:', error);
        }

        this.isLoading = false;
    }

    // Manual refresh button
    handleRefresh() {
        this.loadDashboardData();
    }

    // Subscribe to platform events for live refresh
    subscribeToPlatformEvents() {
        const messageCallback = (response) => {
            // When any case event arrives, refresh the dashboard
            console.log('Platform event received:', JSON.stringify(response));
            this.loadDashboardData();
        };

        subscribe(this.channelName, -1, messageCallback).then((response) => {
            this.subscription = response;
            console.log('Subscribed to Case_Event__e');
        });

        onError((error) => {
            console.error('empApi error:', JSON.stringify(error));
        });
    }

    // Unsubscribe on component destroy
    unsubscribeFromPlatformEvents() {
        if (this.subscription) {
            unsubscribe(this.subscription, () => {
                console.log('Unsubscribed from Case_Event__e');
            });
        }
    }

    // Navigate to case record when row action clicked
    handleCaseRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'view_case') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.caseId,
                    objectApiName: 'Case',
                    actionName: 'view'
                }
            });
        }
    }

    // Navigate to case from escalation row
    handleEscalationRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === 'view_case') {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.caseId,
                    objectApiName: 'Case',
                    actionName: 'view'
                }
            });
        }
    }
}