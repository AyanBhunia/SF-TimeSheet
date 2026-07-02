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



export default class TimesheetLineItemEntry extends LightningElement {
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
    

    @track prevTimesheets = [{ label: 'Select a previous Timesheet to copy', value: '' }];
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

    wiredTimesheetResult;
    error;

    hasUnsavedChanges = false;

    @track isNoteModalOpen = false;
    currentNoteDesc = '';
    currentNoteContext = null;

    dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    dayList=[];
    @track dayHeaders = [];

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
            this.activityOptions = [
                { label: 'Select an Activity', value: '' },
                ...data.values.map(item => ({
                label: item.label,
                value: item.value
            }))];
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
            this.absenceOptions = [
                { label: 'Select an Absence Category', value: '' },
                ...data.values.map(item => ({
                label: item.label,
                value: item.value
            }))];
        } else if (error) {
            console.error('Error fetching Absence picklist values:', error);
        }
    }

    showToast(title, message, variant, mode = 'dismissible') {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
            mode: mode
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
        window.addEventListener('beforeunload', this.beforeUnloadHandler);
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

    disconnectedCallback() {
        window.removeEventListener('beforeunload', this.beforeUnloadHandler);
    }

    beforeUnloadHandler = (event) => {
        if (this.hasUnsavedChanges) {
            event.preventDefault();
            event.returnValue = "There are unsaved changes and this action will erase the data, do you want to proceed?";
        }
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

        this.dayHeaders = this.dayNames.map((name, i) => ({
            name: name,
            date: this.dayList[i]
        }));
    }

    loadPrevTimesheets(){
        getEmployeeTimesheetItems({ empId: this.EmployeeID, recordId: this.recordId})
            .then(result => {
                this.prevTimesheets = [
                    { label: 'Select a previous Timesheet to copy', value: '' },
                    ...result.map(item => ({
                    label: item.Name,
                    value: item.Id
                }))];
            })
            .catch(error => {
                console.error(error);
            });
    }

    loadProjects() {
        return getProjects({ empId: this.EmployeeID })
            .then(result => {
                this.projectOptions = [
                    { label: 'Select a Project', value: '' },
                    ...result.map(proj => {
                    let isActive = true;
                    if (proj.dbt__Project__r) {
                        if (proj.dbt__Project__r.dbt__Active__c !== undefined) {
                            isActive = proj.dbt__Project__r.dbt__Active__c;
                        } else if (proj.dbt__Project__r.Active__c !== undefined) {
                            isActive = proj.dbt__Project__r.Active__c;
                        }
                    }
                    return {
                        label: proj.dbt__Project__r.Name,
                        value: proj.dbt__Project__c,
                        billable: proj.dbt__Project__r?.dbt__Billable__c,
                        hourly_rate: proj.dbt__Hourly_Rate__c || 0,
                        active: isActive
                    };
                })];
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
        const common = Array.isArray(this.activityOptions) ? this.activityOptions.filter(opt => opt.value !== '') : [];
        const specific = (this.ProjectActivityMap && projectId && this.ProjectActivityMap.get(projectId)) || [];
        if (!specific.length) return [
            { label: 'Select an Activity', value: '' },
            ...common
        ];
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
        return [
            { label: 'Select an Activity', value: '' },
            ...merged
        ];
    }

    processTimesheetData(data,includeId) {
        this.projectsList = [];
        this.absenceList = [];

        if (includeId) {
            this.previousRecordIDs = new Set();
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
            }

            const updateDate = record => {
                let dur = parseFloat(item.dbt__Duration__c) || 0;
                record.dates[dayIndex].dur = dur;
                record.dates[dayIndex].desc = item.dbt__Description__c || '';
                record.dates[dayIndex].id = includeId ? item.Id : null; 
                record.dates[dayIndex].isdisable = (dur === 0);
                record.dates[dayIndex].noteLabel = item.dbt__Description__c ? 'Note ✓' : (dur === 0 ? 'Note' : 'Note +');
                record.dates[dayIndex].noteClass = item.dbt__Description__c ? 'note-button note-has-text' : 'note-button';
                record.dates[dayIndex].inputClass = (dur === 0) ? 'duration-empty' : '';
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
        this.hasUnsavedChanges = false;
    }

    getBlankData(type) {
        
        const dates = this.dayNames.map((name, index) => {
            return {
                id: null,
                isdisable: true,
                date: this.dayList[index],
                name,
                dur: 0,
                desc: "",
                noteLabel: "Note",
                noteClass: "note-button",
                inputClass: "duration-empty"
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
                activityOptions: Array.isArray(this.activityOptions) && this.activityOptions.length > 0 ? this.activityOptions : [{ label: 'Select an Activity', value: '' }],
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
        this.hasUnsavedChanges = true;
    }

    handleKeyDown(event) {
        // Feature temporarily disabled.
    }

    handleDurationChange(event) {
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
        let isdisable = (value === 0);
        list[rowIndex].dates[dayIndex].isdisable = isdisable;
        let hasDesc = !!list[rowIndex].dates[dayIndex].desc;
        list[rowIndex].dates[dayIndex].noteLabel = hasDesc ? 'Note ✓' : (isdisable ? 'Note' : 'Note +');
        list[rowIndex].dates[dayIndex].inputClass = isdisable ? 'duration-empty' : '';
        
        if (wasTruncated) {
            try {
                event.target.value = rawStr;
            } catch(e) {}
        }
        this.hasUnsavedChanges = true;
    }

    get characterCount() {
        return this.currentNoteDesc ? this.currentNoteDesc.length : 0;
    }

    async handlePasteText() {
        try {
            const text = await navigator.clipboard.readText();
            if (text) {
                let current = this.currentNoteDesc || '';
                let newText = current + text;
                if (newText.length > 255) {
                    newText = newText.substring(0, 255);
                    this.showToast('Warning', 'Pasted text was truncated to 255 characters.', 'warning');
                }
                this.currentNoteDesc = newText;
            }
        } catch (err) {
            this.showToast('Error', 'Failed to paste text. Clipboard access may be denied.', 'error');
        }
    }

    async handleCopyText() {
        if (this.currentNoteDesc) {
            try {
                await navigator.clipboard.writeText(this.currentNoteDesc);
                this.showToast('Success', 'Text copied to clipboard!', 'success');
            } catch (err) {
                this.showToast('Error', 'Failed to copy text.', 'error');
            }
        }
    }

    handleNoteClick(event) {
        const rowIndex = parseInt(event.target.dataset.rowIndex);
        const dayIndex = parseInt(event.target.dataset.dayIndex);
        const dataFor = event.target.getAttribute('data-for'); // "project" or "absence"
        
        let list = dataFor === 'project' ? this.projectsList : this.absenceList;
        this.currentNoteDesc = list[rowIndex].dates[dayIndex].desc || '';
        
        this.currentNoteContext = { rowIndex, dayIndex, dataFor };
        this.isNoteModalOpen = true;
    }

    handleModalDescriptionChange(event) {
        this.currentNoteDesc = event.target.value;
    }

    closeNoteModal() {
        this.isNoteModalOpen = false;
        this.currentNoteContext = null;
    }

    saveNoteModal() {
        if (!this.currentNoteContext) return;
        
        const { rowIndex, dayIndex, dataFor } = this.currentNoteContext;
        let list = dataFor === 'project' ? this.projectsList : this.absenceList;
        
        let isdisable = list[rowIndex].dates[dayIndex].isdisable;
        list[rowIndex].dates[dayIndex].desc = this.currentNoteDesc;
        list[rowIndex].dates[dayIndex].noteLabel = this.currentNoteDesc ? 'Note ✓' : (isdisable ? 'Note' : 'Note +');
        list[rowIndex].dates[dayIndex].noteClass = this.currentNoteDesc ? 'note-button note-has-text' : 'note-button';
        
        this.hasUnsavedChanges = true;
        this.isNoteModalOpen = false;
        this.currentNoteContext = null;
    }

    handleDeleteRow(event) {
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
        this.hasUnsavedChanges = true;
    }

    handleAbsenceChange(event) {
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
        this.hasUnsavedChanges = true;
    }

    addNewProject() {
        const newProject = this.getBlankData("Attendance");
        this.projectsList.push(newProject);
        this.hasUnsavedChanges = true;
    }

    addNewAbsence() {
        const newAbsence = this.getBlankData("Absence");
        this.absenceList.push(newAbsence);
        this.hasUnsavedChanges = true;
    }

    handleSave(){
        let upsertList = [];
        let deleteList;
        let currentRecordIDs = new Set();
        let hasError = false;
        let errorMessages = new Set();

        // Clear previous validities
        this.template.querySelectorAll('.custom-error').forEach(el => {
            el.classList.remove('custom-error');
        });
        this.template.querySelectorAll('.custom-error-wrapper').forEach(el => {
            el.classList.remove('custom-error-wrapper');
        });
        this.template.querySelectorAll('lightning-input, lightning-select').forEach(input => {
            input.setCustomValidity('');
            input.reportValidity();
        });

        try {
            this.projectsList.forEach((project, rowIndex) => {
                let hasDuration = project.dates.some(day => parseFloat(day.dur) > 0);
                if (hasDuration && project.projectName) {
                    const selectedProject = this.projectOptions.find(option => option.value === project.projectName);
                    if (selectedProject && selectedProject.active === false) {
                        hasError = true;
                        errorMessages.add(`The project ${selectedProject.label} is inactive, not able to save the record.`);
                        let comboWrapper = this.template.querySelector(`div[data-wrapper="projectName"][data-row-index="${rowIndex}"]`);
                        if (comboWrapper) {
                            comboWrapper.classList.add('custom-error-wrapper');
                        }
                    }
                }
                
                project.dates.forEach((day, dayIndex) => {
                    if (parseFloat(day.dur) > 0) {
                        if (day.desc && day.desc.length > 255) {
                            hasError = true;
                            errorMessages.add(`Description is too long on ${this.dayNames[dayIndex]} (max 255 characters).`);
                            let input = this.template.querySelector(`button[data-for="project"][data-row-index="${rowIndex}"][data-day-index="${dayIndex}"]`);
                            if (input) {
                                input.classList.add('custom-error');
                            }
                        }
                        if (!project.projectName || !project.activityName) {
                            hasError = true;
                            if (!project.projectName) {
                                errorMessages.add("Project name cannot be blank");
                                let comboWrapper = this.template.querySelector(`div[data-wrapper="projectName"][data-row-index="${rowIndex}"]`);
                                if (comboWrapper) {
                                    comboWrapper.classList.add('custom-error-wrapper');
                                }
                            }
                            if (!project.activityName) {
                                errorMessages.add("Activity name cannot be blank");
                                let comboWrapper = this.template.querySelector(`div[data-wrapper="activityName"][data-row-index="${rowIndex}"]`);
                                if (comboWrapper) {
                                    comboWrapper.classList.add('custom-error-wrapper');
                                }
                            }
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
                });
            });

            this.absenceList.forEach((absence, rowIndex) => {
                absence.dates.forEach((day, dayIndex) => {
                    if (parseFloat(day.dur) > 0) {
                        if (day.desc && day.desc.length > 255) {
                            hasError = true;
                            errorMessages.add(`Description is too long on ${this.dayNames[dayIndex]} (max 255 characters).`);
                            let input = this.template.querySelector(`button[data-for="absence"][data-row-index="${rowIndex}"][data-day-index="${dayIndex}"]`);
                            if (input) {
                                input.classList.add('custom-error');
                            }
                        }
                        if (!absence.absenceName) {
                            hasError = true;
                            errorMessages.add("Absence name cannot be blank");
                            let comboWrapper = this.template.querySelector(`div[data-wrapper="absenceName"][data-row-index="${rowIndex}"]`);
                            if (comboWrapper) {
                                comboWrapper.classList.add('custom-error-wrapper');
                            }
                        }
                        if (parseFloat(day.dur) > 8) {
                            hasError = true;
                            errorMessages.add("Duration cannot be greater than 8 for Absence.");
                            let input = this.template.querySelector(`lightning-input[data-for="absence"][data-row-index="${rowIndex}"][data-day-index="${dayIndex}"]`);
                            if (input) {
                                input.classList.add('custom-error');
                            }
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
                            dbt__Billable__c: "No",
                            dbt__Hours_Limit_Exceeded__c: false
                        });
                    }
                });
            });
            
            this.grandTotals.forEach((total, dayIndex) => {
                if (total > 24) {
                    hasError = true;
                    errorMessages.add(`Duration entered for ${this.dayNames[dayIndex]} has exceeded 24 hours`);
                    this.template.querySelectorAll(`lightning-input[data-day-index="${dayIndex}"]`).forEach(input => {
                        input.classList.add('custom-error');
                    });
                }
            });

            if (hasError) {
                let msg = Array.from(errorMessages).join('\n');
                this.showToast('Validation Error', msg, 'error', 'dismissable');
                return;
            }

            deleteList = [...this.previousRecordIDs].filter(id => !currentRecordIDs.has(id));

        } catch (error) {
            let errorMsg = error.message || String(error);
            errorMsg = errorMsg.replace(/.*first error:\s*[A-Z_]+,\s*/g, '').replace(/\[.*\]/g, '');
            this.showToast('Error', errorMsg, 'error', 'dismissable');
            return;
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
                this.hasUnsavedChanges = false;
                this.showToast('Success', 'Records saved', 'success');
                this.fetchTimesheetData(this.recordId, result => {
                    this.wiredTimesheetResult = result;
                    this.processTimesheetData(this.wiredTimesheetResult, true);
                });
            })
            .catch(e => {
                let errorMsg = e.message || String(e);
                errorMsg = errorMsg.replace(/.*first error:\s*[A-Z_]+,\s*/g, '').replace(/\[.*\]/g, '');
                
                if (errorMsg.includes('FIELD_FILTER_VALIDATION_EXCEPTION')) {
                    errorMsg = 'A selected project is inactive, not able to save the record.';
                }

                this.showToast('Save Error', errorMsg, 'error', 'dismissable');
            })
        );
        
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
                this.processTimesheetData(result,false);
                this.showToast('Success', 'Timesheet copied successfully', 'success');
            });
        }
    }

    handleCancel() {
        // Clear any validation highlights
        this.template.querySelectorAll('.custom-error').forEach(el => {
            el.classList.remove('custom-error');
        });
        this.template.querySelectorAll('.custom-error-wrapper').forEach(el => {
            el.classList.remove('custom-error-wrapper');
        });

        this.processTimesheetData(this.wiredTimesheetResult,true);

        this.template.querySelectorAll('lightning-select[data-id="prevTimesheet"]').forEach(cb => {
            cb.value = undefined;
        });
    }
}