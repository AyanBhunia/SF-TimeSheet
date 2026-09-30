import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference } from 'lightning/navigation';
import { CloseActionScreenEvent } from 'lightning/actions';
import { RefreshEvent } from 'lightning/refresh';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import getInitialData from '@salesforce/apex/ProjectEmployeeController.getInitialData';
import getEmployeesByGroup from '@salesforce/apex/ProjectEmployeeController.getEmployeesByGroup';
import getExistingCombinations from '@salesforce/apex/ProjectEmployeeController.getExistingCombinations';
import saveProjectEmployees from '@salesforce/apex/ProjectEmployeeController.saveProjectEmployees';

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

    resetState() {
        this.isPageOne = true;
        this.selectedProjects = this._recordId ? [this._recordId] : [];
        this.selectedGroup = '';
        this.selectedEmployees = [];
        this.hourlyRate = 0;
        this.dataTableRows = [];
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

    get isFormDisabled() {
        return this.selectedProjects.length === 0;
    }

    get isNextDisabled() {
        return this.selectedProjects.length === 0;
    }

    get emptyTableMessage() {
        if (this.selectedEmployees.length === 0) {
            return 'No employees were selected. Please click Previous to select employees.';
        }
        return 'All selected combinations already exist in the system. No new records are needed.';
    }

    get hasRecordsToSave() {
        return this.dataTableRows.length > 0;
    }

    handleProjectChange(event) {
        this.selectedProjects = event.detail.values;
        if (this.selectedProjects.length === 0) {
            this.selectedGroup = '';
            this.selectedEmployees = [];
            this.hourlyRate = 0;
        }
    }

    handleGroupChange(event) {
        this.selectedGroup = event.detail.value;
        // Any group change starts over: None clears the employees, a group selects only its members
        this.selectedEmployees = [];
        if (this.selectedGroup) {
            this.isLoading = true;
            getEmployeesByGroup({ groupId: this.selectedGroup })
                .then(employeeIds => {
                    this.selectedEmployees = employeeIds;
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
        this.isLoading = true;
        getExistingCombinations({ projectIds: this.selectedProjects, employeeIds: this.selectedEmployees })
            .then(existingKeys => {
                const existing = new Set(existingKeys);
                const rows = [];
                let keyCounter = 0;
                this.selectedProjects.forEach(projectId => {
                    this.selectedEmployees.forEach(employeeId => {
                        if (!existing.has(projectId + '_' + employeeId)) {
                            rows.push({ key: keyCounter++, projectId, employeeId, hourlyRate: this.hourlyRate });
                        }
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

    handlePrevious() {
        this.isPageOne = true;
    }

    // Row edits only update the row object; the inputs already show the new value
    handleRowEmployeeChange(event) {
        this.dataTableRows[event.target.dataset.index].employeeId = event.detail.value;
    }

    handleRowProjectChange(event) {
        this.dataTableRows[event.target.dataset.index].projectId = event.detail.value;
    }

    handleRowRateChange(event) {
        this.dataTableRows[event.target.dataset.index].hourlyRate = event.target.value;
    }

    handleDeleteRow(event) {
        const index = Number(event.target.dataset.index);
        this.dataTableRows = this.dataTableRows.filter((row, i) => i !== index);
    }

    handleAddRow() {
        this.dataTableRows = [
            ...this.dataTableRows,
            { key: Date.now(), projectId: '', employeeId: '', hourlyRate: 0 }
        ];
    }

    handleSave() {
        const recordsToInsert = this.dataTableRows
            .filter(row => row.projectId && row.employeeId)
            .map(row => ({
                projectId: row.projectId,
                employeeId: row.employeeId,
                hourlyRate: parseFloat(row.hourlyRate) || 0
            }));

        if (recordsToInsert.length === 0) {
            this.showToast('Warning', 'No valid records to save.', 'warning');
            return;
        }

        this.isLoading = true;
        saveProjectEmployees({ records: recordsToInsert })
            .then(created => {
                const skipped = recordsToInsert.length - created;
                if (created === 0) {
                    // Keep the modal open so the rows can be corrected
                    this.showToast('No records created', 'Every row is an employee already assigned to that project.', 'warning');
                    return;
                }
                const skippedNote = skipped > 0 ? ` ${skipped} skipped because they were already assigned.` : '';
                this.showToast('Success', `${created} Project Employee(s) created.${skippedNote}`, 'success');
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
