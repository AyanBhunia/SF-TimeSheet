import { LightningElement, api, track, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';

// Must match SYNC_CHANNEL in timesheetTimer.
const TIMER_SYNC_CHANNEL = 'timesheet-timer-sync';
import { refreshApex } from '@salesforce/apex';
import getWeeklyTimesheetItems from '@salesforce/apex/WeeklyTimesheetController.getWeeklyTimesheetItems';
import getProjects from '@salesforce/apex/WeeklyTimesheetController.getProjects';
import getProjectActivities from '@salesforce/apex/WeeklyTimesheetController.getProjectActivities';
import getTimesheet from '@salesforce/apex/WeeklyTimesheetController.getTimesheet';
import getEmployeeTimesheetItems from '@salesforce/apex/WeeklyTimesheetController.getEmployeeTimesheetItems';
import saveWeek from '@salesforce/apex/WeeklyTimesheetController.saveWeek';
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
    //   console.info('dbt__Timesheet__c schema (UI API):', data);
    } else if (error) {
      console.error('Error loading dbt__Timesheet__c schema', error);
    }
  }

  @wire(getObjectInfo, { objectApiName: EMPLOYEE_OBJECT })
  wiredEmployee({ error, data }) {
    if (data) {
      this.employeeInfo = data;
    //   console.info('dbt__Employee__c schema (UI API):', data);
    } else if (error) {
      console.error('Error loading dbt__Employee__c schema', error);
    }
  }

  @wire(getObjectInfo, { objectApiName: PROJECT_EMPLOYEE_OBJECT })
  wiredProjectEmployee({ error, data }) {
    if (data) {
      this.projectEmployeeInfo = data;
    //   console.info('dbt__Project_Employee__c schema (UI API):', data);
    } else if (error) {
      console.error('Error loading dbt__Project_Employee__c schema', error);
    }
  }

  @wire(getObjectInfo, { objectApiName: TIMESHEET_LINE_OBJECT })
  wiredTimesheetLine({ error, data }) {
    if (data) {
      this.timesheetLineInfo = data;
    //   console.info('dbt__Timesheet_Line_Item__c schema (UI API):', data);
    } else if (error) {
      console.error('Error loading dbt__Timesheet_Line_Item__c schema', error);
    }
  }

    @api recordId;
    @track projectsList = [];
    @track projectOptions = [];
    // Common Activity picklist options from field metadata
    @track activityOptions= [];
    // Map of projectId -> array of activity option objects
    ProjectActivityMap;
    @track absenceList = [];
    @track absenceOptions = [];
    projectIds = [];
    

    @track prevTimesheets= [];
    prevTimesheetValue;

    @track projectsTotals = [0, 0, 0, 0, 0, 0, 0];
    @track absenceTotals = [0, 0, 0, 0, 0, 0, 0];
    @track grandTotals = [0, 0, 0, 0, 0, 0, 0];
    @track billableAmounts = [0, 0, 0, 0, 0, 0, 0];

    TimesheetStartDate='';
    TimeSheetEndDate='';
    TimeSheetName='';
    EmployeeID='';

    previousRecordIDs;
    previousDurations = new Map(); // hours each loaded row had, so the server can tell if it changed since
    previousSignatures = new Map(); // what each loaded row looked like, so only edited rows are sent on Save

    // Unsaved grid edits, and whether the timer changed line items while they were pending.
    isDirty = false;
    timerChangedWhileEditing = false;
    reloadRequestId = 0;
    timerChannel;

    disconnectedCallback() {
        if (this.timerChannel) {
            this.timerChannel.close();
        }
    }

    wiredTimesheetResult;
    error;

    
    dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    dayList=[];

    // Get object info to retrieve recordTypeId
    @wire(getObjectInfo, { objectApiName: TIMESHEET_LINE_ITEM_OBJECT })
    objectInfo;

    // Fetch picklist values for Activity
    @wire(getPicklistValues, { 
        recordTypeId: '$objectInfo.data.defaultRecordTypeId', 
        fieldApiName: ACTIVITY_CATEGORY_FIELD 
    })
    wiredActivityPicklistValues({ error, data }) {
        if (data) {
            // Store the common picklist options
            this.activityOptions = data.values.map(item => ({
                label: item.label,
                value: item.value
            }));
        } else if (error) {
            console.error('Error fetching Activity picklist values:', error);
        }
    }

    // Fetch picklist values for Absence
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

    // Format a Date object as 'YYYY-MM-DD' (local date)
    formatDateYMD(date) {
        const y = date.getFullYear();
        const m = String(date.getMonth() + 1).padStart(2, '0');
        const d = String(date.getDate()).padStart(2, '0');
        return `${y}-${m}-${d}`;
    }

    // Parse server-side date string and return a Date object representing local midnight for that date.
    // Accepts "YYYY-MM-DD" or full ISO "YYYY-MM-DDTHH:MM:SSZ".
    localDateFromServer(dateStr) {
        if (!dateStr) return null;
        // Take only the date portion before 'T' if present
        const dateOnly = String(dateStr).split('T')[0];
        const parts = dateOnly.split('-');
        if (parts.length !== 3) {
            // fallback - let JS try to parse; may include timezone
            const fallback = new Date(dateStr);
            // normalize to local midnight
            return new Date(fallback.getFullYear(), fallback.getMonth(), fallback.getDate());
        }
        const y = parseInt(parts[0], 10);
        const m = parseInt(parts[1], 10) - 1;
        const d = parseInt(parts[2], 10);
        return new Date(y, m, d);
    }

    connectedCallback() {
        // The timer (utility bar, other tabs) announces its changes on this channel.
        if (typeof BroadcastChannel !== 'undefined') {
            this.timerChannel = new BroadcastChannel(TIMER_SYNC_CHANNEL);
            this.timerChannel.onmessage = event => this.handleTimerChange(event.data);
        }

        const fetchPromise = new Promise((resolve, reject) => {
            this.fetchTimesheetData(this.recordId, result => {
                // console.log('timesheet data',JSON.stringify(result));
                this.wiredTimesheetResult = result;
                resolve(result);
            });
        });

        Promise.all([
            fetchPromise,
            this.loadTimesheet()
        ])
            .then(([timesheetData , _loadResult]) => {
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
                // console.log('load timesheet',JSON.stringify(result));
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
        // Defensive: if TimesheetStartDate is already a Date, normalize it; if it's a string, parse safely
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

    loadPrevTimesheets(){
        getEmployeeTimesheetItems({ empId: this.EmployeeID, recordId: this.recordId})
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

    loadProjects() {
        return getProjects({ empId: this.EmployeeID })
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
                        // Build a map of projectId -> array of option objects
                        this.ProjectActivityMap = new Map();
                        result.forEach(item => {
                            const pid = item.dbt__Project__c;
                            const arr = this.ProjectActivityMap.get(pid) || [];
                            arr.push({ label: item.Name, value: item.Name });
                            this.ProjectActivityMap.set(pid, arr);
                        });

                        // After loading project activities, refresh per-row activity options
                        if (Array.isArray(this.projectsList) && this.projectsList.length) {
                            this.projectsList = this.projectsList.map(row => ({
                                ...row,
                                activityOptions: this.getActivityOptionsForProject(row.projectName)
                            }));
                        }
                        console.log('ProjectActivityMap ready');
                    })
            })
            .catch(error => {
                console.error(error);
            });
    }

    // Merge common options with project-specific ones (deduped by value)
    getActivityOptionsForProject(projectId) {
        const common = Array.isArray(this.activityOptions) ? this.activityOptions : [];
        const specific = (this.ProjectActivityMap && projectId && this.ProjectActivityMap.get(projectId)) || [];
        // If no project-specific options, just return common
        if (!specific.length) return common;
        // Merge with project-specific first, then common, with de-dup by value
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

    processTimesheetData(data,includeId) {
        this.projectsList = [];
        this.absenceList = [];

        if (includeId) {
            this.previousRecordIDs = new Set();
            this.previousDurations = new Map();
            this.previousSignatures = new Map();
        }

        let attendanceData = {};
        let absenceData = {};

        // console.log("data",JSON.stringify(data));
  
        data.forEach(item => {
            // Use localDateFromServer to get a local-midnight Date object (no TZ shift)
            const date = this.localDateFromServer(item.dbt__Date__c);
            const dayIndex = date.getDay() === 0 ? 6 : date.getDay() - 1;

            if(includeId){
                this.previousRecordIDs.add(item.Id);
                this.previousDurations.set(item.Id, item.dbt__Duration__c || 0);
                this.previousSignatures.set(item.Id, this.rowSignature({
                    type: item.dbt__Type__c, project: item.dbt__Project__c, activity: item.dbt__Activity__c,
                    absence: item.dbt__Absence_Category__c, date: item.dbt__Date__c,
                    duration: item.dbt__Duration__c, description: item.dbt__Description__c
                }));
            }

            // Helper to update the date data
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

        if(this.projectsList.length === 0) {
            this.addNewProject();
        }

        // calculate totals
        this.calculateTotals();

        // A copied timesheet is unsaved; a fresh load from the server is not.
        this.isDirty = !includeId;
        if (includeId) {
            this.timerChangedWhileEditing = false;
        }
    }

    reloadGrid() {
        // Only the latest reload may apply its result.
        const requestId = ++this.reloadRequestId;
        this.fetchTimesheetData(this.recordId, result => {
            if (requestId !== this.reloadRequestId) return;
            this.wiredTimesheetResult = result;
            this.processTimesheetData(result, true);
        });
    }

    // Reload so a later grid Save does not overwrite the timer's hours. With unsaved
    // edits, warn only when the timer changed hours or removed a row (save, discard).
    handleTimerChange(message) {
        if (!this.isDirty) {
            this.reloadGrid();
        } else if (message && message.affectsHours) {
            this.timerChangedWhileEditing = true;
        }
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
                // Default to common options; per-row options update when project changes
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
        this.isDirty = true;
        const rowIndex = event.target.dataset.rowIndex;
        const fieldName = event.target.name;
        const newValue = event.target.value;

        // Get the current row
        const currentRow = this.projectsList[rowIndex];

        // Create a temporary copy of the current row to test the change
        const tempRow = { ...this.projectsList[rowIndex] };
        
        // Apply the potential change to the temporary row
        if (fieldName === 'projectName') {
            tempRow.projectName = newValue;
        } else if (fieldName === 'activityName') {
            tempRow.activityName = newValue;
        }

        // Only check for duplicates if both fields have values
        if (tempRow.projectName && tempRow.activityName) {
            // Check if this combination would create a duplicate
            const wouldCreateDuplicate = this.projectsList.some((row, index) => 
                index !== parseInt(rowIndex) && 
                row.projectName === tempRow.projectName && 
                row.activityName === tempRow.activityName
            );

            if (wouldCreateDuplicate) {
                // Show error toast
                this.showToast(
                    'Error', 
                    'A row with the same Project and Activity already exists.', 
                    'error'
                );

                // Revert the change by setting the combobox value back
                event.target.value = currentRow[fieldName];
                return; // Exit without making any changes
            }
        }

       // Apply change since it's valid
        currentRow[fieldName] = newValue;

        if (fieldName === 'projectName') {
            // Update billable/hourly based on the selected project
        const selectedProject = this.projectOptions.find(option => option.value === newValue);
        if (selectedProject) {
            currentRow.billable = selectedProject.billable;
            currentRow.hourlyRate = selectedProject.hourly_rate;
        }
            // Refresh per-row activity options for this project
            currentRow.activityOptions = this.getActivityOptionsForProject(newValue);
            // If current activity is not in new options, clear it
            const stillValid = currentRow.activityOptions?.some(opt => opt.value === currentRow.activityName);
            if (!stillValid) {
                currentRow.activityName = '';
            }
        }
        
        // Reassign array reference to trigger reactivity and recalc totals
        this.projectsList = [...this.projectsList];
        this.calculateTotals();
    }

    handleKeyDown(event) {
        // Feature temporarily disabled.
    }

    handleDurationChange(event) {
        this.isDirty = true;
        const rowIndex = event.target.dataset.rowIndex;
        const dayIndex = event.target.dataset.dayIndex;
        const dataFor = event.target.getAttribute('data-for'); // "project" or "absence"
        
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
            } catch(e) {}
        }
    }

    handleDescriptionChange(event) {
        this.isDirty = true;
        const rowIndex = parseInt(event.target.dataset.rowIndex);
        const dayIndex = parseInt(event.target.dataset.dayIndex);
        const newValue = event.target.value;
        const dataFor = event.target.getAttribute('data-for'); // "project" or "absence"
        let list;
        if (dataFor === 'project') {
            list = this.projectsList;
        } else if (dataFor === 'absence') {
            list = this.absenceList;
        }
        
        list[rowIndex].dates[dayIndex].desc = newValue;
    }

    handleDeleteRow(event) {
        this.isDirty = true;
        const rowIndex = parseInt(event.target.dataset.rowIndex);
        const type = event.target.dataset.type;

        try {
            if (type === 'project' && this.projectsList.length>0) {
                // Remove row from projectsList
                this.projectsList = this.projectsList.filter((row, index) => index !== rowIndex);
                
                // If all projects are deleted, you might want to keep at least one empty row
                if (this.projectsList.length === 0) {
                    this.addNewProject();
                }
            } else if (type === 'absence' && this.absenceList.length>0) {
                // Remove row from absenceList
                this.absenceList = this.absenceList.filter((row, index) => index !== rowIndex);
            }

            // Show success toast
            this.showToast('warning', 'Row Removed. Please Click Save', 'warning');
        } catch (error) {
            // Show error toast
            this.showToast('Error', 'Failed to delete row', 'error');
            console.error('Error deleting row:', error);
        }

        // calculate totals
        this.calculateTotals();
    }

    handleAbsenceChange(event) {
        this.isDirty = true;
        const rowIndex = event.target.dataset.rowIndex;
        const newValue = event.target.value;

        // Get the current row's existing value
        const currentRow = this.absenceList[rowIndex];

        // Check if this absence type is already selected in another row
        const isDuplicate = this.absenceList.some((row, index) => 
            index !== parseInt(rowIndex) && row.absenceName === newValue
        );

        if (isDuplicate) {
            // Show error toast if duplicate found
            this.showToast(
                'Error',
                'This absence type is already selected in another row',
                'error'
            );

            // Reset the value in UI to its previous state
            event.target.value = currentRow.absenceName;
            return;
        }

        // Update the absence name if no duplicate
        currentRow.absenceName = newValue;
    }

    handleAddProject() {
        this.isDirty = true;
        this.addNewProject();
    }

    handleAddAbsence() {
        this.isDirty = true;
        this.addNewAbsence();
    }

    addNewProject() {
        const newProject = this.getBlankData("Attendance");
        this.projectsList.push(newProject);
    }

    addNewAbsence() {
        const newAbsence = this.getBlankData("Absence");
        this.absenceList.push(newAbsence);
    }

    async handleSave() {
        if (this.timerChangedWhileEditing) {
            const confirmed = await LightningConfirm.open({
                label: 'Timer changed this timesheet',
                message: 'The timer changed this timesheet after you started editing. Saving now can overwrite or remove the hours it logged. Save anyway?',
                theme: 'warning'
            });
            if (!confirmed) return;
        }
        this.saveGrid();
    }

    // The parts of a row the user can change, as one string, to tell edited rows from untouched ones.
    rowSignature(row) {
        return [
            row.type || '', row.project || '', row.activity || '', row.absence || '',
            String(row.date || '').slice(0, 10), Number(row.duration) || 0, row.description || ''
        ].join('|');
    }

    saveGrid() {
        let upsertList = [];
        let deleteList = [];
        let currentRecordIDs = new Set();

        try {
            let hasError = this.projectsList.some(project => 
                project.dates.some(day => {
                    if (day.dur > 0) {
                        if (project.projectName === '' || project.activityName === '') {
                            this.showToast('Error', "Project name or Activity name cannot be blank", 'error');
                            return true; // Stop iteration
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
                            return true; // Stop iteration
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
            this.showToast('Error', (error && error.message) || String(error), 'error');
            return; // never save a half-built list
        }

        // Rows nobody edited are not sent: saving them again would put old hours over what the timer or a leave
        // approval wrote since the grid was opened. Edited rows are sent with the hours they were loaded with, so
        // the server can refuse the save when they changed meanwhile.
        const loadedHours = {};
        upsertList = upsertList.filter(row => {
            if (!row.Id) return true;
            const unchanged = this.previousSignatures.get(row.Id) === this.rowSignature({
                type: row.dbt__Type__c, project: row.dbt__Project__c, activity: row.dbt__Activity__c,
                absence: row.dbt__Absence_Category__c, date: row.dbt__Date__c,
                duration: row.dbt__Duration__c, description: row.dbt__Description__c
            });
            if (!unchanged) {
                loadedHours[row.Id] = this.previousDurations.get(row.Id) || 0;
            }
            return !unchanged;
        });

        if (upsertList.length === 0 && deleteList.length === 0) {
            this.showToast('Success', 'Records saved', 'success');
            this.reloadGrid();
            return;
        }

        // One server call, one transaction: either the whole week is saved or nothing is.
        saveWeek({
            loadedHours,
            upserts: upsertList,
            deletes: deleteList.map(id => ({
                sobjectType: 'dbt__Timesheet_Line_Item__c',
                Id: id,
                dbt__Duration__c: this.previousDurations.get(id) || 0
            }))
        })
            .then(res => {
                if (!res || !res.success) {
                    throw new Error((res && res.message) || 'The timesheet could not be saved.');
                }
                this.showToast('Success', 'Records saved', 'success');
                if (res.keptTimerRows > 0) {
                    this.showToast('Info', 'A row with a running timer was kept. Save or discard the timer to remove it.', 'info');
                }
                // Open timers show the line item's hours, so let them reload.
                if (this.timerChannel) {
                    this.timerChannel.postMessage({ changed: true, source: 'grid' });
                }
            })
            .catch(e => {
                this.showToast('Error', (e && e.body && e.body.message) || e.message, 'error');
            })
            .finally(() => {
                this.reloadGrid();
            });
    }

    calculateTotals() {
        // Reset totals
        this.projectsTotals = [0, 0, 0, 0, 0, 0, 0];
        this.absenceTotals = [0, 0, 0, 0, 0, 0, 0];
        this.grandTotals = [0, 0, 0, 0, 0, 0, 0];
        this.billableAmounts = [0, 0, 0, 0, 0, 0, 0]; 

        // Calculate Projects totals and billable amounts
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
        // Calculate Absence totals
        this.absenceList.forEach(absence => {
            absence.dates.forEach((day, index) => {
                const duration = parseFloat(day.dur) || 0;
                this.absenceTotals[index] = parseFloat((this.absenceTotals[index] + duration).toFixed(2));
            });
        });

        // Calculate Grand totals
        this.projectsTotals.forEach((total, index) => {
            this.grandTotals[index] = parseFloat((total + this.absenceTotals[index]).toFixed(2));
        });
    }

    prevTimesheet(event) {
        this.prevTimesheetValue=event.detail.value;
    }

    handleCopy(){
        if(this.prevTimesheetValue != undefined){
            // console.log(this.prevTimesheetValue);
            this.fetchTimesheetData(this.prevTimesheetValue, result => {
                // Only the project hours are copied. This week's absence rows (leave from the PTO tab
                // included) stay as they are, so Save never deletes or duplicates them.
                const keptAbsence = this.absenceList;
                this.processTimesheetData(result.filter(item => item.dbt__Type__c === 'Attendance'), false);
                this.absenceList = keptAbsence;
                this.calculateTotals();
                this.showToast('Success', 'Timesheet copied successfully', 'success');
            });
        }
    }

    handleCancel() {
        this.reloadGrid();

        this.template.querySelectorAll('lightning-combobox[data-id="prevTimesheet"]').forEach(cb => {
            cb.value = undefined;
        });
    }
}