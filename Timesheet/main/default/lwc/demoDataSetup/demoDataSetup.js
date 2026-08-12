import { LightningElement, track } from 'lwc';
import createDemoData from '@salesforce/apex/DemoDataController.createDemoData';
import createCurrentUserEmployee from '@salesforce/apex/DemoDataController.createCurrentUserEmployee';
import createDemoProjects from '@salesforce/apex/DemoDataController.createDemoProjects';
import createDemoProjectAssignments from '@salesforce/apex/DemoDataController.createDemoProjectAssignments';
import createDemoTimesheets from '@salesforce/apex/DemoDataController.createDemoTimesheets';
import createDemoTimesheetLineItems from '@salesforce/apex/DemoDataController.createDemoTimesheetLineItems';
import deleteTestRecords from '@salesforce/apex/DemoDataController.deleteTestRecords';
import getDemoStatus from '@salesforce/apex/DemoDataController.getDemoStatus';
import getDemoRecords from '@salesforce/apex/DemoDataController.getDemoRecords';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class DemoDataSetup extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track hasEmployee = false;
    @track isTestEmployee = false;
    @track employeeName = '';
    @track hasAccess = false;
    
    @track employees = [];
    @track projects = [];
    @track projectEmployees = [];
    @track timesheets = [];

    // Default open sections for accordion
    @track activeSections = ['employees', 'projects', 'projectEmployees', 'timesheets'];

    @track accessTerminated = false;
    @track isCreating = false;
    @track isDeleting = false;
    @track showSectionsOverride = false;

    lineItemColumns = [
        { label: 'Date', fieldName: 'dateStr', type: 'text', initialWidth: 120 },
        { label: 'Project / Type', fieldName: 'projectOrType', type: 'text' },
        { label: 'Hours', fieldName: 'duration', type: 'text', initialWidth: 100 },
        { label: 'Description', fieldName: 'description', type: 'text' }
    ];

    connectedCallback() {
        console.log('DemoDataSetup connected');
        this.loadStatus();
    }

    loadStatus() {
        this.isLoading = true;
        getDemoStatus()
            .then((result) => {
                this.hasAccess = result.hasAccess;
                this.hasEmployee = result.hasEmployee;
                this.isTestEmployee = result.isTestEmployee;
                this.employeeName = result.employeeName;
                if (this.hasAccess && this.hasEmployee && this.isTestEmployee && !this.accessTerminated) {
                    this.loadDemoRecords();
                } else {
                    this.isLoading = false;
                }
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', 'Error loading demo status: ' + this.getErrorMessage(error), 'error');
            });
    }

    loadDemoRecords() {
        getDemoRecords()
            .then((wrapper) => {
                this.employees = wrapper.employees || [];
                this.projects = wrapper.projects || [];
                this.projectEmployees = wrapper.projectEmployees || [];
                this.timesheets = (wrapper.timesheets || []).map(ts => {
                    return {
                        ...ts,
                        isOpen: false,
                        iconName: 'utility:chevronright',
                        mappedLineItems: (ts.lineItems || []).map(item => ({
                            ...item,
                            projectOrType: item.project ? item.project : item.type
                        }))
                    };
                });
                this.isLoading = false;
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', 'Failed to load created test records: ' + this.getErrorMessage(error), 'error');
            });
    }

    handleCreateDemoData() {
        this.showSectionsOverride = true;
    }

    handleCreateCurrentUserEmployee() {
        this.isLoading = true;
        createCurrentUserEmployee()
            .then(() => {
                this.showToast('Success', 'Employee created successfully.', 'success');
                this.loadStatus();
            })
            .catch((error) => {
                this.isLoading = false;
                console.error('createCurrentUserEmployee failed', error);
                const errorMsg = this.getErrorMessage(error);
                if (errorMsg.includes('manager in your User record')) {
                    this.showToast('Warning', "Current user doesn't have manager. First assign manager in user record.", 'warning');
                } else {
                    this.showToast('Error', 'Error creating employee: ' + errorMsg, 'error');
                }
            });
    }

    handleCreateProjects() {
        this.isLoading = true;
        createDemoProjects()
            .then(() => {
                this.showToast('Success', 'Projects created successfully.', 'success');
                this.loadStatus();
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', 'Error creating projects: ' + this.getErrorMessage(error), 'error');
            });
    }

    handleCreateProjectAssignments() {
        this.isLoading = true;
        createDemoProjectAssignments()
            .then(() => {
                this.showToast('Success', 'Project assignments created successfully.', 'success');
                this.loadStatus();
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', 'Error creating project assignments: ' + this.getErrorMessage(error), 'error');
            });
    }

    handleCreateTimesheets() {
        this.isLoading = true;
        createDemoTimesheets()
            .then(() => {
                this.showToast('Success', 'Timesheets created successfully.', 'success');
                this.loadStatus();
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', 'Error creating timesheets: ' + this.getErrorMessage(error), 'error');
            });
    }

    handleCreateTimesheetLineItems(event) {
        const timesheetId = event.target.dataset.id;
        if (!timesheetId) return;
        this.isLoading = true;
        createDemoTimesheetLineItems({ timesheetId: timesheetId })
            .then(() => {
                this.showToast('Success', 'Timesheet Line Items created successfully.', 'success');
                this.loadStatus();
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', 'Error creating timesheet line items: ' + this.getErrorMessage(error), 'error');
            });
    }

    handleDeleteTestRecords() {
        this.isDeleting = true;
        this.isLoading = true;
        deleteTestRecords()
            .then(() => {
                this.showToast('Success', 'All test records have been deleted.', 'success');
                this.isDeleting = false;
                this.isLoading = false;
                this.accessTerminated = true;
                this.employees = [];
                this.projects = [];
                this.projectEmployees = [];
                this.timesheets = [];
            })
            .catch((error) => {
                this.isDeleting = false;
                this.isLoading = false;
                this.showToast('Error', 'Error deleting test records: ' + this.getErrorMessage(error), 'error');
            });
    }

    handleToggleTimesheet(event) {
        const recordId = event.currentTarget.dataset.id;
        this.timesheets = this.timesheets.map(ts => {
            if (ts.recordId === recordId) {
                const nowOpen = !ts.isOpen;
                return { 
                    ...ts, 
                    isOpen: nowOpen,
                    iconName: nowOpen ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }
            return ts;
        });
    }

    handleOpenUrl(event) {
        event.stopPropagation();
        const url = event.target.dataset.url || event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleReturnToOverview() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Overview'
            }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }

    getErrorMessage(error) {
        if (!error) return 'Unknown error';
        if (typeof error.body === 'string') return error.body;
        if (Array.isArray(error.body) && error.body.length > 0) {
            return error.body.map((item) => item.message || item.detail || JSON.stringify(item)).join(', ');
        }
        if (error.body) {
            if (error.body.message) return error.body.message;
            if (Array.isArray(error.body.pageErrors) && error.body.pageErrors.length > 0) return error.body.pageErrors.map((item) => item.message).join(', ');
            if (error.body.output && Array.isArray(error.body.output.errors) && error.body.output.errors.length > 0) return error.body.output.errors.map((item) => item.message).join(', ');
            if (error.body.output && error.body.output.errors) return String(error.body.output.errors);
            if (error.body.fieldErrors) {
                const fieldMessages = Object.values(error.body.fieldErrors).flat().map((fieldError) => fieldError.message).filter(Boolean);
                if (fieldMessages.length) return fieldMessages.join(', ');
            }
            if (typeof error.body === 'object') return JSON.stringify(error.body);
        }
        if (error.message) return error.message;
        return JSON.stringify(error);
    }

    // Dynamic labels with counts
    get employeesLabel() { return `Employees (${this.employees.length})`; }
    get projectsLabel() { return `Projects (${this.projects.length})`; }
    get projectAssignmentsLabel() { return `Project Assignments (${this.projectEmployees.length})`; }
    get timesheetsLabel() { return `Timesheets (${this.timesheets.length})`; }

    get showSetupPrompt() {
        return !this.isLoading && this.hasAccess && !this.hasEmployee && !this.accessTerminated && !this.showSectionsOverride;
    }

    get showCreatedRecordsView() {
        return !this.isLoading && this.hasAccess && (this.hasEmployee || this.showSectionsOverride) && !this.accessTerminated;
    }

    get showNoAccessMessage() {
        return !this.isLoading && !this.hasAccess;
    }

    get hasProjects() { return this.projects && this.projects.length > 0; }
    get hasProjectAssignments() { return this.projectEmployees && this.projectEmployees.length > 0; }
    get hasTimesheets() { return this.timesheets && this.timesheets.length > 0; }

    get showDeleteButton() {
        return this.showCreatedRecordsView && this.hasAccess;
    }

    get showAccessTerminated() {
        return !this.isLoading && this.accessTerminated;
    }

    get showInaccessibleEmployee() {
        return false; // Deprecated: we now allow any employee
    }
}
