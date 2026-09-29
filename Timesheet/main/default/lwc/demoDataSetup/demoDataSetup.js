import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
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

export default class DemoDataSetup extends NavigationMixin(LightningElement) {
    isLoading = true;
    hasAccess = false;
    canCreate = false;
    hasEmployee = false;
    isProductionOrg = false;
    showSections = false;
    recordsDeleted = false;

    employees = [];
    projects = [];
    projectEmployees = [];
    timesheets = [];
    activeSections = ['employees', 'projects', 'projectEmployees', 'timesheets'];

    showDeleteModal = false;
    isDeleting = false;
    deleteSummary;

    lineItemColumns = [
        { label: 'Date', fieldName: 'dateStr', type: 'text', initialWidth: 120 },
        { label: 'Project / Type', fieldName: 'projectOrType', type: 'text' },
        { label: 'Hours', fieldName: 'duration', type: 'number', initialWidth: 100 },
        { label: 'Description', fieldName: 'description', type: 'text' }
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
            this.hasEmployee = status.hasEmployee === true;
            this.isProductionOrg = status.isProductionOrg === true;
            if (this.hasAccess && !this.recordsDeleted) {
                await this.loadDemoRecords();
            }
        } catch (error) {
            this.showToast('Error', 'Error loading demo status: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    async loadDemoRecords() {
        const wrapper = await getDemoRecords();
        this.employees = (wrapper.employees || []).map((emp) => ({
            ...emp,
            showCreateChildren: this.canCreate && emp.canCreateChildren
        }));
        this.projects = wrapper.projects || [];
        this.projectEmployees = wrapper.projectEmployees || [];
        this.timesheets = (wrapper.timesheets || []).map((ts) => ({
            ...ts,
            isOpen: false,
            iconName: 'utility:chevronright',
            toggleLabel: 'Show line items',
            hasLineItems: ts.lineItems && ts.lineItems.length > 0
        }));
    }

    handleShowSections() {
        this.showSections = true;
    }

    handleCreateEmployee() {
        this.runCreate(createDemoEmployee, 'Demo employee created.');
    }

    handleCreateChildEmployees() {
        this.runCreate(createChildEmployees, 'Child employees created.');
    }

    handleCreateProjects() {
        this.runCreate(createDemoProjects, 'Demo projects created.');
    }

    handleCreateProjectAssignments() {
        this.runCreate(createDemoProjectAssignments, 'Project assignments created.');
    }

    handleCreateTimesheets() {
        this.runCreate(createDemoTimesheets, 'Demo timesheets created.');
    }

    async runCreate(apexMethod, successMessage) {
        this.isLoading = true;
        try {
            await apexMethod();
            this.showToast('Success', successMessage, 'success');
            await this.loadStatus();
        } catch (error) {
            this.isLoading = false;
            this.showToast('Error', this.getErrorMessage(error), 'error');
        }
    }

    async handleOpenDeleteModal() {
        this.isLoading = true;
        try {
            this.deleteSummary = await getDeleteSummary();
            this.showDeleteModal = true;
        } catch (error) {
            this.showToast('Error', 'Error loading demo records: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isLoading = false;
        }
    }

    handleCancelDelete() {
        this.showDeleteModal = false;
    }

    async handleConfirmDelete() {
        this.isDeleting = true;
        try {
            await deleteDemoRecords();
            this.showToast('Success', 'All demo records have been deleted.', 'success');
            this.recordsDeleted = true;
            this.employees = [];
            this.projects = [];
            this.projectEmployees = [];
            this.timesheets = [];
        } catch (error) {
            this.showToast('Error', 'Error deleting demo records: ' + this.getErrorMessage(error), 'error');
        } finally {
            this.isDeleting = false;
            this.showDeleteModal = false;
        }
    }

    handleModalKeydown(event) {
        if (event.key === 'Escape' && !this.isDeleting) {
            this.handleCancelDelete();
        }
    }

    handleToggleTimesheet(event) {
        const recordId = event.currentTarget.dataset.id;
        this.timesheets = this.timesheets.map((ts) => {
            if (ts.recordId !== recordId) {
                return ts;
            }
            const isOpen = !ts.isOpen;
            return {
                ...ts,
                isOpen,
                iconName: isOpen ? 'utility:chevrondown' : 'utility:chevronright',
                toggleLabel: isOpen ? 'Hide line items' : 'Show line items'
            };
        });
    }

    async handleViewRecord(event) {
        const url = await this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.currentTarget.dataset.id,
                actionName: 'view'
            }
        });
        window.open(url, '_blank');
    }

    handleClose() {
        this.dispatchEvent(new CustomEvent('close'));
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
                .then(() => this.showToast('Success', 'Copied to clipboard', 'success'))
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
            this.showToast('Success', 'Copied to clipboard', 'success');
        } catch (err) {
            this.showToast('Error', 'Failed to copy text', 'error');
        }

        document.body.removeChild(textArea);
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
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

    get employeesLabel() { return `Employees (${this.employees.length})`; }
    get projectsLabel() { return `Projects (${this.projects.length})`; }
    get projectAssignmentsLabel() { return `Project Assignments (${this.projectEmployees.length})`; }
    get timesheetsLabel() { return `Timesheets (${this.timesheets.length})`; }

    get showSetupPrompt() {
        return !this.isLoading && this.hasAccess && this.canCreate && !this.hasEmployee && !this.showSections && !this.recordsDeleted;
    }

    get showRecordsView() {
        return !this.isLoading && this.hasAccess && (this.hasEmployee || this.showSections || !this.canCreate) && !this.recordsDeleted;
    }

    get showNoAccessMessage() {
        return !this.isLoading && !this.hasAccess;
    }

    get showDeletedMessage() {
        return !this.isLoading && this.recordsDeleted;
    }

    get showCleanupOnlyNote() {
        return this.showRecordsView && !this.canCreate;
    }

    get showProductionWarning() {
        return !this.isLoading && this.hasAccess && this.isProductionOrg && !this.recordsDeleted;
    }

    get hasEmployees() { return this.employees.length > 0; }
    get hasProjects() { return this.projects.length > 0; }
    get hasProjectAssignments() { return this.projectEmployees.length > 0; }
    get hasTimesheets() { return this.timesheets.length > 0; }
    get hasChildEmployees() {
        return this.hasEmployees && !this.employees.some((emp) => emp.canCreateChildren);
    }

    get employeesHint() {
        return this.hasEmployees ? null : 'No demo employees.';
    }
    get projectsHint() {
        if (this.hasProjects) return null;
        return this.hasChildEmployees || !this.canCreate ? 'No demo projects.' : 'Create the demo employee and its child employees first.';
    }
    get projectAssignmentsHint() {
        if (this.hasProjectAssignments) return null;
        return this.hasProjects || !this.canCreate ? 'No project assignments.' : 'Create the demo projects first.';
    }
    get timesheetsHint() {
        if (this.hasTimesheets) return null;
        return this.hasProjectAssignments || !this.canCreate ? 'No demo timesheets.' : 'Create the project assignments first.';
    }

    get showNewEmployee() { return this.canCreate && !this.hasEmployees; }
    get showNewProjects() { return this.canCreate && this.hasChildEmployees && !this.hasProjects; }
    get showNewProjectAssignments() { return this.canCreate && this.hasProjects && !this.hasProjectAssignments; }
    get showNewTimesheets() { return this.canCreate && this.hasProjectAssignments && !this.hasTimesheets; }

    get showDeleteButton() {
        return this.showRecordsView && (this.hasEmployees || this.hasProjects);
    }
}
