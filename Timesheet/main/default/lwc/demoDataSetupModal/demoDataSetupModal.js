import LightningModal from 'lightning/modal';
import getDemoStatus from '@salesforce/apex/DemoDataController.getDemoStatus';
import getDemoRecords from '@salesforce/apex/DemoDataController.getDemoRecords';
import createDemoEmployee from '@salesforce/apex/DemoDataController.createDemoEmployee';
import createChildEmployees from '@salesforce/apex/DemoDataController.createChildEmployees';
import createDemoProjects from '@salesforce/apex/DemoDataController.createDemoProjects';
import createDemoProjectAssignments from '@salesforce/apex/DemoDataController.createDemoProjectAssignments';
import createDemoTimesheets from '@salesforce/apex/DemoDataController.createDemoTimesheets';
import getDeleteSummary from '@salesforce/apex/DemoDataController.getDeleteSummary';
import deleteDemoRecords from '@salesforce/apex/DemoDataController.deleteDemoRecords';
import saveDemoRecords from '@salesforce/apex/DemoDataController.saveDemoRecords';

// Plain link column so the browser opens the record in a new tab (no popup blocking).
const VIEW_ACTION = {
    label: '',
    fieldName: 'recordUrl',
    type: 'url',
    fixedWidth: 80,
    typeAttributes: {
        label: { fieldName: 'viewLabel' },
        tooltip: 'Open record in a new tab',
        target: '_blank'
    }
};

function withViewLink(row, recordId) {
    return { ...row, recordUrl: `${window.location.origin}/lightning/r/${recordId}/view`, viewLabel: 'View' };
}

/** "2026-09-14" -> "Mon, Sep 14" in the user's locale (date-local cells always show the year). */
function formatShortDate(isoDate) {
    if (!isoDate) {
        return '';
    }
    const [year, month, day] = isoDate.split('-').map(Number);
    return new Date(year, month - 1, day).toLocaleDateString(undefined, { weekday: 'short', month: 'short', day: 'numeric' });
}

// Setup steps in order. Each step is done once the records it creates exist.
const STEPS = [
    {
        value: 'employee',
        label: 'Employee',
        title: 'Create the demo employee',
        description: 'Creates "Demo Employee" linked to your user (no manager), so the Employee Overview shows the demo data as yours.',
        buttonLabel: 'Create Employee',
        successMessage: 'Demo employee created.',
        action: createDemoEmployee
    },
    {
        value: 'children',
        label: 'Child Employees',
        title: 'Create child employees',
        description: 'Creates two employees who report to you, so you can approve their timesheets. Skip this step to create demo data for yourself only; you can add them later from the Employees section.',
        buttonLabel: 'Create Child Employees',
        successMessage: 'Child employees created.',
        optional: true,
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

// Manual approval process guide, shown one step at a time.
const GUIDE_STEPS = [
    { value: 'emailTemplates', label: 'Email Templates' },
    { value: 'emailAlerts', label: 'Email Alerts' },
    { value: 'approvalProcess', label: 'Approval Process' },
    { value: 'initialSubmission', label: 'Submission Actions' },
    { value: 'approvalSteps', label: 'Approval Steps' },
    { value: 'finalApproval', label: 'Final Approval' },
    { value: 'finalRejection', label: 'Final Rejection' },
    { value: 'recallActions', label: 'Recall Actions' },
    { value: 'activate', label: 'Activate' }
];

/**
 * Full-size demo data popup, opened from demoDataPrompt on the Employee Overview:
 * guided creation, review and deletion of demo records, plus the approval process guide.
 */
export default class DemoDataSetupModal extends LightningModal {
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
    lineItems = [];
    userTimesheetsWithoutManager = false;

    // Set by the Skip button; once projects exist the children step counts as skipped without it.
    childrenSkipped = false;
    // Step clicked in the path; undefined follows the first step that isn't done.
    selectedStepValue;
    selectedTimesheetId;
    selectedTimesheetRows = [];

    // Inline edit state per editable table (employees, projects, projectEmployees).
    drafts = { employees: [], projects: [], projectEmployees: [] };
    tableErrors = {};

    showDeleteConfirm = false;
    isDeleting = false;
    deleteSummary;

    guideSteps = GUIDE_STEPS;
    guideStep = GUIDE_STEPS[0].value;

    // Columns: read-only fields first, then editable fields, then the View link. Read-only: picklists
    // and lookups (the datatable can't edit them natively), and fields that feed the accrual and
    // absence totals, which are only recalculated on timesheet approval (see EDITABLE_FIELDS in Apex).
    employeeColumns = [
        { label: 'Name', fieldName: 'name', initialWidth: 200 },
        { label: 'Manager', fieldName: 'manager' },
        { label: 'Employment Type', fieldName: 'employmentType' },
        { label: 'Accrual Start Date', fieldName: 'accrualStartDate', type: 'date-local' },
        { label: 'Accrual Divisor', fieldName: 'accrualDivisor', type: 'number' },
        { label: 'Extra Accrued Hours', fieldName: 'extraAccruedHours', type: 'number' },
        { label: 'Extra Absence Hours', fieldName: 'extraAbsenceHours', type: 'number' },
        { label: 'Total Accrued Hours', fieldName: 'totalAccruedHours', type: 'number' },
        { label: 'Total Absence Hours', fieldName: 'totalAbsenceHours', type: 'number' },
        { label: 'Email', fieldName: 'email', type: 'email', editable: true },
        { label: 'Active', fieldName: 'active', type: 'boolean', editable: true },
        VIEW_ACTION
    ];

    projectColumns = [
        { label: 'Name', fieldName: 'name' },
        { label: 'Billable', fieldName: 'billable' },
        { label: 'Active', fieldName: 'active', type: 'boolean', editable: true },
        { label: 'Start Date', fieldName: 'startDate', type: 'date-local', editable: true },
        { label: 'End Date', fieldName: 'endDate', type: 'date-local', editable: true },
        VIEW_ACTION
    ];

    projectAssignmentColumns = [
        { label: 'Employee', fieldName: 'employeeName' },
        { label: 'Project', fieldName: 'projectName' },
        { label: 'Hourly Rate', fieldName: 'hourlyRate', type: 'currency', editable: true },
        VIEW_ACTION
    ];

    timesheetColumns = [
        { label: 'Employee', fieldName: 'employeeName' },
        { label: 'Period', fieldName: 'periodName' },
        { label: 'Week', fieldName: 'dates', initialWidth: 190 },
        { label: 'Status', fieldName: 'status' },
        { label: 'Total Hours', fieldName: 'totalHours', type: 'number' },
        { label: 'Billable Hours', fieldName: 'billableHours', type: 'number' },
        VIEW_ACTION
    ];

    lineItemColumns = [
        { label: 'Date', fieldName: 'dateLabel', initialWidth: 110 },
        { label: 'Project / Absence', fieldName: 'projectOrAbsence' },
        { label: 'Activity', fieldName: 'activity' },
        { label: 'Hours', fieldName: 'duration', type: 'number', initialWidth: 70 }
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
        this.employees = (wrapper.employees || []).map((row) => withViewLink(row, row.recordId));
        this.projects = (wrapper.projects || []).map((row) => withViewLink(row, row.recordId));
        this.projectEmployees = (wrapper.projectEmployees || []).map((row) => withViewLink(row, row.recordId));
        this.userTimesheetsWithoutManager = wrapper.userTimesheetsWithoutManager === true;
        const timesheets = wrapper.timesheets || [];
        this.timesheets = timesheets.map((ts) => withViewLink({
            recordId: ts.recordId,
            employeeName: ts.employeeName,
            periodName: ts.periodName,
            dates: ts.dateRange,
            status: ts.status,
            totalHours: ts.totalHours,
            billableHours: ts.billableHours
        }, ts.recordId));
        this.lineItems = timesheets.flatMap((ts) => (ts.lineItems || []).map((item) => ({
            ...item,
            recordId: item.id,
            dateLabel: formatShortDate(item.lineDate),
            projectOrAbsence: item.projectName || item.absenceCategory
        })));
        // Keep the selected timesheet across reloads; default to the first one.
        if (!this.timesheets.some((ts) => ts.recordId === this.selectedTimesheetId)) {
            this.selectedTimesheetId = this.timesheets.length ? this.timesheets[0].recordId : undefined;
        }
        this.selectedTimesheetRows = this.selectedTimesheetId ? [this.selectedTimesheetId] : [];
    }

    handleSkipStep() {
        this.childrenSkipped = true;
        this.selectedStepValue = undefined;
        this.showMessage('success', 'Child employees skipped. You can add them later from the Employees section.');
    }

    /** Path click: go back to any step up to the next one to do; later steps stay locked. */
    handleStepClick(event) {
        const value = event.currentTarget.dataset.step;
        const index = STEPS.findIndex((step) => step.value === value);
        const nextIndex = this.nextStep ? STEPS.indexOf(this.nextStep) : STEPS.length;
        if (value === 'done' || index === nextIndex) {
            this.selectedStepValue = undefined;
        } else if (index >= 0 && index < nextIndex) {
            this.selectedStepValue = value;
        }
    }

    /** From a completed step, move one step right; reaching the next step to do clears the selection. */
    handleStepContinue() {
        const index = STEPS.indexOf(this.activeStep);
        const nextIndex = this.nextStep ? STEPS.indexOf(this.nextStep) : STEPS.length;
        this.selectedStepValue = index + 1 < nextIndex ? STEPS[index + 1].value : undefined;
    }

    async handleAddChildEmployees() {
        this.isLoading = true;
        try {
            await createChildEmployees();
            this.selectedStepValue = undefined;
            this.showMessage('success', 'Child employees created. Create their assignments and timesheets with the next steps.');
            await this.loadStatus();
        } catch (error) {
            this.isLoading = false;
            this.showMessage('error', this.getErrorMessage(error));
        }
    }

    /** One timesheet is always selected: a deselect re-selects the current row so grid and line items stay in sync. */
    handleTimesheetSelect(event) {
        const [row] = event.detail.selectedRows;
        if (row) {
            this.selectedTimesheetId = row.recordId;
        }
        this.selectedTimesheetRows = this.selectedTimesheetId ? [this.selectedTimesheetId] : [];
    }

    /** Saves inline edits of one table; rows that fail keep their drafts and show the error. */
    async handleSave(event) {
        const table = event.target.dataset.table;
        const draftValues = event.detail.draftValues;
        this.isLoading = true;
        let errors;
        try {
            errors = await saveDemoRecords({ tableKey: table, drafts: draftValues });
        } catch (error) {
            this.isLoading = false;
            this.showMessage('error', 'Error saving changes: ' + this.getErrorMessage(error));
            return;
        }
        const failedIds = Object.keys(errors || {});
        this.drafts = { ...this.drafts, [table]: draftValues.filter((draft) => failedIds.includes(draft.recordId)) };
        this.tableErrors = { ...this.tableErrors, [table]: this.toTableErrors(errors) };
        const savedCount = draftValues.length - failedIds.length;
        if (failedIds.length) {
            this.showMessage('error', `${failedIds.length} of ${draftValues.length} records could not be saved. See the highlighted rows.`);
        } else {
            this.showMessage('success', 'Changes saved.');
        }
        // A failed refresh doesn't undo the save, so report it separately.
        try {
            await this.loadDemoRecords();
        } catch (error) {
            this.showMessage('error', `${savedCount} records saved, but the tables could not be refreshed: ${this.getErrorMessage(error)}`);
        } finally {
            this.isLoading = false;
        }
    }

    handleCancelEdit(event) {
        const table = event.target.dataset.table;
        this.drafts = { ...this.drafts, [table]: [] };
        this.tableErrors = { ...this.tableErrors, [table]: undefined };
    }

    /** { recordId: message } from Apex to the lightning-datatable errors format. */
    toTableErrors(errors) {
        const entries = Object.entries(errors || {});
        if (!entries.length) {
            return undefined;
        }
        const rows = Object.fromEntries(entries.map(([recordId, message]) => [recordId, { title: 'Not saved', messages: [message] }]));
        return { rows, table: { title: 'Some records could not be saved', messages: entries.map(([, message]) => message) } };
    }

    async handleNextStep() {
        const step = this.activeStep;
        if (!step) {
            return;
        }
        this.isLoading = true;
        try {
            await step.action();
            this.selectedStepValue = undefined;
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
            this.lineItems = [];
            this.message = undefined;
        } catch (error) {
            this.showMessage('error', 'Error deleting demo records: ' + this.getErrorMessage(error));
        } finally {
            this.isDeleting = false;
            this.isLoading = false;
            this.showDeleteConfirm = false;
        }
    }

    handleGuideStepClick(event) {
        this.guideStep = event.currentTarget.dataset.step;
    }

    handleGuidePrevious() {
        this.moveGuideStep(-1);
    }

    handleGuideNext() {
        this.moveGuideStep(1);
    }

    moveGuideStep(offset) {
        const index = this.guideStepIndex + offset;
        if (index >= 0 && index < GUIDE_STEPS.length) {
            this.guideStep = GUIDE_STEPS[index].value;
        }
    }

    get guideStepIndex() {
        return GUIDE_STEPS.findIndex((step) => step.value === this.guideStep);
    }

    get guideStepNumber() { return this.guideStepIndex + 1; }
    get guideStepCount() { return GUIDE_STEPS.length; }
    get isFirstGuideStep() { return this.guideStepIndex === 0; }
    get isLastGuideStep() { return this.guideStepIndex === GUIDE_STEPS.length - 1; }

    /** { emailTemplates: true, emailAlerts: false, ... } for the template's lwc:if checks. */
    get guideStepVisible() {
        return Object.fromEntries(GUIDE_STEPS.map((step) => [step.value, step.value === this.guideStep]));
    }

    handleClose() {
        this.close('closed');
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

    get demoDataNote() {
        return this.userTimesheetsWithoutManager
            ? "For demo purposes, the child employees are not linked to any user, and your Demo Employee's timesheets have no manager. In real use these fields are required: link every employee to a user and make sure every employee has a manager."
            : "For demo purposes, the child employees are not linked to any user, and your Demo Employee's timesheets have a manager only if your user has one. In real use every employee must be linked to a user and have a manager.";
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

    /** No child employees, and the user skipped them (or moved on to projects, which implies it). */
    get isChildrenSkipped() {
        return this.hasEmployees && !this.hasChildEmployees && (this.childrenSkipped || this.hasProjects);
    }

    get employeesLabel() { return `Employees (${this.employees.length})`; }
    get projectsLabel() { return `Projects (${this.projects.length})`; }
    get projectAssignmentsLabel() { return `Project Assignments (${this.projectEmployees.length})`; }
    get timesheetsLabel() { return `Timesheets (${this.timesheets.length}) & Line Items (${this.lineItems.length})`; }

    get selectedTimesheet() {
        return this.timesheets.find((ts) => ts.recordId === this.selectedTimesheetId);
    }

    get selectedLineItems() {
        return this.lineItems.filter((item) => item.timesheetId === this.selectedTimesheetId);
    }

    get hasSelectedLineItems() {
        return this.selectedLineItems.length > 0;
    }

    get lineItemsHeading() {
        const ts = this.selectedTimesheet;
        return ts ? `Line Items: ${ts.employeeName}, ${ts.periodName} (${ts.dates})` : 'Line Items';
    }

    get showAddChildEmployees() {
        return this.canCreate && this.isChildrenSkipped;
    }

    /**
     * First step that is not done yet; undefined when everything is created. Assignments and
     * timesheets are done only when every employee has them, so child employees added later
     * send the user back through those steps (which only create the missing records).
     */
    get nextStep() {
        const done = this.doneSteps;
        return STEPS.find((step) => !done[step.value]);
    }

    /** Which steps are done; a skipped children step counts as done. */
    get doneSteps() {
        const everyEmployee = (countField) => this.hasEmployees && this.employees.every((emp) => emp[countField] > 0);
        return {
            employee: this.hasEmployees,
            children: this.hasChildEmployees || this.isChildrenSkipped,
            projects: this.hasProjects,
            assignments: everyEmployee('assignmentCount'),
            timesheets: everyEmployee('timesheetCount')
        };
    }

    /** Step shown in the card: the one picked in the path, otherwise the next one to do. */
    get activeStep() {
        return STEPS.find((step) => step.value === this.selectedStepValue) || this.nextStep;
    }

    /** A skipped children step is not complete, so going back to it offers to create them. */
    get isActiveStepComplete() {
        const step = this.activeStep;
        if (!step) {
            return false;
        }
        return step.value === 'children' ? this.hasChildEmployees : this.doneSteps[step.value];
    }

    get showSkipButton() {
        return this.activeStep && this.activeStep.optional && !this.isActiveStepComplete && !this.isChildrenSkipped;
    }

    /** Path shown above the next-step card; the extra "Ready" step is current once everything exists. */
    get steps() {
        const steps = STEPS.map((step) => (step.value === 'children' && this.isChildrenSkipped
            ? { value: step.value, label: `${step.label} (Skipped)` }
            : { value: step.value, label: step.label }));
        return [...steps, { value: 'done', label: 'Ready' }];
    }

    // The path marks steps left of the current one as completed and the ones right of it as inactive.
    get currentStep() {
        return this.activeStep ? this.activeStep.value : 'done';
    }

    get stepNumber() {
        return STEPS.indexOf(this.activeStep) + 1;
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
        return this.showProgress && this.activeStep;
    }

    get showAllDone() {
        return this.showProgress && !this.activeStep;
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
