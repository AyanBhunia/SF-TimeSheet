import { LightningElement } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getDemoStatus from '@salesforce/apex/DemoDataController.getDemoStatus';
import getDemoRecords from '@salesforce/apex/DemoDataController.getDemoRecords';
import createDemoEmployee from '@salesforce/apex/DemoDataController.createDemoEmployee';
import createChildEmployees from '@salesforce/apex/DemoDataController.createChildEmployees';
import createDemoProjects from '@salesforce/apex/DemoDataController.createDemoProjects';
import createDemoProjectAssignments from '@salesforce/apex/DemoDataController.createDemoProjectAssignments';
import createDemoTimesheets from '@salesforce/apex/DemoDataController.createDemoTimesheets';
import getDeleteSummary from '@salesforce/apex/DemoDataController.getDeleteSummary';
import deleteDemoRecords from '@salesforce/apex/DemoDataController.deleteDemoRecords';

const VIEW_ACTION = {
    type: 'button-icon',
    fixedWidth: 50,
    typeAttributes: {
        iconName: 'utility:new_window',
        name: 'view',
        title: 'Open record in a new tab',
        alternativeText: 'Open record',
        variant: 'bare'
    }
};

// Setup steps in order. Each step is done once the records it creates exist.
const STEPS = [
    {
        value: 'employee',
        label: 'Employee',
        title: 'Create the demo employee',
        description: 'Creates "Demo Employee", managed by your manager (or by you if you have none).',
        buttonLabel: 'Create Employee',
        successMessage: 'Demo employee created.',
        action: createDemoEmployee
    },
    {
        value: 'children',
        label: 'Child Employees',
        title: 'Create child employees',
        description: 'Creates two employees who report to you, so you can approve their timesheets.',
        buttonLabel: 'Create Child Employees',
        successMessage: 'Child employees created.',
        action: createChildEmployees
    },
    {
        value: 'projects',
        label: 'Projects',
        title: 'Create demo projects',
        description: 'Creates a billable, a non-billable and a legacy project.',
        buttonLabel: 'Create Projects',
        successMessage: 'Demo projects created.',
        action: createDemoProjects
    },
    {
        value: 'assignments',
        label: 'Assignments',
        title: 'Assign employees to projects',
        description: 'Assigns every demo employee to every demo project at an hourly rate of 150.',
        buttonLabel: 'Create Assignments',
        successMessage: 'Project assignments created.',
        action: createDemoProjectAssignments
    },
    {
        value: 'timesheets',
        label: 'Timesheets',
        title: 'Create demo timesheets',
        description: 'Creates four weekly timesheets per employee with line items; the two oldest weeks are approved and the legacy project is deactivated.',
        buttonLabel: 'Create Timesheets',
        successMessage: 'Demo timesheets created.',
        action: createDemoTimesheets
    }
];

export default class DemoDataSetup extends NavigationMixin(LightningElement) {
    isLoading = true;
    hasAccess = false;
    canCreate = false;
    isProductionOrg = false;
    recordsDeleted = false;
    message;

    employees = [];
    projects = [];
    projectEmployees = [];
    timesheets = [];

    showDeleteConfirm = false;
    isDeleting = false;
    deleteSummary;

    // Path shown above the next-step card; the extra "Ready" step is current once everything exists.
    steps = [...STEPS, { value: 'done', label: 'Ready' }];

    employeeColumns = [
        { label: 'Name', fieldName: 'name' },
        { label: 'Manager', fieldName: 'manager' },
        { label: 'Accrual Start Date', fieldName: 'accrualStartDate', type: 'date-local' },
        { label: 'Accrual Divisor', fieldName: 'accrualDivisor', type: 'number' },
        VIEW_ACTION
    ];

    projectColumns = [
        { label: 'Name', fieldName: 'name' },
        { label: 'Status', fieldName: 'status' },
        { label: 'Billable', fieldName: 'billable' },
        VIEW_ACTION
    ];

    projectAssignmentColumns = [
        { label: 'Employee', fieldName: 'employeeName' },
        { label: 'Project', fieldName: 'projectName' },
        { label: 'Hourly Rate', fieldName: 'hourlyRate', type: 'number' },
        VIEW_ACTION
    ];

    timesheetColumns = [
        { label: 'Timesheet / Date', fieldName: 'name', type: 'text', initialWidth: 320 },
        { label: 'Week', fieldName: 'dates', type: 'text', initialWidth: 200 },
        { label: 'Project / Type', fieldName: 'projectOrType', type: 'text' },
        { label: 'Status', fieldName: 'status', type: 'text', initialWidth: 110 },
        { label: 'Hours', fieldName: 'hours', type: 'number', initialWidth: 90 },
        { label: 'Description', fieldName: 'description', type: 'text' },
        VIEW_ACTION
    ];

    connectedCallback() {
        this.loadStatus();
    }

    async loadStatus() {
        this.isLoading = true;
        try {
            const status = await getDemoStatus();
            this.hasAccess = status.hasAccess;
            this.canCreate = status.canCreate === true;
            this.isProductionOrg = status.isProductionOrg === true;
            if (this.hasAccess && !this.recordsDeleted) {
                await this.loadDemoRecords();
            }
        } catch (error) {
            this.showMessage('error', 'Error loading demo data: ' + this.getErrorMessage(error));
        } finally {
            this.isLoading = false;
        }
    }

    async loadDemoRecords() {
        const wrapper = await getDemoRecords();
        this.employees = wrapper.employees || [];
        this.projects = wrapper.projects || [];
        this.projectEmployees = wrapper.projectEmployees || [];
        this.timesheets = (wrapper.timesheets || []).map((ts) => ({
            id: ts.recordId,
            name: `${ts.employeeName} - ${ts.periodName}`,
            dates: ts.dateRange,
            status: ts.status,
            hours: ts.totalHours,
            _children: (ts.lineItems || []).map((item) => ({
                id: item.id,
                name: item.dateStr,
                projectOrType: item.projectOrType,
                hours: item.duration,
                description: item.description
            }))
        }));
    }

    async handleNextStep() {
        const step = this.nextStep;
        if (!step) {
            return;
        }
        this.isLoading = true;
        try {
            await step.action();
            this.showMessage('success', step.successMessage);
            await this.loadStatus();
        } catch (error) {
            this.isLoading = false;
            this.showMessage('error', this.getErrorMessage(error));
        }
    }

    async handleShowDeleteConfirm() {
        this.isLoading = true;
        try {
            this.deleteSummary = await getDeleteSummary();
            this.showDeleteConfirm = true;
            // Bring the confirmation (rendered below the tables) into view.
            requestAnimationFrame(() => {
                const panel = this.template.querySelector('.delete-confirm');
                if (panel) {
                    panel.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
            });
        } catch (error) {
            this.showMessage('error', 'Error loading demo records: ' + this.getErrorMessage(error));
        } finally {
            this.isLoading = false;
        }
    }

    handleCancelDelete() {
        this.showDeleteConfirm = false;
    }

    async handleConfirmDelete() {
        this.isDeleting = true;
        this.isLoading = true;
        try {
            await deleteDemoRecords();
            this.recordsDeleted = true;
            this.employees = [];
            this.projects = [];
            this.projectEmployees = [];
            this.timesheets = [];
            this.message = undefined;
        } catch (error) {
            this.showMessage('error', 'Error deleting demo records: ' + this.getErrorMessage(error));
        } finally {
            this.isDeleting = false;
            this.isLoading = false;
            this.showDeleteConfirm = false;
        }
    }

    async handleRowAction(event) {
        if (event.detail.action.name !== 'view') {
            return;
        }
        const url = await this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.detail.row.recordId || event.detail.row.id,
                actionName: 'view'
            }
        });
        window.open(url, '_blank');
    }

    handleDismissMessage() {
        this.message = undefined;
    }

    showMessage(variant, text) {
        this.message = { variant, text };
    }

    get approvedEmailBody() {
        return "{!dbt__Timesheet__c.dbt__Employee__c},\nYour {!dbt__Timesheet__c.Name} is Approved.\nComments : {!ApprovalRequest.Comments}";
    }

    get rejectedEmailBody() {
        return "{!dbt__Timesheet__c.dbt__Employee__c},\nYour {!dbt__Timesheet__c.Name} is Rejected.\nComments : {!ApprovalRequest.Comments}";
    }

    handleCopy(event) {
        const text = event.currentTarget.dataset.text;
        if (navigator.clipboard && window.isSecureContext) {
            navigator.clipboard.writeText(text)
                .then(() => this.showMessage('success', 'Copied to clipboard.'))
                .catch(() => this.fallbackCopyTextToClipboard(text));
        } else {
            this.fallbackCopyTextToClipboard(text);
        }
    }

    fallbackCopyTextToClipboard(text) {
        const textArea = document.createElement('textarea');
        textArea.value = text;
        // Avoid scrolling to bottom
        textArea.style.top = '0';
        textArea.style.left = '0';
        textArea.style.position = 'fixed';

        document.body.appendChild(textArea);
        textArea.focus();
        textArea.select();

        try {
            document.execCommand('copy');
            this.showMessage('success', 'Copied to clipboard.');
        } catch (err) {
            this.showMessage('error', 'Failed to copy text.');
        }

        document.body.removeChild(textArea);
    }

    getErrorMessage(error) {
        if (!error) return 'Unknown error';
        const body = error.body;
        if (typeof body === 'string') return body;
        if (Array.isArray(body) && body.length > 0) {
            return body.map((item) => item.message || JSON.stringify(item)).join(', ');
        }
        if (body) {
            if (body.message) return body.message;
            if (Array.isArray(body.pageErrors) && body.pageErrors.length > 0) {
                return body.pageErrors.map((item) => item.message).join(', ');
            }
            if (body.fieldErrors) {
                const fieldMessages = Object.values(body.fieldErrors).flat().map((fieldError) => fieldError.message).filter(Boolean);
                if (fieldMessages.length) return fieldMessages.join(', ');
            }
        }
        return error.message || JSON.stringify(error);
    }

    get messageClass() {
        const theme = this.message && this.message.variant === 'error' ? 'slds-theme_error' : 'slds-theme_success';
        return `slds-scoped-notification slds-media slds-media_center slds-m-bottom_medium ${theme}`;
    }

    get messageIcon() {
        return this.message && this.message.variant === 'error' ? 'utility:error' : 'utility:success';
    }

    get hasEmployees() { return this.employees.length > 0; }
    get hasProjects() { return this.projects.length > 0; }
    get hasProjectAssignments() { return this.projectEmployees.length > 0; }
    get hasTimesheets() { return this.timesheets.length > 0; }
    get hasChildEmployees() {
        return this.hasEmployees && !this.employees.some((emp) => emp.canCreateChildren);
    }
    get hasAnyRecords() {
        return this.hasEmployees || this.hasProjects;
    }

    get employeesLabel() { return `Employees (${this.employees.length})`; }
    get projectsLabel() { return `Projects (${this.projects.length})`; }
    get projectAssignmentsLabel() { return `Project Assignments (${this.projectEmployees.length})`; }
    get timesheetsLabel() { return `Timesheets (${this.timesheets.length})`; }

    /** First step whose records don't exist yet; undefined when everything is created. */
    get nextStep() {
        const done = {
            employee: this.hasEmployees,
            children: this.hasChildEmployees,
            projects: this.hasProjects,
            assignments: this.hasProjectAssignments,
            timesheets: this.hasTimesheets
        };
        return STEPS.find((step) => !done[step.value]);
    }

    get currentStep() {
        return this.nextStep ? this.nextStep.value : 'done';
    }

    get stepNumber() {
        return STEPS.indexOf(this.nextStep) + 1;
    }

    get stepCount() {
        return STEPS.length;
    }

    get showNoAccessMessage() {
        return !this.isLoading && !this.hasAccess;
    }

    get showDataView() {
        return this.hasAccess && !this.recordsDeleted;
    }

    get showProgress() {
        return this.showDataView && this.canCreate;
    }

    get showNextStep() {
        return this.showProgress && this.nextStep;
    }

    get showAllDone() {
        return this.showProgress && !this.nextStep;
    }

    get showCleanupOnlyNote() {
        return this.showDataView && !this.canCreate;
    }

    get showProductionWarning() {
        return this.showDataView && this.isProductionOrg;
    }

    get showRecords() {
        return this.showDataView && this.hasAnyRecords;
    }

    get showDeleteSection() {
        return this.showRecords && !this.showDeleteConfirm;
    }

    get activeSections() {
        const sections = [];
        if (this.hasEmployees) sections.push('employees');
        if (this.hasProjects) sections.push('projects');
        if (this.hasProjectAssignments) sections.push('projectEmployees');
        if (this.hasTimesheets) sections.push('timesheets');
        return sections;
    }
}
