import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getInitialData from '@salesforce/apex/ProjectEmployeeController.getInitialData';
import getEmployeesByGroup from '@salesforce/apex/ProjectEmployeeController.getEmployeesByGroup';
import getExistingProjectEmployees from '@salesforce/apex/ProjectEmployeeController.getExistingProjectEmployees';
import saveProjectEmployees from '@salesforce/apex/ProjectEmployeeController.saveProjectEmployees';

// Space kept free under the component: the modal's own bottom margin (80px) plus a small buffer,
// because Lightning's modal body reports a few pixels more content than the card's measured height
const MODAL_BOTTOM_GAP = 96;
const TABLE_MIN_HEIGHT = 160;

const BADGE = {
    existing: { label: 'Existing', title: 'Already assigned', cls: 'slds-badge slds-theme_shade' },
    willUpdate: { label: 'Will update', title: 'The hourly rate of this assignment will be updated', cls: 'slds-badge slds-theme_warning' },
    duplicate: { label: 'Duplicate', title: 'This employee and project are already in another row', cls: 'slds-badge slds-theme_error' },
    assigned: { label: 'Already assigned', title: 'This employee is already assigned to this project', cls: 'slds-badge slds-theme_error' },
    newRow: { label: 'New', title: 'A new assignment will be created', cls: 'slds-badge slds-theme_success' }
};

// Hosted two ways: as a Project quick action (recordId set, closes the action screen)
// or inside the ProjectEmployeeCreatorWrapper Aura modal for the list button (fires "close").
export default class ProjectEmployeeCreator extends LightningElement {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        // Pre-select the Project the action was launched from
        if (value && !this.selectedProjects.includes(value)) {
            this.selectedProjects = [...this.selectedProjects, value];
        }
    }

    // The URL addressable Aura page is cached between visits, so reset on every navigation
    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (currentPageReference) {
            this.resetState();
            this.fetchInitialData();
        }
    }

    isPageOne = true;
    isLoading = true;

    projectOptions = [];
    groupOptions = [];
    employeeOptions = [];

    selectedProjects = [];
    selectedGroup = '';
    selectedEmployees = [];
    hourlyRate = 0;

    dataTableRows = [];
    rowKeyCounter = 0;
    groupRequestId = 0;
    revalidateRate = false;

    resetState() {
        this.isPageOne = true;
        this.selectedProjects = this._recordId ? [this._recordId] : [];
        this.selectedGroup = '';
        this.selectedEmployees = [];
        this.hourlyRate = 0;
        this.dataTableRows = [];
        this.revalidateRate = true;
    }

    connectedCallback() {
        this._resizeHandler = () => this.fitTableToViewport();
        window.addEventListener('resize', this._resizeHandler);
    }

    disconnectedCallback() {
        window.removeEventListener('resize', this._resizeHandler);
    }

    renderedCallback() {
        this.fitTableToViewport();
        // A reset rate keeps the error of the value it replaced until it is validated again
        if (this.revalidateRate) {
            const rateInput = this.template.querySelector('lightning-input[data-id="defaultRate"]');
            if (rateInput) {
                this.revalidateRate = false;
                rateInput.reportValidity();
            }
        }
    }

    // Only the table scrolls: it takes the height left between its top and the bottom of the
    // screen, after the buttons, messages and card padding below it, so the modal never needs to scroll
    fitTableToViewport() {
        const scroller = this.template.querySelector('.table-scroll');
        const card = this.template.querySelector('lightning-card');
        if (!scroller || !card) {
            return;
        }
        const tableRect = scroller.getBoundingClientRect();
        const below = card.getBoundingClientRect().bottom - tableRect.bottom;
        const available = window.innerHeight - tableRect.top - below - MODAL_BOTTOM_GAP;
        const maxHeight = Math.max(TABLE_MIN_HEIGHT, Math.floor(available)) + 'px';
        if (scroller.style.maxHeight !== maxHeight) {
            scroller.style.maxHeight = maxHeight;
        }
    }

    fetchInitialData() {
        this.isLoading = true;
        getInitialData()
            .then(result => {
                this.projectOptions = result.projects.map(p => ({ label: p.Name, value: p.Id }));
                this.groupOptions = [{ label: 'None', value: '' }].concat(
                    result.groups.map(g => ({ label: g.Name, value: g.Id }))
                );
                this.employeeOptions = result.employees.map(e => ({ label: e.Name, value: e.Id }));
            })
            .catch(() => {
                this.showToast('Error', 'Failed to load initial data', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    // Group, employees and rate stay disabled until a project is picked
    get isFormDisabled() {
        return this.selectedProjects.length === 0;
    }

    get isNextDisabled() {
        return this.selectedProjects.length === 0 || this.selectedEmployees.length === 0 || !isValidRate(this.hourlyRate);
    }

    get emptyTableMessage() {
        return 'No rows. Click Add Row, or click Previous to select projects and employees.';
    }

    get hasRows() {
        return this.dataTableRows.length > 0;
    }

    // Rows with their status: existing rows can only change their rate; a new row is invalid
    // when its pair is already in an earlier row (existing rows take precedence) or already assigned
    get displayRows() {
        const seen = new Set(this.dataTableRows.filter(r => r.isExisting).map(pairKey));
        return this.dataTableRows.map(row => {
            let badge = null;
            let isDuplicate = false;
            if (row.isExisting) {
                badge = row.willUpdate ? BADGE.willUpdate : BADGE.existing;
            } else if (row.projectId && row.employeeId) {
                const key = pairKey(row);
                isDuplicate = seen.has(key);
                seen.add(key);
                if (isDuplicate) {
                    badge = BADGE.duplicate;
                } else if (row.alreadyAssigned) {
                    badge = BADGE.assigned;
                } else {
                    badge = BADGE.newRow;
                }
            }
            const hasInvalidRate = !isValidRate(row.hourlyRate);
            const hasError = hasInvalidRate || isDuplicate || (!row.isExisting && row.alreadyAssigned);
            return {
                ...row,
                isDuplicate,
                hasInvalidRate,
                hasBadge: badge !== null,
                badgeLabel: badge ? badge.label : '',
                badgeTitle: badge ? badge.title : '',
                badgeClass: badge ? badge.cls : '',
                rowClass: hasError ? 'slds-hint-parent row-error' : 'slds-hint-parent'
            };
        });
    }

    // Problems that block saving, shown above the buttons
    get validationMessages() {
        const rows = this.displayRows;
        const messages = [];
        if (rows.some(r => !r.isExisting && (!r.projectId || !r.employeeId))) {
            messages.push('Select an employee and a project in every row, or delete the incomplete row.');
        }
        if (rows.some(r => r.hasInvalidRate)) {
            messages.push('Enter an hourly rate of 0 or more in every row.');
        }
        if (rows.some(r => r.isDuplicate)) {
            messages.push('The same employee and project appear in more than one row. Delete the duplicate rows.');
        }
        if (rows.some(r => !r.isExisting && !r.isDuplicate && r.alreadyAssigned)) {
            messages.push('Some new rows are already assigned. Delete them, or go Previous and select that project and employee to edit the existing rate.');
        }
        return messages.map((text, i) => ({ key: 'msg-' + i, text }));
    }

    get hasValidationMessages() {
        return this.validationMessages.length > 0;
    }

    // Rows that would change something: new assignments, or existing ones whose rate was edited
    get rowsToSave() {
        return this.dataTableRows.filter(row => !row.isExisting || row.willUpdate);
    }

    get isSaveDisabled() {
        return this.rowsToSave.length === 0 || this.hasValidationMessages;
    }

    handleProjectChange(event) {
        this.selectedProjects = event.detail.values;
        if (this.selectedProjects.length === 0) {
            this.selectedGroup = '';
            this.selectedEmployees = [];
            this.hourlyRate = 0;
            this.revalidateRate = true;
        }
    }

    handleGroupChange(event) {
        this.selectedGroup = event.detail.value;
        // Any group change starts over: None clears the employees, a group selects only its members
        this.selectedEmployees = [];
        const requestId = ++this.groupRequestId;
        if (this.selectedGroup) {
            this.isLoading = true;
            getEmployeesByGroup({ groupId: this.selectedGroup })
                .then(employeeIds => {
                    // Ignore the answer for a group that is no longer selected
                    if (requestId === this.groupRequestId) {
                        this.selectedEmployees = employeeIds;
                    }
                })
                .catch(() => {
                    this.showToast('Error', 'Failed to fetch group employees', 'error');
                })
                .finally(() => {
                    this.isLoading = false;
                });
        }
    }

    handleEmployeeChange(event) {
        this.selectedEmployees = event.detail.values;
    }

    handleRateChange(event) {
        this.hourlyRate = event.target.value;
    }

    handleCancel() {
        this.close(false);
    }

    close(saved) {
        if (this._recordId) {
            if (saved) {
                this.dispatchEvent(new RefreshEvent());
            }
            this.dispatchEvent(new CloseActionScreenEvent());
            return;
        }
        this.dispatchEvent(new CustomEvent('close', { detail: { saved } }));
    }

    handleNext() {
        const rateInput = this.template.querySelector('lightning-input[data-id="defaultRate"]');
        if (rateInput && !rateInput.reportValidity()) {
            return;
        }
        this.isLoading = true;
        getExistingProjectEmployees({ projectIds: this.selectedProjects, employeeIds: this.selectedEmployees })
            .then(existingRecords => {
                const existingByPair = new Map();
                (existingRecords || []).forEach(rec => {
                    existingByPair.set(rec.projectId + '_' + rec.employeeId, rec);
                });

                // Every selected pair gets a row: existing assignments are locked except for their rate
                const rows = [];
                this.selectedProjects.forEach(projectId => {
                    this.selectedEmployees.forEach(employeeId => {
                        const existing = existingByPair.get(projectId + '_' + employeeId);
                        // An existing assignment without a rate is shown, and compared, as 0
                        rows.push(existing
                            ? this.newRow(projectId, employeeId, existing.hourlyRate == null ? 0 : existing.hourlyRate, true)
                            : this.newRow(projectId, employeeId, this.hourlyRate, false));
                    });
                });
                this.dataTableRows = rows;
                this.isPageOne = false;
            })
            .catch(() => {
                this.showToast('Error', 'Failed to prepare confirmation data', 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    newRow(projectId, employeeId, hourlyRate, isExisting) {
        return this.withRateStatus({
            key: 'row-' + this.rowKeyCounter++,
            projectId,
            employeeId,
            hourlyRate,
            // Bound to the rate input and never changed, so re-renders don't rewrite the field while typing
            initialRate: hourlyRate,
            originalRate: isExisting ? toRate(hourlyRate) : null,
            isExisting,
            alreadyAssigned: false
        });
    }

    withRateStatus(row) {
        return { ...row, willUpdate: row.isExisting && toRate(row.hourlyRate) !== row.originalRate };
    }

    handlePrevious() {
        this.isPageOne = true;
    }

    updateRow(key, changes) {
        this.dataTableRows = this.dataTableRows.map(row => (row.key === key ? this.withRateStatus({ ...row, ...changes }) : row));
    }

    handleRowEmployeeChange(event) {
        this.changeRowPair(event.target.dataset.key, { employeeId: event.detail.value });
    }

    handleRowProjectChange(event) {
        this.changeRowPair(event.target.dataset.key, { projectId: event.detail.value });
    }

    // A new row's pair may already exist outside this table, so check it once both are picked
    changeRowPair(key, changes) {
        this.updateRow(key, { ...changes, alreadyAssigned: false });
        const row = this.dataTableRows.find(r => r.key === key);
        if (!row || row.isExisting || !row.projectId || !row.employeeId) {
            return;
        }
        const { projectId, employeeId } = row;
        getExistingProjectEmployees({ projectIds: [projectId], employeeIds: [employeeId] })
            .then(existing => {
                const current = this.dataTableRows.find(r => r.key === key);
                if (current && current.projectId === projectId && current.employeeId === employeeId) {
                    this.updateRow(key, { alreadyAssigned: (existing || []).length > 0 });
                }
            })
            .catch(() => {
                // Save still skips pairs that already exist
            });
    }

    handleRowRateChange(event) {
        this.updateRow(event.target.dataset.key, { hourlyRate: event.target.value });
    }

    handleDeleteRow(event) {
        const key = event.currentTarget.dataset.key;
        this.dataTableRows = this.dataTableRows.filter(row => row.key !== key);
    }

    handleAddRow() {
        this.dataTableRows = [...this.dataTableRows, this.newRow('', '', this.hourlyRate, false)];
    }

    handleSave() {
        const rateInputs = [...this.template.querySelectorAll('lightning-input[data-key]')];
        const ratesValid = rateInputs.reduce((valid, input) => input.reportValidity() && valid, true);
        if (!ratesValid) {
            this.showToast('Warning', 'Please correct the invalid hourly rates.', 'warning');
            return;
        }
        if (this.hasValidationMessages) {
            this.showToast('Warning', this.validationMessages[0].text, 'warning');
            return;
        }

        const recordsToSave = this.rowsToSave.map(row => ({
            projectId: row.projectId,
            employeeId: row.employeeId,
            hourlyRate: toRate(row.hourlyRate) || 0,
            isExisting: row.isExisting
        }));

        if (recordsToSave.length === 0) {
            this.showToast('Warning', 'There are no new assignments or rate changes to save.', 'warning');
            return;
        }

        this.isLoading = true;
        saveProjectEmployees({ records: recordsToSave })
            .then(result => {
                const parts = [];
                if (result.created > 0) {
                    parts.push(`${result.created} Project Employee(s) created`);
                }
                if (result.updated > 0) {
                    parts.push(`${result.updated} hourly rate(s) updated`);
                }
                if (parts.length === 0) {
                    // Keep the modal open so the rows can be corrected
                    this.showToast('Nothing saved', 'Every new row is an employee already assigned to that project.', 'warning');
                    return;
                }
                const skipped = recordsToSave.length - result.created - result.updated;
                const skippedNote = skipped > 0 ? ` ${skipped} skipped because they were already assigned.` : '';
                this.showToast('Success', `${parts.join(', ')}.${skippedNote}`, 'success');
                this.close(true);
            })
            .catch(error => {
                const msg = error && error.body && error.body.message ? error.body.message : 'Failed to save records';
                this.showToast('Error', msg, 'error');
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

// Blank and negative rates are invalid; 0 is allowed
function isValidRate(value) {
    const rate = toRate(value);
    return rate !== null && rate >= 0;
}

function pairKey(row) {
    return row.projectId + '_' + row.employeeId;
}

// Normalizes an input or Apex value to a number, or null when blank
function toRate(value) {
    if (value === null || value === undefined || value === '') {
        return null;
    }
    const num = Number(value);
    return Number.isNaN(num) ? null : num;
}
