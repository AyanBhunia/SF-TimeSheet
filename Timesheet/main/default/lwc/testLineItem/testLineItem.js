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
    @track displayedProjectsList = [];
    @track projectOptions = [];
    // Common Activity picklist options from field metadata
    @track activityOptions= [];
    // Map of projectId -> array of activity option objects
    ProjectActivityMap;
    @track absenceList = [];
    @track displayedAbsenceList = [];
    @track absenceOptions = [];
    projectIds = [];
    

    @track prevTimesheets= [];
    prevTimesheetValue;

    @track projectsTotals = [];
    @track absenceTotals = [];
    @track grandTotals = [];
    @track billableAmounts = [];

    TimesheetStartDate='';
    TimeSheetEndDate='';
    TimeSheetName='';
    EmployeeID='';
    @track timesheetStatus = '';

    get isLocked() {
        return this.timesheetStatus === 'Submitted' || this.timesheetStatus === 'Approved';
    }

    get lockedMessage() {
        if (this.timesheetStatus === 'Submitted') {
            return 'This timesheet has been submitted and is locked for editing.';
        }
        if (this.timesheetStatus === 'Approved') {
            return 'This timesheet has been approved and is locked for editing.';
        }
        return '';
    }

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

    @track dayHeaders = [];
    @track activeWeekIndex = 0; // 0 = Week 1, 1 = Week 2, ..., -1 = All Days

    get isMultiWeek() {
        return this.dayList && this.dayList.length > 7;
    }

    get totalWeeks() {
        return (this.dayList && this.dayList.length) ? Math.ceil(this.dayList.length / 7) : 1;
    }

    get timesheetCardTitle() {
        if (!this.dayList || this.dayList.length <= 7) return 'Weekly Timesheet View';
        if (this.dayList.length <= 14) return 'Bi-Weekly Timesheet View';
        if (this.dayList.length <= 31) return 'Monthly Timesheet View';
        return 'Timesheet View';
    }

    get weekOptions() {
        if (!this.isMultiWeek) return [];
        const options = [];
        for (let w = 0; w < this.totalWeeks; w++) {
            const startIdx = w * 7;
            const endIdx = Math.min((w + 1) * 7 - 1, this.dayList.length - 1);
            const startH = this.dayHeaders[startIdx];
            const endH = this.dayHeaders[endIdx];
            const startLabel = startH ? startH.formattedDate : '';
            const endLabel = endH ? endH.formattedDate : '';
            options.push({
                index: w,
                key: 'week-btn-' + w,
                label: `Week ${w + 1} (${startLabel} - ${endLabel})`,
                shortLabel: `Week ${w + 1}`,
                dateRange: `${startLabel} - ${endLabel}`,
                variant: this.activeWeekIndex === w ? 'brand' : 'neutral'
            });
        }
        return options;
    }

    get allDaysVariant() {
        return this.activeWeekIndex === -1 ? 'brand' : 'neutral';
    }

    get allDaysLabel() {
        const total = this.dayList ? this.dayList.length : 0;
        return `All ${total} Days`;
    }

    get overallTotalHours() {
        return (this.grandTotals || []).reduce((acc, h) => acc + (parseFloat(h) || 0), 0).toFixed(2);
    }

    get overallBillableAmount() {
        return (this.billableAmounts || []).reduce((acc, a) => acc + (parseFloat(a) || 0), 0).toFixed(2);
    }

    get activeWeekHours() {
        const slice = this.getDisplayedSlice(this.grandTotals || []);
        return slice.reduce((acc, item) => acc + (parseFloat(item.val) || 0), 0).toFixed(2);
    }

    get canGoPrev() {
        return this.activeWeekIndex > 0;
    }

    get canGoNext() {
        return this.activeWeekIndex >= 0 && this.activeWeekIndex < this.totalWeeks - 1;
    }

    handleSelectWeek(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.activeWeekIndex = isNaN(index) ? 0 : index;
        this.updateDisplayedRows();
    }

    handleSelectAllDays() {
        this.activeWeekIndex = -1;
        this.updateDisplayedRows();
    }

    handlePrevWeek() {
        if (this.activeWeekIndex > 0) {
            this.activeWeekIndex--;
            this.updateDisplayedRows();
        }
    }

    handleNextWeek() {
        if (this.activeWeekIndex >= 0 && this.activeWeekIndex < this.totalWeeks - 1) {
            this.activeWeekIndex++;
            this.updateDisplayedRows();
        }
    }

    getDisplayedSlice(array) {
        if (!array || !array.length) return [];
        if (!this.isMultiWeek || this.activeWeekIndex === -1) {
            return array.map((val, idx) => ({ val, index: idx }));
        }
        const start = this.activeWeekIndex * 7;
        const end = Math.min(start + 7, (this.dayList && this.dayList.length) ? this.dayList.length : array.length);
        const sliced = array.slice(start, end);
        return sliced.map((val, i) => ({
            val,
            index: start + i
        }));
    }

    get displayedDayHeaders() {
        if (!this.isMultiWeek || this.activeWeekIndex === -1) {
            return this.dayHeaders;
        }
        const start = this.activeWeekIndex * 7;
        const end = Math.min(start + 7, this.dayHeaders.length);
        return this.dayHeaders.slice(start, end);
    }

    get projectsTotalsDisplay() {
        return this.getDisplayedSlice(this.projectsTotals || []).map(item => ({
            key: 'p-' + item.index,
            val: item.val
        }));
    }

    get absenceTotalsDisplay() {
        return this.getDisplayedSlice(this.absenceTotals || []).map(item => ({
            key: 'a-' + item.index,
            val: item.val
        }));
    }

    get grandTotalsDisplay() {
        return this.getDisplayedSlice(this.grandTotals || []).map(item => ({
            key: 'g-' + item.index,
            val: item.val
        }));
    }

    get billableAmountsDisplay() {
        return this.getDisplayedSlice(this.billableAmounts || []).map(item => ({
            key: 'b-' + item.index,
            val: item.val
        }));
    }

    updateDisplayedRows() {
        const isFilteredWeek = (this.isMultiWeek && this.activeWeekIndex !== -1);
        const start = isFilteredWeek ? (this.activeWeekIndex * 7) : 0;
        const end = isFilteredWeek
            ? Math.min(start + 7, (this.dayList && this.dayList.length) ? this.dayList.length : 7)
            : ((this.dayList && this.dayList.length) ? this.dayList.length : 7);

        if (Array.isArray(this.projectsList)) {
            this.projectsList.forEach((row, idx) => {
                if (!row.rowKey) {
                    row.rowKey = 'p-row-' + idx + '-' + Date.now();
                }
                row.realIndex = idx;
                row.isProjectComboboxDisabled = this.isLocked;
                row.isDeleteDisabled = this.isLocked;
                const dates = Array.isArray(row.dates) ? row.dates : [];
                dates.forEach(d => {
                    d.isDurationDisabled = this.isLocked;
                    d.isDescDisabled = d.isdisable || this.isLocked;
                });
                row.displayedDates = dates.slice(start, end);
            });
        }
        if (Array.isArray(this.absenceList)) {
            this.absenceList.forEach((row, idx) => {
                if (!row.rowKey) {
                    row.rowKey = 'a-row-' + idx + '-' + Date.now();
                }
                row.realIndex = idx;
                row.isAbsenceComboboxDisabled = row.hasPto || this.isLocked;
                row.isDeleteDisabled = this.isLocked;
                const dates = Array.isArray(row.dates) ? row.dates : [];
                dates.forEach(d => {
                    d.isDurationDisabled = d.isPto || this.isLocked;
                    d.isDescDisabled = d.isdisable || this.isLocked;
                });
                row.displayedDates = dates.slice(start, end);
            });
        }

        if (!isFilteredWeek) {
            this.displayedProjectsList = [...(this.projectsList || [])];
            this.displayedAbsenceList = [...(this.absenceList || [])];
        } else {
            let weekProjects = (this.projectsList || []).filter(row => {
                const hasHours = (row.displayedDates || []).some(d => (parseFloat(d.dur) || 0) > 0);
                const hasDesc = (row.displayedDates || []).some(d => d.desc && d.desc.trim().length > 0);
                const createdForWeek = (row.createdInWeek === this.activeWeekIndex);
                const unconfigured = (!row.projectName && !row.activityName && row.createdInWeek === this.activeWeekIndex);
                return hasHours || hasDesc || createdForWeek || unconfigured;
            });

            if (weekProjects.length === 0) {
                const blankRow = this.getBlankData("Attendance");
                blankRow.createdInWeek = this.activeWeekIndex;
                blankRow.realIndex = this.projectsList.length;
                blankRow.rowKey = 'p-blank-' + this.activeWeekIndex + '-' + Date.now();
                blankRow.isProjectComboboxDisabled = this.isLocked;
                blankRow.isDeleteDisabled = this.isLocked;
                const dates = Array.isArray(blankRow.dates) ? blankRow.dates : [];
                dates.forEach(d => {
                    d.isDurationDisabled = this.isLocked;
                    d.isDescDisabled = d.isdisable || this.isLocked;
                });
                blankRow.displayedDates = blankRow.dates.slice(start, end);
                this.projectsList.push(blankRow);
                weekProjects = [blankRow];
            }
            this.displayedProjectsList = weekProjects;

            let weekAbsences = (this.absenceList || []).filter(row => {
                const hasHours = (row.displayedDates || []).some(d => (parseFloat(d.dur) || 0) > 0);
                const hasDesc = (row.displayedDates || []).some(d => d.desc && d.desc.trim().length > 0);
                const createdForWeek = (row.createdInWeek === this.activeWeekIndex);
                const unconfigured = (!row.absenceName && row.createdInWeek === this.activeWeekIndex);
                return hasHours || hasDesc || createdForWeek || unconfigured;
            });
            this.displayedAbsenceList = weekAbsences;
        }
    }

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
                this.EmployeeID = result.dbt__Employee__c || result.Employee__c;
                this.TimesheetStartDate = result.dbt__Start_Date__c || result.Start_Date__c;
                this.TimeSheetEndDate = result.dbt__End_Date__c || result.End_Date__c;
                this.TimeSheetName = result.name || result.Name;
                this.timesheetStatus = result.dbt__Status__c || result.Status__c || '';
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
            this.dayNames = [];
            this.dayHeaders = [];
            return;
        }

        let totalDays = 7;
        if (this.TimeSheetEndDate) {
            const endDateObj = (this.TimeSheetEndDate instanceof Date)
                ? new Date(this.TimeSheetEndDate.getFullYear(), this.TimeSheetEndDate.getMonth(), this.TimeSheetEndDate.getDate())
                : this.localDateFromServer(this.TimeSheetEndDate);
            if (endDateObj && endDateObj >= startDateObj) {
                const diffMs = endDateObj.getTime() - startDateObj.getTime();
                totalDays = Math.round(diffMs / (1000 * 60 * 60 * 24)) + 1;
            }
        }

        const weekdayNames = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
        const monthNames = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
        this.dayNames = [];
        this.dayHeaders = [];
        this.dayList = Array.from({ length: totalDays }, (_, i) => {
            const temp = new Date(startDateObj.getFullYear(), startDateObj.getMonth(), startDateObj.getDate() + i);
            const dayName = weekdayNames[temp.getDay()];
            const ymd = this.formatDateYMD(temp);
            const shortMonth = monthNames[temp.getMonth()];
            const dayNum = String(temp.getDate()).padStart(2, '0');
            const formattedDate = `${shortMonth} ${dayNum}`;
            this.dayNames.push(dayName);
            this.dayHeaders.push({
                key: ymd,
                name: dayName.substring(0, 3).toUpperCase(),
                fullDayName: dayName,
                formattedDate: formattedDate,
                date: ymd,
                index: i
            });
            return ymd;
        });

        this.projectsTotals = new Array(totalDays).fill(0);
        this.absenceTotals = new Array(totalDays).fill(0);
        this.grandTotals = new Array(totalDays).fill(0);
        this.billableAmounts = new Array(totalDays).fill(0);
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
                this.projectOptions = result.map(proj => {
                    const projRel = proj.dbt__Project__r || proj.Project__r;
                    const projId = proj.dbt__Project__c || proj.Project__c;
                    const billable = projRel ? (projRel.dbt__Billable__c || projRel.Billable__c) : 'No';
                    const hourlyRate = proj.dbt__Hourly_Rate__c != null ? proj.dbt__Hourly_Rate__c : (proj.Hourly_Rate__c != null ? proj.Hourly_Rate__c : 0);
                    return {
                        label: projRel ? projRel.Name : '',
                        value: projId,
                        billable: billable,
                        hourly_rate: hourlyRate
                    };
                });
                this.projectIds = result.map(proj => proj.dbt__Project__c || proj.Project__c);
            })
            .then(() => {
                getProjectActivities({ projectIds: this.projectIds })
                    .then(result => {
                        console.log('Project Activities:', JSON.stringify(result));
                        // Build a map of projectId -> array of option objects
                        this.ProjectActivityMap = new Map();
                        result.forEach(item => {
                            const pid = item.dbt__Project__c || item.Project__c;
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
            const itemDate = item.dbt__Date__c || item.Date__c;
            const itemDur = item.dbt__Duration__c != null ? item.dbt__Duration__c : (item.Duration__c != null ? item.Duration__c : 0);
            const itemType = item.dbt__Type__c || item.Type__c;
            const itemProj = item.dbt__Project__c || item.Project__c;
            const itemAct = item.dbt__Activity__c || item.Activity__c;
            const itemAbs = item.dbt__Absence_Category__c || item.Absence_Category__c;
            const itemDesc = item.dbt__Description__c != null ? item.dbt__Description__c : (item.Description__c != null ? item.Description__c : '');
            const itemProjRel = item.dbt__Project__r || item.Project__r;
            const itemBillable = itemProjRel ? (itemProjRel.dbt__Billable__c || itemProjRel.Billable__c) : undefined;
            const ptoRel = item.dbt__Leave_Line_Items__r || item.Leave_Line_Items__r;
            const isPto = !!(ptoRel && (Array.isArray(ptoRel) ? ptoRel.length > 0 : ptoRel.records && ptoRel.records.length > 0));

            // Match date directly against the timesheet dayList
            const dayIndex = this.dayList.indexOf(itemDate);
            if (dayIndex === -1) {
                return;
            }

            if(includeId){
                this.previousRecordIDs.add(item.Id);
                this.previousDurations.set(item.Id, itemDur || 0);
                this.previousSignatures.set(item.Id, this.rowSignature({
                    type: itemType, project: itemProj, activity: itemAct,
                    absence: itemAbs, date: itemDate,
                    duration: itemDur, description: itemDesc
                }));
            }

            // Helper to update the date data
            const updateDate = (record, isPtoItem) => {
                record.dates[dayIndex].dayIndex = dayIndex;
                record.dates[dayIndex].dur = itemDur || 0;
                record.dates[dayIndex].desc = itemDesc || '';
                record.dates[dayIndex].id = includeId ? item.Id : null; 
                record.dates[dayIndex].isdisable = isPtoItem ? true : false;
                if (isPtoItem) {
                    record.dates[dayIndex].isPto = true;
                    record.hasPto = true;
                }
            };

            if (itemType === "Attendance") {

                const key = `${itemProj}_${itemAct}`;

                if (!attendanceData[key]) {
                    const selectedProject = this.projectOptions.find(option => option.value === itemProj);
                    attendanceData[key] = {
                        ...this.getBlankData("Attendance"),
                        projectName: itemProj,
                        activityName: itemAct,
                        billable: itemBillable,
                        hourlyRate: (selectedProject && selectedProject.hourly_rate) ? selectedProject.hourly_rate : 0
                    };
                }
                updateDate(attendanceData[key], false); 
            } else {
                const key = itemAbs;
                if (!absenceData[key]) {
                    absenceData[key] = {
                        ...this.getBlankData("Absence"),
                        absenceName: itemAbs
                    };
                }
                updateDate(absenceData[key], isPto);
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
        this.updateDisplayedRows();

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
        const rowUid = 'row_' + Date.now() + '_' + Math.random().toString(36).substring(2, 7);
        const dates = this.dayNames.map((name, index) => {
            return {
                id: null,
                isdisable: true,
                date: this.dayList[index],
                dayIndex: index,
                name,
                dur: 0,
                desc: "",
                isPto: false
            };
        });

        if (type === "Attendance") {
            return {
                rowKey: rowUid,
                createdInWeek: null,
                type: "Attendance",
                projectName: "",
                activityName: "",
                billable: "",
                hourlyRate: 0,
                // Default to common options; per-row options update when project changes
                activityOptions: Array.isArray(this.activityOptions) ? this.activityOptions : [],
                dates,
                displayedDates: []
            };
        } else {
            return {
                rowKey: rowUid,
                createdInWeek: null,
                type: "Absence",
                absenceName: "",
                hasPto: false,
                dates,
                displayedDates: []
            };
        }
    }

    handleProjectChange(event) {
        if (this.isLocked) {
            return;
        }
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

        // Check for duplicates / existing row across month
        if (tempRow.projectName && tempRow.activityName) {
            const existingRowIndex = this.projectsList.findIndex((row, index) => 
                index !== parseInt(rowIndex, 10) && 
                row.projectName === tempRow.projectName && 
                row.activityName === tempRow.activityName
            );

            if (existingRowIndex !== -1) {
                if (this.isMultiWeek && this.activeWeekIndex !== -1) {
                    const existingRow = this.projectsList[existingRowIndex];
                    const currentHasHours = (currentRow.dates || []).some(d => (parseFloat(d.dur) || 0) > 0);
                    if (!currentHasHours && this.projectsList.length > 1) {
                        this.projectsList = this.projectsList.filter((_, idx) => idx !== parseInt(rowIndex, 10));
                    }
                    existingRow.createdInWeek = this.activeWeekIndex;
                    this.calculateTotals();
                    this.updateDisplayedRows();
                    this.showToast('Info', `Loaded row for ${tempRow.projectName} - ${tempRow.activityName}`, 'info');
                    return;
                } else {
                    this.showToast(
                        'Error', 
                        'A row with the same Project and Activity already exists.', 
                        'error'
                    );
                    event.target.value = currentRow[fieldName];
                    return;
                }
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
        this.updateDisplayedRows();
    }

    handleKeyDown(event) {
        // Feature temporarily disabled.
    }

    handleDurationChange(event) {
        if (this.isLocked) {
            return;
        }
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
        
        if (dataFor === 'project') {
            this.projectsList = [...this.projectsList];
        } else if (dataFor === 'absence') {
            this.absenceList = [...this.absenceList];
        }
        this.updateDisplayedRows();
        
        if (wasTruncated) {
            try {
                event.target.value = rawStr;
            } catch(e) {}
        }
    }

    handleDescriptionChange(event) {
        if (this.isLocked) {
            return;
        }
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
        if (this.isLocked) {
            return;
        }
        this.isDirty = true;
        const rowIndex = parseInt(event.target.dataset.rowIndex, 10);
        const type = event.target.dataset.type;

        try {
            if (type === 'project' && this.projectsList.length > 0) {
                const targetRow = this.projectsList[rowIndex];
                if (!targetRow) return;

                const isFilteredWeek = (this.isMultiWeek && this.activeWeekIndex !== -1);
                const hasHoursInOtherWeeks = (targetRow.dates || []).some((d, idx) => {
                    if (!isFilteredWeek) return false;
                    const start = this.activeWeekIndex * 7;
                    const end = start + 7;
                    const inThisWeek = (idx >= start && idx < end);
                    return !inThisWeek && (parseFloat(d.dur) || 0) > 0;
                });

                if (isFilteredWeek && hasHoursInOtherWeeks) {
                    // Clear only the hours in the active week
                    const start = this.activeWeekIndex * 7;
                    const end = Math.min(start + 7, targetRow.dates.length);
                    for (let i = start; i < end; i++) {
                        targetRow.dates[i].dur = 0;
                        targetRow.dates[i].desc = '';
                        targetRow.dates[i].isdisable = true;
                    }
                    targetRow.createdInWeek = null;
                    this.showToast('Info', 'Hours for the active week cleared.', 'info');
                } else {
                    // Remove row from projectsList
                    this.projectsList = this.projectsList.filter((_, index) => index !== rowIndex);
                    if (this.projectsList.length === 0) {
                        this.addNewProject();
                    }
                    this.showToast('warning', 'Row Removed. Please Click Save', 'warning');
                }
            } else if (type === 'absence' && this.absenceList.length > 0) {
                const targetRow = this.absenceList[rowIndex];
                if (targetRow && targetRow.hasPto) {
                    this.showToast('Warning', 'Absence rows created from approved PTO leave cannot be deleted from the timesheet.', 'warning');
                    return;
                }
                const isFilteredWeek = (this.isMultiWeek && this.activeWeekIndex !== -1);
                const hasHoursInOtherWeeks = (targetRow.dates || []).some((d, idx) => {
                    if (!isFilteredWeek) return false;
                    const start = this.activeWeekIndex * 7;
                    const end = start + 7;
                    const inThisWeek = (idx >= start && idx < end);
                    return !inThisWeek && (parseFloat(d.dur) || 0) > 0;
                });

                if (isFilteredWeek && hasHoursInOtherWeeks) {
                    const start = this.activeWeekIndex * 7;
                    const end = Math.min(start + 7, targetRow.dates.length);
                    for (let i = start; i < end; i++) {
                        targetRow.dates[i].dur = 0;
                        targetRow.dates[i].desc = '';
                        targetRow.dates[i].isdisable = true;
                    }
                    targetRow.createdInWeek = null;
                    this.showToast('Info', 'Hours for the active week cleared.', 'info');
                } else {
                    this.absenceList = this.absenceList.filter((_, index) => index !== rowIndex);
                    this.showToast('warning', 'Row Removed. Please Click Save', 'warning');
                }
            }
        } catch (error) {
            this.showToast('Error', 'Failed to delete row', 'error');
            console.error('Error deleting row:', error);
        }

        // calculate totals
        this.calculateTotals();
        this.updateDisplayedRows();
    }

    handleAbsenceChange(event) {
        if (this.isLocked) {
            return;
        }
        this.isDirty = true;
        const rowIndex = parseInt(event.target.dataset.rowIndex, 10);
        const newValue = event.target.value;

        // Get the current row's existing value
        const currentRow = this.absenceList[rowIndex];

        // Check if this absence type is already selected in another row
        const existingAbsenceIndex = this.absenceList.findIndex((row, index) => 
            index !== rowIndex && row.absenceName === newValue
        );

        if (existingAbsenceIndex !== -1) {
            if (this.isMultiWeek && this.activeWeekIndex !== -1) {
                const existingRow = this.absenceList[existingAbsenceIndex];
                const currentHasHours = (currentRow.dates || []).some(d => (parseFloat(d.dur) || 0) > 0);
                if (!currentHasHours && this.absenceList.length > 1) {
                    this.absenceList = this.absenceList.filter((_, idx) => idx !== rowIndex);
                }
                existingRow.createdInWeek = this.activeWeekIndex;
                this.calculateTotals();
                this.updateDisplayedRows();
                this.showToast('Info', `Loaded row for ${newValue}`, 'info');
                return;
            } else {
                this.showToast(
                    'Error',
                    'This absence type is already selected in another row',
                    'error'
                );
                event.target.value = currentRow.absenceName;
                return;
            }
        }

        // Update the absence name if no duplicate
        currentRow.absenceName = newValue;
        this.calculateTotals();
        this.updateDisplayedRows();
    }

    handleAddProject() {
        if (this.isLocked) {
            return;
        }
        this.isDirty = true;
        this.addNewProject();
    }

    handleAddAbsence() {
        if (this.isLocked) {
            return;
        }
        this.isDirty = true;
        this.addNewAbsence();
    }

    addNewProject() {
        const newProject = this.getBlankData("Attendance");
        if (this.isMultiWeek && this.activeWeekIndex !== -1) {
            newProject.createdInWeek = this.activeWeekIndex;
        }
        this.projectsList.push(newProject);
        this.updateDisplayedRows();
    }

    addNewAbsence() {
        const newAbsence = this.getBlankData("Absence");
        if (this.isMultiWeek && this.activeWeekIndex !== -1) {
            newAbsence.createdInWeek = this.activeWeekIndex;
        }
        this.absenceList.push(newAbsence);
        this.updateDisplayedRows();
    }

    async handleSave() {
        if (this.isLocked) {
            this.showToast('Timesheet Locked', this.lockedMessage, 'warning');
            return;
        }
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
                        const projOption = this.projectOptions.find(option => option.value === project.projectName);
                        upsertList.push({
                            Id: day.id,
                            Timesheet__c: this.recordId,
                            dbt__Timesheet__c: this.recordId,
                            Type__c: "Attendance",
                            dbt__Type__c: "Attendance",
                            Project__c: project.projectName,
                            dbt__Project__c: project.projectName,
                            Activity__c: project.activityName,
                            dbt__Activity__c: project.activityName,
                            Duration__c: day.dur,
                            dbt__Duration__c: day.dur,
                            Description__c: day.desc,
                            dbt__Description__c: day.desc,
                            Date__c: day.date,
                            dbt__Date__c: day.date,
                            Billable__c: projOption?.billable || "No",
                            dbt__Billable__c: projOption?.billable || "No",
                            Hours_Limit_Exceeded__c: false,
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
                        const absOption = this.projectOptions.find(option => option.value === absence.absenceName);
                        upsertList.push({
                            Id: day.id,
                            Timesheet__c: this.recordId,
                            dbt__Timesheet__c: this.recordId,
                            Type__c: "Absence",
                            dbt__Type__c: "Absence",
                            Absence_Category__c: absence.absenceName,
                            dbt__Absence_Category__c: absence.absenceName,
                            Duration__c: day.dur,
                            dbt__Duration__c: day.dur,
                            Description__c: day.desc,
                            dbt__Description__c: day.desc,
                            Date__c: day.date,
                            dbt__Date__c: day.date,
                            Billable__c: absOption?.billable || "No",
                            dbt__Billable__c: absOption?.billable || "No",
                            Hours_Limit_Exceeded__c: false,
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
                type: row.Type__c || row.dbt__Type__c,
                project: row.Project__c || row.dbt__Project__c,
                activity: row.Activity__c || row.dbt__Activity__c,
                absence: row.Absence_Category__c || row.dbt__Absence_Category__c,
                date: row.Date__c || row.dbt__Date__c,
                duration: row.Duration__c != null ? row.Duration__c : row.dbt__Duration__c,
                description: row.Description__c != null ? row.Description__c : row.dbt__Description__c
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
                Id: id,
                Duration__c: this.previousDurations.get(id) || 0,
                dbt__Duration__c: this.previousDurations.get(id) || 0
            }))
        })
            .then(res => {
                if (!res || !res.success) {
                    throw new Error((res && res.message) || 'The timesheet could not be saved.');
                }
                this.showToast('Success', 'Records saved', 'success');
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
        // Reset totals matching dayList length
        const len = (this.dayList && this.dayList.length) ? this.dayList.length : 7;
        this.projectsTotals = new Array(len).fill(0);
        this.absenceTotals = new Array(len).fill(0);
        this.grandTotals = new Array(len).fill(0);
        this.billableAmounts = new Array(len).fill(0); 

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
        if (this.isLocked) {
            return;
        }
        if(this.prevTimesheetValue != undefined){
            // console.log(this.prevTimesheetValue);
            this.fetchTimesheetData(this.prevTimesheetValue, result => {
                // Only the project hours are copied. This week's absence rows (leave from the PTO tab
                // included) stay as they are, so Save never deletes or duplicates them.
                const keptAbsence = this.absenceList;
                this.processTimesheetData(result.filter(item => (item.dbt__Type__c || item.Type__c) === 'Attendance'), false);
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