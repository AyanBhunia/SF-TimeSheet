import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getWeeklyTimesheetItems from '@salesforce/apex/WeeklyTimesheetController.getWeeklyTimesheetItems';
import getProjects from '@salesforce/apex/WeeklyTimesheetController.getProjects';
import getProjectActivities from '@salesforce/apex/WeeklyTimesheetController.getProjectActivities';
import getTimesheet from '@salesforce/apex/WeeklyTimesheetController.getTimesheet';
import getEmployeeTimesheetItems from '@salesforce/apex/WeeklyTimesheetController.getEmployeeTimesheetItems';
import upsertLineItems from '@salesforce/apex/WeeklyTimesheetController.upsertLineItems';
import deleteTimesheetLineItems from '@salesforce/apex/WeeklyTimesheetController.deleteTimesheetLineItems';
import { getPicklistValues, getObjectInfo } from 'lightning/uiObjectInfoApi';
import TIMESHEET_LINE_ITEM_OBJECT from '@salesforce/schema/Timesheet_Line_Item__c';
import ACTIVITY_CATEGORY_FIELD from '@salesforce/schema/Timesheet_Line_Item__c.Activity__c';
import ABSENCE_CATEGORY_FIELD from '@salesforce/schema/Timesheet_Line_Item__c.Absence_Category__c';

import TIMESHEET_OBJECT from '@salesforce/schema/Timesheet__c';
import EMPLOYEE_OBJECT from '@salesforce/schema/Employee__c';
import PROJECT_EMPLOYEE_OBJECT from '@salesforce/schema/Project_Employee__c';
import TIMESHEET_LINE_OBJECT from '@salesforce/schema/Timesheet_Line_Item__c';

export default class TestLineItem extends LightningElement {
    timesheetInfo;
    employeeInfo;
    projectEmployeeInfo;
    timesheetLineInfo;

    @wire(getObjectInfo, { objectApiName: TIMESHEET_OBJECT })
    wiredTimesheet({ error, data }) {
        if (data) {
            this.timesheetInfo = data;
        } else if (error) {
            console.error('Error loading dbt__Timesheet__c schema', error);
        }
    }

    @wire(getObjectInfo, { objectApiName: EMPLOYEE_OBJECT })
    wiredEmployee({ error, data }) {
        if (data) {
            this.employeeInfo = data;
        } else if (error) {
            console.error('Error loading dbt__Employee__c schema', error);
        }
    }

    @wire(getObjectInfo, { objectApiName: PROJECT_EMPLOYEE_OBJECT })
    wiredProjectEmployee({ error, data }) {
        if (data) {
            this.projectEmployeeInfo = data;
        } else if (error) {
            console.error('Error loading dbt__Project_Employee__c schema', error);
        }
    }

    @wire(getObjectInfo, { objectApiName: TIMESHEET_LINE_OBJECT })
    wiredTimesheetLine({ error, data }) {
        if (data) {
            this.timesheetLineInfo = data;
        } else if (error) {
            console.error('Error loading dbt__Timesheet_Line_Item__c schema', error);
        }
    }

    @api recordId;
    @track projectsList = [];
    @track projectOptions = [];
    @track activityOptions = [];
    ProjectActivityMap;
    @track absenceList = [];
    @track absenceOptions = [];
    projectIds = [];

    @track prevTimesheets = [];
    prevTimesheetValue;

    @track projectsTotals = [0, 0, 0, 0, 0, 0, 0];
    @track absenceTotals = [0, 0, 0, 0, 0, 0, 0];
    @track grandTotals = [0, 0, 0, 0, 0, 0, 0];
    @track billableAmounts = [0, 0, 0, 0, 0, 0, 0];

    TimesheetStartDate = '';
    TimeSheetEndDate = '';
    TimeSheetName = '';
    EmployeeID = '';

    previousRecordIDs;
    wiredTimesheetResult;
    error;

    dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    dayList = [];

    @wire(getObjectInfo, { objectApiName: TIMESHEET_LINE_ITEM_OBJECT })
    objectInfo;

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: ACTIVITY_CATEGORY_FIELD
    })
    wiredActivityPicklistValues({ error, data }) {
        if (data) {
            this.activityOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            console.error('Error fetching Activity picklist values:', error);
        }
    }

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: ABSENCE_CATEGORY_FIELD
    })
    wiredAbsencePicklistValues({ error, data }) {
        if (data) {
            this.absenceOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            console.error('Error fetching Absence picklist values:', error);
        }
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

    formatDateYMD(date) {
        const y = date.getFullYear();
        const m = String(date.getMonth() + 1).padStart(2, '0');
        const d = String(date.getDate()).padStart(2, '0');
        return `${y}-${m}-${d}`;
    }

    localDateFromServer(dateStr) {
        if (!dateStr) return null;
        const dateOnly = String(dateStr).split('T')[0];
        const parts = dateOnly.split('-');
        if (parts.length !== 3) {
            const fallback = new Date(dateStr);
            return new Date(fallback.getFullYear(), fallback.getMonth(), fallback.getDate());
        }
        const y = parseInt(parts[0], 10);
        const m = parseInt(parts[1], 10) - 1;
        const d = parseInt(parts[2], 10);
        return new Date(y, m, d);
    }

    connectedCallback() {
        const fetchPromise = new Promise((resolve, reject) => {
            this.fetchTimesheetData(this.recordId, result => {
                this.wiredTimesheetResult = result;
                resolve(result);
            });
        });

        Promise.all([
            fetchPromise,
            this.loadTimesheet()
        ])
            .then(([timesheetData, _loadResult]) => {
                this.processTimesheetData(timesheetData, true);
            })
            .catch(error => {
                console.error(error);
            });
    }

    fetchTimesheetData(Id, callback) {
        getWeeklyTimesheetItems({ timesheetId: Id })
            .then(result => {
                callback(result);
            })
            .catch(error => {
                console.error(error);
            });
    }

    loadTimesheet() {
        return getTimesheet({ timesheetId: this.recordId })
            .then(result => {
                this.EmployeeID = result.dbt__Employee__c;
                this.TimesheetStartDate = result.dbt__Start_Date__c;
                this.TimeSheetEndDate = result.dbt__End_Date__c;
                this.TimeSheetName = result.name;
            })
            .then(() => {
                this.createDays();
                return Promise.all([
                    this.loadProjects(),
                    this.loadPrevTimesheets()
                ]);
            })
            .catch(error => {
                console.error(error);
            });
    }

    createDays() {
        const startDateObj = (this.TimesheetStartDate instanceof Date)
            ? new Date(this.TimesheetStartDate.getFullYear(), this.TimesheetStartDate.getMonth(), this.TimesheetStartDate.getDate())
            : this.localDateFromServer(this.TimesheetStartDate);

        if (!startDateObj) {
            console.warn('createDays: invalid TimesheetStartDate', this.TimesheetStartDate);
            this.dayList = [];
            return;
        }

        this.dayList = Array.from({ length: 7 }, (_, i) => {
            const temp = new Date(startDateObj.getFullYear(), startDateObj.getMonth(), startDateObj.getDate() + i);
            return this.formatDateYMD(temp);
        });
    }

    loadPrevTimesheets() {
        getEmployeeTimesheetItems({ empId: this.EmployeeID, recordId: this.recordId })
            .then(result => {
                this.prevTimesheets = result.map(item => ({
                    label: item.Name,
                    value: item.Id
                }));
            })
            .catch(error => {
                console.error(error);
            });
    }

    loadProjects(existingProjectIds = '') {
        return getProjects({ empId: this.EmployeeID, existingProjectIds: existingProjectIds })
            .then(result => {
                this.projectOptions = result.map(proj => ({
                    label: proj.dbt__Project__r.Name,
                    value: proj.dbt__Project__c,
                    billable: proj.dbt__Project__r?.dbt__Billable__c,
                    hourly_rate: proj.dbt__Hourly_Rate__c || 0
                }));
                this.projectIds = result.map(proj => proj.dbt__Project__c);
            })
            .then(() => {
                getProjectActivities({ projectIds: this.projectIds })
                    .then(result => {
                        console.log('Project Activities:', JSON.stringify(result));
                        this.ProjectActivityMap = new Map();
                        result.forEach(item => {
                            const pid = item.dbt__Project__c;
                            const arr = this.ProjectActivityMap.get(pid) || [];
                            arr.push({ label: item.Name, value: item.Name });
                            this.ProjectActivityMap.set(pid, arr);
                        });

                        if (Array.isArray(this.projectsList) && this.projectsList.length) {
                            this.projectsList = this.projectsList.map(row => ({
                                ...row,
                                activityOptions: this.getActivityOptionsForProject(row.projectName)
                            }));
                        }
                        console.log('ProjectActivityMap ready');
                    });
            })
            .catch(error => {
                console.error(error);
            });
    }

    getActivityOptionsForProject(projectId) {
        const common = Array.isArray(this.activityOptions) ? this.activityOptions : [];
        const specific = (this.ProjectActivityMap && projectId && this.ProjectActivityMap.get(projectId)) || [];
        if (!specific.length) return common;
        const seen = new Set();
        const merged = [];
        [...specific, ...common].forEach(opt => {
            const key = opt.value;
            if (!seen.has(key)) {
                seen.add(key);
                merged.push(opt);
            }
        });
        return merged;
    }

    processTimesheetData(data, includeId) {
        this.projectsList = [];
        this.absenceList = [];

        if (includeId) {
            this.previousRecordIDs = new Set();
        }

        let attendanceData = {};
        let absenceData = {};

        data.forEach(item => {
            const date = this.localDateFromServer(item.dbt__Date__c);
            const dayIndex = date.getDay() === 0 ? 6 : date.getDay() - 1;

            if (includeId) {
                this.previousRecordIDs.add(item.Id);
            }

            const updateDate = record => {
                record.dates[dayIndex].dur = item.dbt__Duration__c || 0;
                record.dates[dayIndex].desc = item.dbt__Description__c || '';
                record.dates[dayIndex].id = includeId ? item.Id : null;
                record.dates[dayIndex].isdisable = false;
            };

            if (item.dbt__Type__c === "Attendance") {
                const key = `${item.dbt__Project__c}_${item.dbt__Activity__c}`;
                if (!attendanceData[key]) {
                    const selectedProject = this.projectOptions.find(option => option.value === item.dbt__Project__c);
                    attendanceData[key] = {
                        ...this.getBlankData("Attendance"),
                        projectName: item.dbt__Project__c,
                        activityName: item.dbt__Activity__c,
                        billable: item.dbt__Project__r?.dbt__Billable__c,
                        hourlyRate: (selectedProject && selectedProject.hourly_rate) ? selectedProject.hourly_rate : 0
                    };
                }
                updateDate(attendanceData[key]);
            } else {
                const key = item.dbt__Absence_Category__c;
                if (!absenceData[key]) {
                    absenceData[key] = {
                        ...this.getBlankData("Absence"),
                        absenceName: item.dbt__Absence_Category__c
                    };
                }
                updateDate(absenceData[key]);
            }
        });

        this.projectsList = Object.values(attendanceData).map(row => ({
            ...row,
            activityOptions: this.getActivityOptionsForProject(row.projectName)
        }));
        this.absenceList = Object.values(absenceData);

        if (this.projectsList.length === 0) {
            this.addNewProject();
        }

        // Reload projects including inactive ones used in existing records
        if (includeId) {
            const existingProjectIds = this.projectsList
                .map(row => row.projectName)
                .filter(id => id !== '')
                .join(',');
            this.loadProjects(existingProjectIds);
        }

        this.calculateTotals();
    }

    getBlankData(type) {
        const dates = this.dayNames.map((name, index) => {
            return {
                id: null,
                isdisable: true,
                date: this.dayList[index],
                name,
                dur: 0,
                desc: ""
            };
        });

        if (type === "Attendance") {
            return {
                type: "Attendance",
                projectName: "",
                activityName: "",
                billable: "",
                hourlyRate: 0,
                activityOptions: Array.isArray(this.activityOptions) ? this.activityOptions : [],
                dates
            };
        } else {
            return {
                type: "Absence",
                absenceName: "",
                dates
            };
        }
    }

    handleProjectChange(event) {
        const rowIndex = event.target.dataset.rowIndex;
        const fieldName = event.target.name;
        const newValue = event.target.value;

        const currentRow = this.projectsList[rowIndex];
        const tempRow = { ...this.projectsList[rowIndex] };

        if (fieldName === 'projectName') {
            tempRow.projectName = newValue;
        } else if (fieldName === 'activityName') {
            tempRow.activityName = newValue;
        }

        if (tempRow.projectName && tempRow.activityName) {
            const wouldCreateDuplicate = this.projectsList.some((row, index) =>
                index !== parseInt(rowIndex) &&
                row.projectName === tempRow.projectName &&
                row.activityName === tempRow.activityName
            );

            if (wouldCreateDuplicate) {
                this.showToast('Error', 'A row with the same Project and Activity already exists.', 'error');
                event.target.value = currentRow[fieldName];
                return;
            }
        }

        currentRow[fieldName] = newValue;

        if (fieldName === 'projectName') {
            const selectedProject = this.projectOptions.find(option => option.value === newValue);
            if (selectedProject) {
                currentRow.billable = selectedProject.billable;
                currentRow.hourlyRate = selectedProject.hourly_rate;
            }
            currentRow.activityOptions = this.getActivityOptionsForProject(newValue);
            const stillValid = currentRow.activityOptions?.some(opt => opt.value === currentRow.activityName);
            if (!stillValid) {
                currentRow.activityName = '';
            }
        }

        this.projectsList = [...this.projectsList];
        this.calculateTotals();
    }

    handleKeyDown(event) {
        // Feature temporarily disabled.
    }

    handleDurationChange(event) {
        const rowIndex = event.target.dataset.rowIndex;
        const dayIndex = event.target.dataset.dayIndex;
        const dataFor = event.target.getAttribute('data-for');

        let rawStr = String(event.target.value);
        let wasTruncated = false;

        if (rawStr.includes('.')) {
            let parts = rawStr.split('.');
            if (parts[1].length > 2) {
                parts[1] = parts[1].substring(0, 2);
                rawStr = parts.join('.');
                wasTruncated = true;
            }
        }

        let value = parseFloat(rawStr) || 0;

        let list;
        let CalculateList;
        if (dataFor === 'project') {
            list = this.projectsList;
            CalculateList = this.projectsTotals;
        } else if (dataFor === 'absence') {
            list = this.absenceList;
            CalculateList = this.absenceTotals;
        }

        if (value < 0 || value > 24) {
            this.showToast('Error', "Duration must be a number between 0 and 24", 'error');
            event.target.value = list[rowIndex].dates[dayIndex].dur || 0;
            return;
        }

        let prevDur = parseFloat(list[rowIndex].dates[dayIndex].dur) || 0;

        CalculateList[dayIndex] = parseFloat((CalculateList[dayIndex] + (value - prevDur)).toFixed(2));
        this.grandTotals[dayIndex] = parseFloat((this.grandTotals[dayIndex] + (value - prevDur)).toFixed(2));

        if (dataFor === 'project') {
            this.billableAmounts[dayIndex] = parseFloat((this.billableAmounts[dayIndex] + (value - prevDur) * parseFloat(list[rowIndex].hourlyRate)).toFixed(2)) || 0;
        }

        list[rowIndex].dates[dayIndex].dur = value;
        list[rowIndex].dates[dayIndex].isdisable = (value === 0);

        if (wasTruncated) {
            try {
                event.target.value = rawStr;
            } catch (e) {}
        }
    }

    handleDescriptionChange(event) {
        const rowIndex = parseInt(event.target.dataset.rowIndex);
        const dayIndex = parseInt(event.target.dataset.dayIndex);
        const newValue = event.target.value;
        const dataFor = event.target.getAttribute('data-for');
        let list;
        if (dataFor === 'project') {
            list = this.projectsList;
        } else if (dataFor === 'absence') {
            list = this.absenceList;
        }
        list[rowIndex].dates[dayIndex].desc = newValue;
    }

    handleDeleteRow(event) {
        const rowIndex = parseInt(event.target.dataset.rowIndex);
        const type = event.target.dataset.type;

        try {
            if (type === 'project' && this.projectsList.length > 0) {
                this.projectsList = this.projectsList.filter((row, index) => index !== rowIndex);
                if (this.projectsList.length === 0) {
                    this.addNewProject();
                }
            } else if (type === 'absence' && this.absenceList.length > 0) {
                this.absenceList = this.absenceList.filter((row, index) => index !== rowIndex);
            }
            this.showToast('warning', 'Row Removed. Please Click Save', 'warning');
        } catch (error) {
            this.showToast('Error', 'Failed to delete row', 'error');
            console.error('Error deleting row:', error);
        }

        this.calculateTotals();
    }

    handleAbsenceChange(event) {
        const rowIndex = event.target.dataset.rowIndex;
        const newValue = event.target.value;
        const currentRow = this.absenceList[rowIndex];

        const isDuplicate = this.absenceList.some((row, index) =>
            index !== parseInt(rowIndex) && row.absenceName === newValue
        );

        if (isDuplicate) {
            this.showToast('Error', 'This absence type is already selected in another row', 'error');
            event.target.value = currentRow.absenceName;
            return;
        }

        currentRow.absenceName = newValue;
    }

    addNewProject() {
        const newProject = this.getBlankData("Attendance");
        this.projectsList.push(newProject);
    }

    addNewAbsence() {
        const newAbsence = this.getBlankData("Absence");
        this.absenceList.push(newAbsence);
    }

    handleSave() {
        let upsertList = [];
        let deleteList;
        let currentRecordIDs = new Set();

        try {
            let hasError = this.projectsList.some(project =>
                project.dates.some(day => {
                    if (day.dur > 0) {
                        if (project.projectName === '' || project.activityName === '') {
                            this.showToast('Error', "Project name or Activity name cannot be blank", 'error');
                            return true;
                        }
                        if (day.id) currentRecordIDs.add(day.id);
                        upsertList.push({
                            sobjectType: 'dbt__Timesheet_Line_Item__c',
                            Id: day.id,
                            dbt__Timesheet__c: this.recordId,
                            dbt__Type__c: "Attendance",
                            dbt__Project__c: project.projectName,
                            dbt__Activity__c: project.activityName,
                            dbt__Duration__c: day.dur,
                            dbt__Description__c: day.desc,
                            dbt__Date__c: day.date,
                            dbt__Billable__c: this.projectOptions.find(option => option.value === project.projectName)?.billable || "No",
                            dbt__Hours_Limit_Exceeded__c: false
                        });
                    }
                })
            );

            if (hasError) return;

            hasError = this.absenceList.some(absence =>
                absence.dates.some(day => {
                    if (day.dur > 0) {
                        if (absence.absenceName === '') {
                            this.showToast('Error', "Absence name cannot be blank", 'error');
                            return true;
                        }
                        if (day.id) currentRecordIDs.add(day.id);
                        upsertList.push({
                            sobjectType: 'dbt__Timesheet_Line_Item__c',
                            Id: day.id,
                            dbt__Timesheet__c: this.recordId,
                            dbt__Type__c: "Absence",
                            dbt__Absence_Category__c: absence.absenceName,
                            dbt__Duration__c: day.dur,
                            dbt__Description__c: day.desc,
                            dbt__Date__c: day.date,
                            dbt__Billable__c: this.projectOptions.find(option => option.value === absence.absenceName)?.billable || "No",
                            dbt__Hours_Limit_Exceeded__c: false
                        });
                    }
                })
            );

            if (hasError) return;

            deleteList = [...this.previousRecordIDs].filter(id => !currentRecordIDs.has(id));

        } catch (error) {
            this.showToast('Error', error, 'error');
        }

        (
            (deleteList.length > 0
                ? deleteTimesheetLineItems({ lineItemIds: deleteList.map(id => ({ Id: id })) })
                : Promise.resolve()
            )
                .then(res => {
                    if (res && res !== 'Success') throw new Error(res);
                    return upsertList.length > 0 ? upsertLineItems({ lineItems: upsertList }) : Promise.resolve();
                })
                .then(res => {
                    if (res && res !== 'Success') throw new Error(res);
                    this.showToast('Success', 'Records saved', 'success');
                })
                .catch(e => {
                    this.showToast('Error', e.message, 'error');
                })
                .finally(() => {
                    this.fetchTimesheetData(this.recordId, result => {
                        this.wiredTimesheetResult = result;
                        this.processTimesheetData(this.wiredTimesheetResult, true);
                    });
                })
        );
    }

    calculateTotals() {
        this.projectsTotals = [0, 0, 0, 0, 0, 0, 0];
        this.absenceTotals = [0, 0, 0, 0, 0, 0, 0];
        this.grandTotals = [0, 0, 0, 0, 0, 0, 0];
        this.billableAmounts = [0, 0, 0, 0, 0, 0, 0];

        try {
            this.projectsList.forEach(project => {
                project.dates.forEach((day, index) => {
                    const duration = parseFloat(day.dur) || 0;
                    this.projectsTotals[index] = parseFloat((this.projectsTotals[index] + duration).toFixed(2));
                    if (project.billable === "Yes") {
                        this.billableAmounts[index] = parseFloat((this.billableAmounts[index] + duration * parseFloat(project.hourlyRate || 0)).toFixed(2));
                    }
                });
            });
        } catch (error) {
            console.log(error);
        }

        this.absenceList.forEach(absence => {
            absence.dates.forEach((day, index) => {
                const duration = parseFloat(day.dur) || 0;
                this.absenceTotals[index] = parseFloat((this.absenceTotals[index] + duration).toFixed(2));
            });
        });

        this.projectsTotals.forEach((total, index) => {
            this.grandTotals[index] = parseFloat((total + this.absenceTotals[index]).toFixed(2));
        });
    }

    prevTimesheet(event) {
        this.prevTimesheetValue = event.detail.value;
    }

    handleCopy() {
        if (this.prevTimesheetValue != undefined) {
            this.fetchTimesheetData(this.prevTimesheetValue, result => {
                this.processTimesheetData(result, false);
                this.showToast('Success', 'Timesheet copied successfully', 'success');
            });
        }
    }

    handleCancel() {
        this.processTimesheetData(this.wiredTimesheetResult, true);
        this.template.querySelectorAll('lightning-combobox[data-id="prevTimesheet"]').forEach(cb => {
            cb.value = undefined;
        });
    }
}