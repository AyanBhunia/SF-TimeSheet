import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import Toast from 'lightning/toast';
import getDemoData from '@salesforce/apex/DemoDataController.getDemoData';
import createDemoEmployees from '@salesforce/apex/DemoDataController.createDemoEmployees';
import createDemoProjects from '@salesforce/apex/DemoDataController.createDemoProjects';
import createDemoProjectAssignments from '@salesforce/apex/DemoDataController.createDemoProjectAssignments';
import createDemoTimesheets from '@salesforce/apex/DemoDataController.createDemoTimesheets';
import createDemoLineItems from '@salesforce/apex/DemoDataController.createDemoLineItems';
import deleteDemoRecords from '@salesforce/apex/DemoDataController.deleteDemoRecords';

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

// Read-only columns of the "records this step will create" table, per step.
const PREVIEW_COLUMNS = {
    employee: [
        { label: 'Name', fieldName: 'name', initialWidth: 200 },
        { label: 'Manager', fieldName: 'manager' },
        { label: 'Employment Type', fieldName: 'employmentType' },
        { label: 'Accrual Start Date', fieldName: 'accrualStartDate', type: 'date-local' },
        { label: 'Accrual Divisor', fieldName: 'accrualDivisor', type: 'number' },
        { label: 'Extra Accrued Hours', fieldName: 'extraAccruedHours', type: 'number' },
        { label: 'Email', fieldName: 'email', type: 'email' },
        { label: 'Active', fieldName: 'active', type: 'boolean' }
    ],
    projects: [
        { label: 'Name', fieldName: 'name' },
        { label: 'Billable', fieldName: 'billable' },
        { label: 'Active', fieldName: 'active', type: 'boolean' }
    ],
    assignments: [
        { label: 'Employee', fieldName: 'employeeName' },
        { label: 'Project', fieldName: 'projectName' },
        { label: 'Hourly Rate', fieldName: 'hourlyRate', type: 'currency' }
    ],
    timesheets: [
        { label: 'Employee', fieldName: 'employeeName' },
        { label: 'Period', fieldName: 'periodName' },
        { label: 'Week', fieldName: 'dateRange' },
        { label: 'Status', fieldName: 'status' }
    ],
    lineItems: [
        { label: 'Employee', fieldName: 'employeeName' },
        { label: 'Period', fieldName: 'periodName' },
        { label: 'Date', fieldName: 'dateLabel', initialWidth: 110 },
        { label: 'Project / Absence', fieldName: 'projectOrAbsence' },
        { label: 'Activity', fieldName: 'activity' },
        { label: 'Hours', fieldName: 'duration', type: 'number', initialWidth: 70 },
        { label: 'Timesheet Status', fieldName: 'status' }
    ]
};

// Setup steps in order. Each step is done once the records it creates exist; the data model step creates
// nothing. action: the Apex call, which returns the changed part of the popup's data.
const STEPS = [
    {
        value: 'model',
        label: 'Data Model',
        title: 'How the demo data fits together',
        description: 'The next steps create demo records in these objects, one step at a time. Each step shows the records it will create before you create them.'
    },
    {
        value: 'employee',
        label: 'Employees',
        title: 'Create demo employees',
        description: 'Creates "Demo Employee" linked to your user (no manager), so the Employee Overview shows the demo data as yours. Child employees report to you, so you can approve their timesheets.',
        buttonLabel: 'Create Employees',
        successMessage: 'Demo employees created.',
        action: (cmp) => createDemoEmployees({ includeChildren: cmp.includeChildren })
    },
    {
        value: 'projects',
        label: 'Projects',
        title: 'Create demo projects',
        description: 'Creates a billable, a non-billable and a legacy project.',
        buttonLabel: 'Create Projects',
        successMessage: 'Demo projects created.',
        action: () => createDemoProjects()
    },
    {
        value: 'assignments',
        label: 'Assignments',
        title: 'Assign employees to projects',
        description: 'Assigns every demo employee to every demo project at an hourly rate of 150.',
        buttonLabel: 'Create Assignments',
        successMessage: 'Project assignments created.',
        action: () => createDemoProjectAssignments()
    },
    {
        value: 'timesheets',
        label: 'Timesheets',
        title: 'Create demo timesheets',
        description: 'Creates four weekly timesheets per employee, from two weeks ago to next week. They start with the status New and no hours.',
        buttonLabel: 'Create Timesheets',
        successMessage: 'Demo timesheets created.',
        action: () => createDemoTimesheets()
    },
    {
        value: 'lineItems',
        label: 'Line Items',
        title: 'Create timesheet line items',
        description: 'Logs hours on the timesheets up to this week; next week stays empty. The two oldest weeks are then approved, and the legacy project is deactivated to show hours logged on an inactive project.',
        buttonLabel: 'Create Line Items',
        successMessage: 'Line items created.',
        action: () => createDemoLineItems()
    }
];

// Preview tables with more rows than this get a fixed height and scroll.
const PREVIEW_SCROLL_ROWS = 10;

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
 * Full-size demo data popup, opened from demoDataPrompt on the Employee Overview: guided creation, review
 * and deletion of demo records, plus the approval process guide. One Apex call loads everything (records and
 * the blueprint the previews are built from); each Create or Delete is one more call. Fires "datachange"
 * (detail.hasDemoData) after records are created or deleted.
 */
export default class DemoDataSetupModal extends LightningModal {
    /** Set by demoDataPrompt from the cached org check. */
    @api isProductionOrg = false;

    isLoading = true;
    isLoaded = false;
    recordsDeleted = false;
    message;

    // What the demo creates, from getDemoData(); previews are built from it.
    blueprint;
    employees = [];
    projects = [];
    projectEmployees = [];
    timesheets = [];
    lineItems = [];
    userTimesheetsWithoutManager = false;

    // Set by Next on the data model step; once employees exist that step is done anyway.
    modelReviewed = false;
    // Employee step checkbox. Final once the employees exist: child employees can't be added later.
    includeChildren = true;
    // Step clicked in the path; undefined follows the first step that isn't done.
    selectedStepValue;
    selectedTimesheetId;
    selectedTimesheetRows = [];

    showDeleteConfirm = false;
    isDeleting = false;

    // Tab shown in the popup; the footer's step navigation belongs to the Demo Data tab.
    activeTab = 'demoData';

    guideSteps = GUIDE_STEPS;
    guideStep = GUIDE_STEPS[0].value;

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
        { label: 'Email', fieldName: 'email', type: 'email' },
        { label: 'Active', fieldName: 'active', type: 'boolean' },
        VIEW_ACTION
    ];

    projectColumns = [
        { label: 'Name', fieldName: 'name' },
        { label: 'Billable', fieldName: 'billable' },
        { label: 'Active', fieldName: 'active', type: 'boolean' },
        { label: 'Start Date', fieldName: 'startDate', type: 'date-local' },
        { label: 'End Date', fieldName: 'endDate', type: 'date-local' },
        VIEW_ACTION
    ];

    projectAssignmentColumns = [
        { label: 'Employee', fieldName: 'employeeName' },
        { label: 'Project', fieldName: 'projectName' },
        { label: 'Hourly Rate', fieldName: 'hourlyRate', type: 'currency' },
        VIEW_ACTION
    ];

    timesheetColumns = [
        { label: 'Employee', fieldName: 'employeeName' },
        { label: 'Period', fieldName: 'periodName' },
        { label: 'Week', fieldName: 'dateRange', initialWidth: 190 },
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
        this.load();
    }

    async load() {
        this.isLoading = true;
        try {
            this.applyState(await getDemoData());
            this.isLoaded = true;
        } catch (error) {
            this.showMessage('error', 'Error loading demo data: ' + this.getErrorMessage(error));
        } finally {
            this.isLoading = false;
        }
    }

    /** Applies a DemoState from Apex. A list it leaves null is unchanged, so the current rows stay. */
    applyState(state) {
        if (state.blueprint) {
            this.blueprint = state.blueprint;
        }
        if (state.projects) {
            this.projects = state.projects.map((row) => withViewLink(row, row.recordId));
        }
        if (!state.employees) {
            return;
        }
        this.employees = state.employees.map((row) => withViewLink(row, row.recordId));
        this.projectEmployees = state.projectEmployees.map((row) => withViewLink(row, row.recordId));
        this.userTimesheetsWithoutManager = state.userTimesheetsWithoutManager === true;
        this.timesheets = state.timesheets.map((ts) => withViewLink(ts, ts.recordId));
        this.lineItems = state.timesheets.flatMap((ts) => ts.lineItems.map((item) => ({
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

    /**
     * Rows the given step will create: the blueprint's records minus what exists. Mirrors the "skip what
     * exists" rules of the matching Apex create method.
     */
    buildPreviewRows(stepValue) {
        const bp = this.blueprint;
        if (!bp) {
            return [];
        }
        switch (stepValue) {
            case 'employee':
                return bp.employees.filter((emp) => this.includeChildren || !emp.isChild);
            case 'projects': {
                const existing = new Set(this.projects.map((proj) => proj.name));
                return bp.projects.filter((proj) => !existing.has(proj.name));
            }
            case 'assignments':
                return this.employees.flatMap((emp) => this.projects
                    .filter((proj) => !this.projectEmployees.some((pe) => pe.employeeId === emp.recordId && pe.projectId === proj.recordId))
                    .map((proj) => ({ employeeName: emp.name, projectName: proj.name, hourlyRate: bp.hourlyRate })));
            case 'timesheets':
                return this.employees.flatMap((emp) => bp.weeks
                    .filter((week) => !this.timesheets.some((ts) => ts.employeeId === emp.recordId && ts.startDate === week.startDate))
                    .map((week) => ({ employeeName: emp.name, periodName: week.periodName, dateRange: week.dateRange, status: 'New' })));
            case 'lineItems':
                return this.timesheets
                    .filter((ts) => ts.status === 'New' && !this.lineItems.some((item) => item.timesheetId === ts.recordId))
                    .flatMap((ts) => {
                        const week = bp.weeks.find((w) => w.startDate === ts.startDate);
                        return (week ? week.lineItems : []).map((item) => ({
                            employeeName: ts.employeeName,
                            periodName: week.periodName,
                            dateLabel: formatShortDate(item.lineDate),
                            projectOrAbsence: item.projectName || item.absenceCategory,
                            activity: item.activity,
                            duration: item.duration,
                            status: week.approvalRound > 0 ? 'Approved' : ts.status
                        }));
                    });
            default:
                return [];
        }
    }

    handleIncludeChildrenChange(event) {
        this.includeChildren = event.target.checked;
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

    /** Moves one step right, once the active step is done; after the last step comes Ready. */
    handleNextStep() {
        const step = this.activeStep;
        if (!step) {
            return;
        }
        if (step.value === 'model') {
            this.modelReviewed = true;
        }
        if (!this.doneSteps[step.value]) {
            return;
        }
        const next = STEPS[STEPS.indexOf(step) + 1];
        this.selectedStepValue = next ? next.value : undefined;
    }

    /** Moves one step left; from Ready back to the last step. */
    handlePreviousStep() {
        const index = this.activeStep ? STEPS.indexOf(this.activeStep) : STEPS.length;
        if (index > 0) {
            this.selectedStepValue = STEPS[index - 1].value;
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

    /** Creates the active step's records and shows them; the popup stays on the step until Next. */
    async handleCreateStep() {
        const step = this.activeStep;
        if (!step || !step.action) {
            return;
        }
        this.isLoading = true;
        try {
            this.applyState(await step.action(this));
            this.selectedStepValue = step.value;
            this.message = undefined;
            this.showMessage('success', step.successMessage);
            this.notifyDataChange();
        } catch (error) {
            this.showMessage('error', this.getErrorMessage(error));
        } finally {
            this.isLoading = false;
        }
    }

    handleShowDeleteConfirm() {
        this.showDeleteConfirm = true;
        // Bring the confirmation (rendered below the tables) into view.
        requestAnimationFrame(() => {
            const panel = this.template.querySelector('.delete-confirm');
            if (panel) {
                panel.scrollIntoView({ behavior: 'smooth', block: 'center' });
            }
        });
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
            this.notifyDataChange();
        } catch (error) {
            this.showMessage('error', 'Error deleting demo records: ' + this.getErrorMessage(error));
        } finally {
            this.isDeleting = false;
            this.isLoading = false;
            this.showDeleteConfirm = false;
        }
    }

    /** Tells demoDataPrompt whether demo data exists now, so its card is right without asking the server. */
    notifyDataChange() {
        this.dispatchEvent(new CustomEvent('datachange', { detail: { hasDemoData: this.hasAnyRecords } }));
    }

    /** Counts for the delete confirmation, from the loaded rows. */
    get deleteSummary() {
        return {
            lineItems: this.lineItems.length,
            timesheets: this.timesheets.length,
            projectEmployees: this.projectEmployees.length,
            projects: this.projects.length,
            employees: this.employees.length
        };
    }

    handleTabActive(event) {
        this.activeTab = event.target.value;
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

    get isFirstGuideStep() { return this.guideStepIndex === 0; }
    get isLastGuideStep() { return this.guideStepIndex === GUIDE_STEPS.length - 1; }

    /** { emailTemplates: true, emailAlerts: false, ... } for the template's lwc:if checks. */
    get guideStepVisible() {
        return Object.fromEntries(GUIDE_STEPS.map((step) => [step.value, step.value === this.guideStep]));
    }

    handleDismissMessage() {
        this.message = undefined;
    }

    /** Success messages show as a toast; errors stay on the page until dismissed. */
    showMessage(variant, text) {
        if (variant === 'success') {
            Toast.show({ label: text, variant: 'success' }, this);
            return;
        }
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
        const children = this.hasChildEmployees ? 'the child employees are not linked to any user, and ' : '';
        return this.userTimesheetsWithoutManager
            ? `For demo purposes, ${children}your Demo Employee's timesheets have no manager. In real use these fields are required: link every employee to a user and make sure every employee has a manager.`
            : `For demo purposes, ${children}your Demo Employee's timesheets have a manager only if your user has one. In real use every employee must be linked to a user and have a manager.`;
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
        return this.employees.some((emp) => emp.isChild);
    }
    get hasAnyRecords() {
        return this.hasEmployees || this.hasProjects;
    }

    get employeesLabel() { return `Employees (${this.employees.length})`; }
    get projectsLabel() { return `Projects (${this.projects.length})`; }
    get projectAssignmentsLabel() { return `Project Assignments (${this.projectEmployees.length})`; }
    get timesheetsLabel() { return `Timesheets (${this.timesheets.length}) & Line Items (${this.lineItems.length})`; }
    get timesheetsOnlyLabel() { return `Timesheets (${this.timesheets.length})`; }

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
        return ts ? `Line Items: ${ts.employeeName}, ${ts.periodName} (${ts.dateRange})` : 'Line Items';
    }

    /**
     * First step that is not done yet; undefined when everything is created. Assignments and
     * timesheets are done only when every employee has them; those steps only create the missing records.
     */
    get nextStep() {
        const done = this.doneSteps;
        return STEPS.find((step) => !done[step.value]);
    }

    /** Which steps are done. */
    get doneSteps() {
        const everyEmployee = (countField) => this.hasEmployees && this.employees.every((emp) => emp[countField] > 0);
        return {
            model: this.modelReviewed || this.hasEmployees,
            employee: this.hasEmployees,
            projects: this.hasProjects,
            assignments: everyEmployee('assignmentCount'),
            timesheets: everyEmployee('timesheetCount'),
            lineItems: this.lineItems.length > 0
        };
    }

    /** Step shown in the card: the one picked in the path, otherwise the next one to do. */
    get activeStep() {
        return STEPS.find((step) => step.value === this.selectedStepValue) || this.nextStep;
    }

    get isActiveStepComplete() {
        return Boolean(this.activeStep && this.doneSteps[this.activeStep.value]);
    }

    get isModelStep() {
        return Boolean(this.activeStep && this.activeStep.value === 'model');
    }

    /** The data model step creates nothing, so it has no Done badge or create button. */
    get showStepDoneBadge() {
        return this.isActiveStepComplete && !this.isModelStep;
    }

    get showCreateButton() {
        return Boolean(this.activeStep && this.activeStep.action && !this.isActiveStepComplete);
    }

    get showStepNavigation() {
        return this.showProgress && this.activeTab === 'demoData';
    }

    /** The step's create button sits in the footer, left of Next. */
    get showFooterCreateButton() {
        return this.showStepNavigation && this.showCreateButton;
    }

    get showGuideNavigation() {
        return this.activeTab === 'approvalGuide';
    }

    get isPreviousDisabled() {
        return this.isLoading || this.isModelStep;
    }

    /** Next unlocks once the step's records are created; the data model step has nothing to create. */
    get isNextDisabled() {
        return this.isLoading || !this.activeStep || !(this.isModelStep || this.isActiveStepComplete);
    }

    /** The child employee choice, until the employees exist. */
    get showIncludeChildren() {
        return Boolean(this.activeStep && this.activeStep.value === 'employee' && !this.isActiveStepComplete);
    }

    /** Read-only table of the records the active step will create, shown before they are created. */
    get showPreview() {
        return Boolean(this.showProgress && this.activeStep && this.activeStep.action && !this.isActiveStepComplete);
    }

    get previewRows() {
        if (!this.showPreview) {
            return [];
        }
        return this.buildPreviewRows(this.activeStep.value).map((row, index) => ({ ...row, key: String(index) }));
    }

    get previewColumns() {
        return this.activeStep ? PREVIEW_COLUMNS[this.activeStep.value] : [];
    }

    get previewHeading() {
        return `Records this step will create (${this.previewRows.length})`;
    }

    get hasPreviewRows() {
        return this.previewRows.length > 0;
    }

    get previewTableClass() {
        return this.previewRows.length > PREVIEW_SCROLL_ROWS ? 'preview-table preview-table_scroll' : 'preview-table';
    }

    /** Path shown above the next-step card; the extra "Ready" step is current once everything exists. */
    get steps() {
        return [...STEPS.map((step) => ({ value: step.value, label: step.label })), { value: 'done', label: 'Ready' }];
    }

    // The path marks steps left of the current one as completed and the ones right of it as inactive.
    get currentStep() {
        return this.activeStep ? this.activeStep.value : 'done';
    }

    get showDataView() {
        return this.isLoaded && !this.recordsDeleted;
    }

    get showProgress() {
        return this.showDataView;
    }

    get showNextStep() {
        return this.showProgress && this.activeStep;
    }

    get showAllDone() {
        return this.showProgress && !this.activeStep;
    }

    get showProductionWarning() {
        return this.showDataView && this.isProductionOrg;
    }

    get showRecords() {
        return this.showDataView && this.hasAnyRecords;
    }

    /**
     * Which record tables show: the active step's table once its records exist, or every table on
     * Ready. The data model step shows none.
     */
    get recordsView() {
        const view = this.currentStep;
        const all = view === 'done';
        const stepDone = this.isActiveStepComplete;
        return {
            employees: this.hasEmployees && (all || (view === 'employee' && stepDone)),
            projects: this.hasProjects && (all || (view === 'projects' && stepDone)),
            projectEmployees: this.hasProjectAssignments && (all || (view === 'assignments' && stepDone)),
            timesheets: this.hasTimesheets && view === 'timesheets' && stepDone,
            lineItems: this.hasTimesheets && (all || (view === 'lineItems' && stepDone))
        };
    }

    get showDeleteSection() {
        return this.showRecords && !this.showDeleteConfirm;
    }
}
