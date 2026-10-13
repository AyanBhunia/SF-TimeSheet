import { LightningElement, track } from 'lwc';
import getTimesheetData from '@salesforce/apex/TimesheetApprovalController.getTimesheetData';
import approveLineItems from '@salesforce/apex/TimesheetApprovalController.approveLineItems';
import rejectLineItemsWithNotes from '@salesforce/apex/TimesheetApprovalController.rejectLineItemsWithNotes';
import approveTimesheets from '@salesforce/apex/TimesheetApprovalController.approveTimesheets';
import rejectTimesheets from '@salesforce/apex/TimesheetApprovalController.rejectTimesheets';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const MAIN_MAX = 200;

const MAIN_COLUMN_DEFS = [
{ id: 'employeeName', label: 'Employee', fieldName: 'employeeName', order: 1, isExpanded: true, isDuration: false, sortDirection: 'asc', isFilterOpen: false },
{ id: 'date', label: 'Date', fieldName: 'date', order: 2, isExpanded: true, isDuration: false, sortDirection: 'asc', isFilterOpen: false },
{ id: 'projectName', label: 'Project', fieldName: 'projectName', order: 3, isExpanded: true, isDuration: false, sortDirection: 'asc', isFilterOpen: false },
{ id: 'activityName', label: 'Activity', fieldName: 'activityName', order: 4, isExpanded: true, isDuration: false, sortDirection: 'asc', isFilterOpen: false },
{ id: 'duration', label: 'Duration', fieldName: 'duration', order: 5, isExpanded: true, isDuration: true, sortDirection: 'asc', isFilterOpen: false },
{ id: 'status', label: 'Status', fieldName: 'status', order: 6, isExpanded: true, isDuration: false, sortDirection: 'asc', isFilterOpen: false }
];

export default class TimesheetApprovalScreen extends LightningElement {

@track dateRange =
window.localStorage.getItem('managerApprovalDateRange') || 'Current Week';
@track statusFilter = 'All';
@track employeeSearch = '';
@track projectFilter = 'All';
@track isBulkRejectModalOpen = false;
@track bulkRejectionReason = '';
@track customStartDate =
window.localStorage.getItem('managerApprovalCustomStartDate') || null;

@track customEndDate =
window.localStorage.getItem('managerApprovalCustomEndDate') || null;
@track isTableLoading = false;

@track columns = MAIN_COLUMN_DEFS.map(c => Object.assign({}, c));
@track groupingIndexes = [];

_rawRows = [];
_groupedRows = [];
@track tableRows = [];
@track totalCount = 0;

@track _selectedRowMap = {};

selectedTimesheetIds = [];
selectedLineItemIds = [];

_processedRowIds = new Set();

@track _columnFilterSelections = {};
@track _activeSortColId = 'employeeName';
@track isTimesheetFilterOpen = false;
@track timesheetFilterSelections = null;
@track timesheetSortDirection = 'asc';
@track allTimesheetNames = [];
@track allFilterValues = {};

_dragColId = null;
_dragTarget = null;

// Initializes the screen.
connectedCallback() {
    this.fetchData();
}

// Checks for a custom date range.
get isCustomDate() {
return this.dateRange === 'Custom';
}

// Checks whether no rows are selected.
get isNoSelection() {
if (!Array.isArray(this.tableRows)) {
    return true;
}

return !this.tableRows.some(
    row =>
        !row.hidden &&
        !row.actioned &&
        row.selected === true
);
}

get isTimesheetApprovalMode() {
return this._rawRows.length > 0 &&
this._rawRows.every(row => row.isPartialAllowed === false);
}
get timesheetSortIcon() {
return this.timesheetSortDirection === 'desc' ? '↓' : '↑';
}

get timesheetSortTitle() {
return this.timesheetSortDirection === 'desc'
    ? 'Sort Descending — click for Ascending'
    : 'Sort Ascending — click for Descending';
}

get timesheetFilterBtnClass() {
return 'tli-col-filter-btn' +
    (this.timesheetFilterSelections != null
        ? ' tli-filter-active'
        : '');
}

get timesheetFilterOptions() {
const values = new Set();

this.allTimesheetNames.forEach(name => {
    const value =
        name != null &&
        String(name).trim() !== ''
            ? String(name).trim()
            : '(Blank)';

    values.add(value);
});

const selected = this.timesheetFilterSelections;

return Array.from(values)
    .sort((a, b) => a.localeCompare(b))
    .map(value => ({
        label: value,
        value: value,
        checked:
            selected == null ||
            selected.has(value)
    }));
}
get isGroupingSelectionMode() {
return this.groupingIndexes.length > 0;

}
// Checks whether the standard selection column is visible.
get showSelectionColumn() {
return !this.groupingIndexes || this.groupingIndexes.length === 0;
}
// Checks whether all visible rows are disabled.
get isAllCheckboxesDisabled() {
if (!this.tableRows || this.tableRows.length === 0) {
return false;
}

const visibleRows = this.tableRows.filter(
row => !row.hidden
);

if (visibleRows.length === 0) {
return false;
}

return visibleRows.every(
row => row.actioned === true
);
}

// Checks whether the table is empty.
get isTableEmpty() {
return !this.tableRows || this.tableRows.length === 0;
}

// Checks whether the row limit is exceeded.
get isCountExceeded() {
return this.totalCount > MAIN_MAX;
}

// Returns the row limit.
get maxLimit() {
return MAIN_MAX;
}

// Returns date range options.
get dateRangeOptions() {
return [
{ label: 'Current Week', value: 'Current Week' },
{ label: 'Last Week', value: 'Last Week' },
{ label: 'Current Month', value: 'Current Month' },
{ label: 'Last Month', value: 'Last Month' },
{ label: 'All Pending', value: 'All Pending' },
{ label: 'Custom', value: 'Custom' }
];
}

// Returns status filter options.
get statusOptions() {
return [
{ label: 'All Statuses', value: 'All' },
{ label: 'Submitted', value: 'Submitted' },
{ label: 'Partial', value: 'Partial' }
];
}

// Returns project filter options.
get projectOptions() {
const projects = new Set();

this._rawRows.forEach(r => {
if (r.projectName) {
    projects.add(r.projectName);
}

});

const opts = [{ label: 'All Projects', value: 'All' }];

Array.from(projects).sort().forEach(p => {
opts.push({ label: p, value: p });
});

return opts;
}

// Returns ordered columns.
get orderedColumns() {
let ordered = [...this.columns]
.sort((a, b) => a.order - b.order);

return ordered.map((col, index) => {
const isAsc = col.sortDirection !== 'desc';
const isSortActive = this._activeSortColId === col.id;
const selectedSet = this._columnFilterSelections[col.id];
const isFiltered = selectedSet != null;
const distinctValues = new Set();

const allValues = this.allFilterValues[col.id] || [];
allValues.forEach(value => {
    const val =
        value != null && String(value).trim() !== ''
            ? String(value).trim()
            : '(Blank)';

    distinctValues.add(val);
});

const filterOptions = Array.from(distinctValues)
.sort()
.map(val => {
const isChecked = selectedSet == null ? true : selectedSet.has(val);

return {
    label: val,
    value: val,
    checked: isChecked
};

});

return Object.assign({}, col, {
sortIcon: isAsc ? '↑' : '↓',

sortTitle: isAsc
? 'Sort Ascending — click for Descending'
: 'Sort Descending — click for Ascending',

sortBtnClass:
'tli-col-action-btn' +
(isSortActive ? ' tli-sort-active' : ''),

filterBtnClass:
'tli-col-filter-btn' +
(isFiltered ? ' tli-filter-active' : ''),

filterOptions,
columnIndex: index,
showGroupByButton:
index < 5 &&
(
this.groupingIndexes.includes(index) ||
index === this.groupingIndexes.length
),

groupByIcon:
this.groupingIndexes.includes(index)
? '☰'
: '|||',

groupByBtnClass: 'tli-col-type-btn',
groupByTitle: this.groupingIndexes.includes(index)
? 'Grouped'
: 'Group by this column'

});
});
}

// Returns the table column span.
get colSpan() {
return this.orderedColumns.length + 2;
}

// Checks whether all selectable rows are selected.
get isAllSelected() {
const selectableRows = this.tableRows.filter(row => !row.hidden && !row.actioned);

return selectableRows.length > 0 &&
selectableRows.every(row => !!this._selectedRowMap[row.id]);

}

// Loads timesheet data.
fetchData() {
this.isTableLoading = true;

getTimesheetData({
dateRange: this.dateRange,
customStartDate: this.customStartDate,
customEndDate: this.customEndDate,
groupingIndexes: this.groupingIndexes,
columnOrder: this.orderedColumns.map(col => col.id)
})

.then(result => {
// Get all Timesheet names for the Timesheet filter
this.allTimesheetNames = Array.isArray(result.timesheetNames)
    ? result.timesheetNames
    : [];

this.allFilterValues = result.filterValues || {};

// Parses Apex results.
this._rawRows = this._parseApexResult(result.rows);

this._groupedRows = [];

this._recompute();
})
.catch(error => {
this.showToast(
'Error',
error.body ? error.body.message : error.message,
'error'
);
})
.finally(() => {
this.isTableLoading = false;
});
}

// Parses Apex results.
_parseApexResult(rawList) {
if (!rawList) {
return [];
}

const rows = [];

rawList.forEach((wrapper, wIdx) => {
const empName = wrapper.employeeName || 'Unknown Employee';
const tsStatus = wrapper.timesheetStatus || 'Submitted';
const fallbackDate = wrapper.startDate ? String(wrapper.startDate) : '';
const tsId = wrapper.timesheetId || wrapper.id;
const tsName = wrapper.timesheetName || '';
const isPartialAllowed = wrapper.isPartialAllowed === true;

// Partial Allowed = TRUE: approval is at line-item level.
if (isPartialAllowed && wrapper.lineItems && wrapper.lineItems.length > 0) {
    wrapper.lineItems.forEach((li, lIdx) => {
        const typeVal = li.dbt__Type__c;
        const isAbsence = typeVal === 'Absence';
        const absenceCat = li.dbt__Absence_Category__c || 'Absence';
        const projObj = li.dbt__Project__r;
        const projId = li.dbt__Project__c;

        const pName = isAbsence
            ? absenceCat
            : (projObj ? projObj.Name : (projId || wrapper.projectName || 'N/A'));

        const aName = isAbsence
            ? '-'
            : (li.dbt__Activity__c || li.dbt__Description__c || typeVal || '-');

        const durVal = li.dbt__Duration__c;
        const dur = durVal !== undefined && durVal !== null ? parseFloat(durVal) : 0;
        const lineItemStatus = li.dbt__Line_Item_Status__c || '';
        const lineDate = li.dbt__Date__c || fallbackDate;

        rows.push({
            id: li.Id || (tsId + '_li_' + lIdx),
            lineItemId: li.Id || null,
            timesheetId: tsId,
            timesheetName: tsName,
            timesheetStatus: tsStatus,
            isPartialAllowed: true,
            employeeId: wrapper.employeeId || null,
            employeeName: empName,
            date: lineDate,
            projectId: projId || null,
            projectName: pName,
            activityName: aName,
            duration: dur,
            status: lineItemStatus,
            lineItemStatus: lineItemStatus,
            statusClass: this._statusClass(lineItemStatus),
            employeeLineItemCount: wrapper.employeeLineItemCount,
            employeeTotalDuration: wrapper.employeeTotalDuration,
            projectLineItemCount: wrapper.projectLineItemCount,
            projectTotalDuration: wrapper.projectTotalDuration,
            employeeProjectLineItemCount: wrapper.employeeProjectLineItemCount,
            employeeProjectTotalDuration: wrapper.employeeProjectTotalDuration
        });
    });
    return;
}

// Partial Allowed = FALSE: approval is at Timesheet level.
// One selectable row represents the complete Timesheet.
rows.push({
      id: tsId || wrapper.id || ('ts_' + wIdx),
    lineItemId: null,
    timesheetId: tsId,
    timesheetName: tsName,
    timesheetStatus: tsStatus,
    isPartialAllowed: false,
    employeeName: empName,

    date: wrapper.startDate && wrapper.endDate
        ? `${wrapper.startDate} → ${wrapper.endDate}`
        : fallbackDate,

    projectName: wrapper.projectName || '-',

    activityName: wrapper.activityName || '-',

    duration: wrapper.duration || 0,
    status: tsStatus,
    lineItemStatus: null,
    statusClass: this._statusClass(tsStatus),

    employeeLineItemCount: wrapper.employeeLineItemCount,
    employeeTotalDuration: wrapper.employeeTotalDuration,
    projectLineItemCount: wrapper.projectLineItemCount,
    projectTotalDuration: wrapper.projectTotalDuration,
    employeeProjectLineItemCount: wrapper.employeeProjectLineItemCount,
    employeeProjectTotalDuration: wrapper.employeeProjectTotalDuration
});
});

return rows;

}

// Checks whether a line item is processed.
_isLineItemProcessed(record) {
if (!record) {
return false;
}

// Non-partial records are processed when the parent Timesheet is approved.
if (record.isPartialAllowed === false) {
return record.status === 'Approved' ||
    (record.id && this._processedRowIds.has(record.id));
}

// Partial records are processed from the line-item status.
if (
record.lineItemStatus === 'Partial Approved' ||
record.lineItemStatus === 'Approved'
) {
return true;
}

return record.id &&
this._processedRowIds &&
this._processedRowIds.has(record.id);

}

// Recomputes table rows.
_recompute() {
let filtered = [...this._rawRows];
// Find timesheets where ALL line items are processed/disabled
const timesheetGroups = new Map();

this._rawRows.forEach(row => {
if (!row.timesheetId || !row.lineItemId) {
    return;
}

if (!timesheetGroups.has(row.timesheetId)) {
timesheetGroups.set(row.timesheetId, []);
}

timesheetGroups.get(row.timesheetId).push(row);
});

const fullyProcessedTimesheets = new Set();

timesheetGroups.forEach((lineItems, timesheetId) => {
const allProcessed =
lineItems.length > 0 &&
lineItems.every(lineItem =>
// Checks whether a line item is processed.
this._isLineItemProcessed(lineItem)
);

if (allProcessed) {
fullyProcessedTimesheets.add(timesheetId);
}

});

// Remove the ENTIRE timesheet only when all its line items are processed
filtered = filtered.filter(
row => !fullyProcessedTimesheets.has(row.timesheetId)
);

if (this.statusFilter && this.statusFilter !== 'All') {
filtered = filtered.filter(r => r.status === this.statusFilter);
}

if (this.employeeSearch && this.employeeSearch.trim()) {
const q = this.employeeSearch.trim().toLowerCase();

filtered = filtered.filter(r =>
r.employeeName &&
r.employeeName.toLowerCase().includes(q)
);

}

if (this.projectFilter && this.projectFilter !== 'All') {
filtered = filtered.filter(r => r.projectName === this.projectFilter);
}

for (const col of this.columns) {
const selectedSet = this._columnFilterSelections[col.id];

if (selectedSet != null) {
filtered = filtered.filter(r => {
    const val = r[col.fieldName] != null && String(r[col.fieldName]).trim() !== ''
    ? String(r[col.fieldName])
    : '(Blank)';

    return selectedSet.has(val);
});

}
}

if (
this.isTimesheetApprovalMode &&
this.timesheetFilterSelections != null
) {
filtered = filtered.filter(row => {
    const value =
        row.timesheetName != null &&
        String(row.timesheetName).trim() !== ''
            ? String(row.timesheetName)
            : '(Blank)';

    return this.timesheetFilterSelections.has(value);
});
}


this.totalCount = filtered.length;

const capped = filtered.slice(0, MAIN_MAX);
const cols = this.orderedColumns;
const colCache = new Array(cols.length);

for (let ci = 0; ci < cols.length; ci++) {
const col = cols[ci];

if (col.isExpanded) {
colCache[ci] = null;
} else {
const contextColIds = [];

for (let j = 0; j < ci; j++) {
if (cols[j] && cols[j].isExpanded) {
    contextColIds.push(cols[j].id);
}

}

const contextMap = new Map();

for (const r of capped) {
const ctxKey = this._getRowContextKey(r, contextColIds, cols);

if (!contextMap.has(ctxKey)) {
contextMap.set(ctxKey, []);
}

contextMap.get(ctxKey).push(r);
}

const valueMap = new Map();

for (const [ctxKey, groupRecs] of contextMap.entries()) {
if (col.isDuration) {
const totalDur = groupRecs.reduce(
(s, rec) => s + (parseFloat(rec[col.fieldName]) || 0),
0
);

valueMap.set(ctxKey, totalDur);
} else {
const distinctSet = new Set(
groupRecs
.map(rec => rec[col.fieldName])
.filter(v => v != null && String(v).trim() !== '')
.map(String)
);

valueMap.set(ctxKey, distinctSet.size);

}
}

colCache[ci] = {
contextColIds,
valueMap
};
}
}

const getSortVal = (r, ci) => {
const col = cols[ci];
const cache = colCache[ci];

if (!cache) {
const rawVal = r[col.fieldName];

if (col.isDuration) {
    return parseFloat(rawVal) || 0;
}

return rawVal != null ? String(rawVal).toLowerCase() : '';

}

const ctxKey = this._getRowContextKey(r, cache.contextColIds, cols);

return cache.valueMap.get(ctxKey) || 0;
};

const activeCol = cols.find(c => c.id === this._activeSortColId) || cols[0];
const activeIdx = cols.indexOf(activeCol);
const activeGroupingLevels = Math.min(this.groupingIndexes.length, 5);
const isTimesheetSort =
this.isTimesheetApprovalMode &&
this._activeSortColId === 'timesheet';

capped.sort((a, b) => {
// Keep every active grouping level contiguous. The user's normal sort
// still applies after the grouping prefix has been compared.
if (isTimesheetSort) {
    const va =
        a.timesheetName != null
            ? String(a.timesheetName).toLowerCase()
            : '';

    const vb =
        b.timesheetName != null
            ? String(b.timesheetName).toLowerCase()
            : '';

    if (va < vb) {
        return this.timesheetSortDirection === 'desc'
            ? 1
            : -1;
    }

    if (va > vb) {
        return this.timesheetSortDirection === 'desc'
            ? -1
            : 1;
    }

    return 0;
}
for (let gi = 0; gi < activeGroupingLevels; gi++) {
const groupingCol = cols[gi];
const ga = getSortVal(a, gi);
const gb = getSortVal(b, gi);

if (ga < gb) {
    return groupingCol.sortDirection === 'desc' ? 1 : -1;
}

if (ga > gb) {
    return groupingCol.sortDirection === 'desc' ? -1 : 1;
}
}

if (activeIdx >= 0) {
const va = getSortVal(a, activeIdx);
const vb = getSortVal(b, activeIdx);

if (va < vb) {
    return activeCol.sortDirection === 'desc' ? 1 : -1;
}

if (va > vb) {
return activeCol.sortDirection === 'desc' ? -1 : 1;
}

}

for (let ci = 0; ci < cols.length; ci++) {
if (ci === activeIdx || ci < activeGroupingLevels) {
continue;
}

const col = cols[ci];
const va = getSortVal(a, ci);
const vb = getSortVal(b, ci);

if (va < vb) {
return col.sortDirection === 'desc' ? 1 : -1;
}

if (va > vb) {
return col.sortDirection === 'desc' ? -1 : 1;
}
}

return 0;
});

// Builds display rows.
this.tableRows = this._buildDisplayRows(capped, cols);
}

// Returns the grouping token.
_getGroupingToken(row, col) {
if (!row || !col) {
return '(Blank)';
}

let value = row[col.fieldName];

if (col.id === 'employeeName') {
value = row.employeeId || row.employeeName;
} else if (col.id === 'projectName') {
value = row.projectId || row.projectName;
}
else if (col.id === 'date') {
value = row.date;

if (value) {
value = String(value).substring(0, 10);
}

}

if (value === null || value === undefined || String(value).trim() === '') {
return '(Blank)';
}

if (col.isDuration) {
const numberValue = Number(value);
return Number.isFinite(numberValue)
    ? numberValue.toFixed(6)
    : '(Blank)';
}

return String(value);

}

// Returns a grouping key for the selected grouping level.

// Returns the grouping key.
_getGroupingKey(row, cols, level) {
const parts = [];

for (let i = 0; i <= level; i++) {
const columnIndex =
    this.groupingIndexes[i];

const column =
    cols[columnIndex];

const token =
    this._getGroupingToken(
        row,
        column
    );

parts.push(
    '|L' +
    i +
    ':' +
    String(token ?? '')
);
}

return parts.join('');

}

// Formats a duration value.
_formatDurationValue(value) {
const numberValue = Number(value) || 0;

if (Number.isInteger(numberValue)) {
return String(numberValue);
}

return numberValue
.toFixed(2)
.replace(/0+$/, '')
.replace(/\.$/, '');

}

// Builds grouping summaries.
_buildClientGroupingSummaries(data, cols, activeLevels) {
const summaries = new Map();

for (let level = 0; level < activeLevels; level++) {
data.forEach(row => {
    const groupKey =
        this._getGroupingKey(
            row,
            cols,
            level
        );

    if (!summaries.has(groupKey)) {
        summaries.set(groupKey, {
            count: 0,
            totalDuration: 0,
            projectIds: new Set(),
            activityValues: new Set(),
            statuses: new Set(),
            minDate: null,
            maxDate: null
        });
    }

    const summary = summaries.get(groupKey);

    summary.count += 1;
    summary.totalDuration +=
        parseFloat(row.duration) || 0;

    if (row.projectId || row.projectName) {
        summary.projectIds.add(
            row.projectId || row.projectName
        );
    }

    if (
        row.activityName &&
        row.activityName !== '-'
    ) {
        summary.activityValues.add(
            String(row.activityName)
        );
    }

    if (row.status) {
        summary.statuses.add(
            String(row.status)
        );
    }

    const date =
        row.date
            ? String(row.date).substring(0, 10)
            : null;

    if (date) {
        if (
            !summary.minDate ||
            date < summary.minDate
        ) {
            summary.minDate = date;
        }

        if (
            !summary.maxDate ||
            date > summary.maxDate
        ) {
            summary.maxDate = date;
        }
    }
});
}

for (const [groupKey, summary] of summaries.entries()) {
summaries.set(groupKey, {
    count: summary.count,
    totalDuration: summary.totalDuration,
    projectCount: summary.projectIds.size,
    minDate: summary.minDate,
    maxDate: summary.maxDate,
    activityCount: summary.activityValues.size,
    statuses: Array.from(summary.statuses)
});
}

return summaries;

}

// Builds group checkbox state.
_getGroupCheckboxState(data, cols, colIndex, groupKey, groupState) {

    if (!groupState.showCell) {
        return {
            showGroupCheckbox: false,
            groupSelectionKey: '',
            groupSelectionLevel: colIndex,
            groupCheckboxChecked: false,
            groupCheckboxIndeterminate: false,
            groupCheckboxDisabled: true,
            groupSelectedCount: 0,
            groupTotalCount: 0
        };
    }

    const groupRecords = data.filter(record =>
        this._getGroupingKey(record, cols, colIndex) === groupKey
    );

    const selectableRecords = groupRecords.filter(
        record => !this._isLineItemProcessed(record)
    );

    const selectedRecords = selectableRecords.filter(
        record => !!this._selectedRowMap[record.id]
    );

    const totalCount = selectableRecords.length;
    const selectedCount = selectedRecords.length;

    return {
        showGroupCheckbox: true,
        groupSelectionKey: groupKey,
        groupSelectionLevel: colIndex,

        // All selected
        groupCheckboxChecked:
            totalCount > 0 &&
            selectedCount === totalCount,

        // Some selected, but not all
        groupCheckboxIndeterminate:
            selectedCount > 0 &&
            selectedCount < totalCount,

        groupCheckboxDisabled:
            totalCount === 0,

        groupSelectedCount: selectedCount,
        groupTotalCount: totalCount
    };
}

// Builds display rows. Apex supplies aggregate GROUP BY summaries;

// Builds display rows.
_buildDisplayRows(data, cols) {
if (!data || !data.length) {
return [];
}

const activeLevels = Math.min(
this.groupingIndexes
    ? this.groupingIndexes.length
    : 0,
6,
cols.length
);

const hasDurationGrouping =
this.groupingIndexes.some(
groupIndex =>
cols[groupIndex] &&
cols[groupIndex].id === 'duration'
);

const summaries =
activeLevels > 0
? this._buildClientGroupingSummaries(
data,
cols,
activeLevels
)
: new Map();

if (!hasDurationGrouping) {
(this._groupedRows || []).forEach(groupedRow => {

    if (!groupedRow || !groupedRow.groupKey) {
        return;
    }

    summaries.set(groupedRow.groupKey, {
        count: Number(groupedRow.rowCount) || 0,
        totalDuration:
            Number(groupedRow.totalDuration) || 0,

        projectCount:
            Number(groupedRow.projectCount) || 0,

        minDate:
            groupedRow.minDate || null,

        maxDate:
            groupedRow.maxDate || null,

        activityCount:
            Number(groupedRow.activityCount) || 0,

        statuses:
            Array.isArray(groupedRow.statuses)
                ? groupedRow.statuses
                : []
    });
});
}

/*
* Returns how many consecutive rows belong to
* the supplied grouping level.
*/
const getGroupRowspan = (
index,
level
) => {

const currentKey =
    this._getGroupingKey(
        data[index],
        cols,
        level
    );

if (index > 0) {

    const previousKey =
        this._getGroupingKey(
            data[index - 1],
            cols,
            level
        );

    if (previousKey === currentKey) {
        return {
            rowspan: 0,
            showCell: false
        };
    }
}

let count = 1;

for (
    let next = index + 1;
    next < data.length;
    next++
) {

    const nextKey =
        this._getGroupingKey(
            data[next],
            cols,
            level
        );

    if (nextKey !== currentKey) {
        break;
    }

    count++;
}

return {
    rowspan: count,
    showCell: true
};
};

return data.map((raw, index) => {

const row = {
    id:
        raw.id ||
        ('row_' + index),

    timesheetId:
        raw.timesheetId,

    timesheetName: raw.timesheetName,

    lineItemId:
        raw.lineItemId || null,

    isPartialAllowed:
        raw.isPartialAllowed === true,

    rowNum:
        index + 1,

    records: [raw],

    cells: [],

    hidden: false,

    selected:
        !!this._selectedRowMap[raw.id],

    actioned:
        this._isLineItemProcessed(raw)
};

cols.forEach((col, colIndex) => {

    /*
        * No grouping:
        * every column behaves normally.
        */
    if (activeLevels === 0) {

        row.cells.push({
            id:
                col.id +
                '_' +
                row.id,

            colId:
                col.id,

            value:
                raw[col.fieldName] != null
                    ? String(raw[col.fieldName])
                    : '',

            summaryValue: '',

            rowspan: 1,

            showCell: true,

            isGrouped: false,

            isStatus:
                col.id === 'status',

            statusClass:
                col.id === 'status'
                    ? raw.statusClass
                    : '',

            statusItems:
                col.id === 'status'
                    ? [{
                        label: raw.status || '',
                        className:
                            raw.statusClass ||
                            this._statusClass(
                                raw.status || ''
                            )
                    }]
                    : [],

            isDuration:
                col.isDuration
        });

        return;
    }

    /*
        * ---------------------------------------------------------
        * GROUPED COLUMN
        * ---------------------------------------------------------
        *
        * Only the first N columns are grouped.
        *
        * Example:
        *
        * 1 grouping:
        * Employee
        *
        * 2 grouping:
        * Employee -> Project
        *
        * 3 grouping:
        * Employee -> Project -> Date
        */
    if (colIndex < activeLevels) {

const level = this.groupingIndexes[colIndex];

const groupKey =
this._getGroupingKey(
    raw,
    cols,
    colIndex
);

let summary = summaries.get(groupKey);

if (!summary) {
const groupedRow = (this._groupedRows || []).find(
item =>
item &&
item.groupKey === groupKey
);

if (groupedRow) {
summary = {
    count: Number(groupedRow.rowCount) || 0,
    totalDuration:
        Number(groupedRow.totalDuration) || 0,
    projectCount:
        Number(groupedRow.projectCount) || 0,
    minDate:
        groupedRow.minDate || null,
    maxDate:
        groupedRow.maxDate || null,
    activityCount:
        Number(groupedRow.activityCount) || 0,
    statuses:
        Array.isArray(groupedRow.statuses)
            ? groupedRow.statuses
            : []
};
}

}

        const groupState =
            getGroupRowspan(
                index,
                level
            );

        const groupCheckboxState =
            this._getGroupCheckboxState(
                data,
                cols,
                colIndex,
                groupKey,
                groupState
            );

        let value =
raw[col.fieldName] != null
? String(raw[col.fieldName])
: '';

if (
!value &&
col.id === 'employeeName'
) {
value =
raw.employeeName ||
raw.employeeId ||
'';
}

if (col.isDuration) {
value = this._formatDurationValue(raw.duration);
}

if (groupState.showCell) {

value +=
' (' +
groupState.rowspan +
')';

}

        /*
            * Grouped cells show their own
            * group's total duration underneath.
            */
        let summaryValue = '';

        if (summary) {

            summaryValue =
                this._formatDurationValue(
                    summary.totalDuration
                )
                ;
        }

        row.cells.push({
            id:
                col.id +
                '_' +
                row.id,

            colId:
                col.id,

            value,

            summaryValue,

            rowspan:
                groupState.rowspan,

            showCell:
                groupState.showCell,

            isGrouped: true,
            ...groupCheckboxState,

            isStatus:
                col.id === 'status',

            statusClass:
                col.id === 'status'
                    ? raw.statusClass
                    : '',

            statusItems: [],

            isDuration:
                col.isDuration
        });

        return;
    }

    /*
        * ---------------------------------------------------------
        * COLUMNS TO THE RIGHT OF GROUPING
        * ---------------------------------------------------------
        *
        * Column 1 grouping is special:
        *
        * Employee grouped
        * -> all remaining columns show Employee summary.
        *
        * From Column 2 onward:
        *
        * Employee + Project grouped
        * -> Date onward shows individual records.
        *
        * Employee + Project + Date grouped
        * -> Activity onward shows individual records.
        */
    /*



COLUMNS TO THE RIGHT OF GROUPING





When Column 1 is grouped:



Column 1 shows grouped value + count.



Every remaining column shows a summary

for that Column 1 group.



When multiple columns are grouped:



Each grouped column shows its grouped value + count.



Remaining columns show summaries for the

complete grouping hierarchy.
*/
const currentGroupLevel =
activeLevels > 0
? activeLevels - 1
: -1;

const currentGroupKey =
currentGroupLevel >= 0
? this._getGroupingKey(
raw,
cols,
currentGroupLevel
)
: '';

const currentGroupSummary =
currentGroupKey
? summaries.get(currentGroupKey)
: null;

const currentGroupState =
currentGroupLevel >= 0
? getGroupRowspan(
index,
currentGroupLevel
)
: {
rowspan: 1,
showCell: true
};

/*



SUMMARY FOR COLUMNS AFTER GROUPING



*/
if (activeLevels == 1) {
let summaryValue = '';

/*
* Employee summary.
*
* Shows Employee Name (count) within
* the current parent grouping.
*/
if (col.id === 'employeeName') {
const employeeToken =
    this._getGroupingToken(
        raw,
        col
    );

let employeeCount = 0;

for (const record of data) {
    const recordGroupKey =
        this._getGroupingKey(
            record,
            cols,
            currentGroupLevel
        );

    if (
        recordGroupKey !==
        currentGroupKey
    ) {
        continue;
    }

    const recordEmployeeToken =
        this._getGroupingToken(
            record,
            col
        );

    if (
        recordEmployeeToken ===
        employeeToken
    ) {
        employeeCount++;
    }
}

summaryValue =
    (raw.employeeName ||
        raw.employeeId ||
        '') +
    ' (' +
    employeeCount +
    ')';
}

/*
* Project summary.
*/
else if (
col.id === 'projectName' &&
currentGroupSummary
) {
summaryValue =
    currentGroupSummary.projectCount +
    ' Projects';
}

/*
* Date summary.
*/
else if (
col.id === 'date' &&
currentGroupSummary
) {
if (
    currentGroupSummary.minDate &&
    currentGroupSummary.maxDate
) {
    summaryValue =
        currentGroupSummary.minDate +
        ' → ' +
        currentGroupSummary.maxDate;
} else if (
    currentGroupSummary.minDate
) {
    summaryValue =
        currentGroupSummary.minDate;
}
}

/*
* Activity summary.
*/
else if (
col.id === 'activityName' &&
currentGroupSummary
) {
summaryValue =
    currentGroupSummary.activityCount +
    ' Activities';
}

/*
* Duration summary.
*/
else if (
col.id === 'duration' &&
currentGroupSummary
) {
summaryValue =
    this._formatDurationValue(
        currentGroupSummary.totalDuration
    ) +
    ' Hours';
}

/*
* Status summary.
*/
else if (
col.id === 'status' &&
currentGroupSummary
) {
const statuses =
    Array.isArray(
        currentGroupSummary.statuses
    )
        ? currentGroupSummary.statuses
        : [];

const statusItems =
    statuses.map(status => ({
        label: status,
        className:
            this._statusClass(
                status
            )
    }));

row.cells.push({
    id:
        col.id +
        '_' +
        row.id,

    colId:
        col.id,

    value: '',

    summaryValue: '',

    rowspan:
        currentGroupState.rowspan,

    showCell:
        currentGroupState.showCell,

    isGrouped: false,

    isStatus: true,

    statusClass:
        raw.statusClass || '',

    statusItems,

    isDuration:
        col.isDuration
});

return;
}

row.cells.push({
id:
    col.id +
    '_' +
    row.id,

colId:
    col.id,

value: summaryValue,

summaryValue: '',

rowspan:
    currentGroupState.rowspan,

showCell:
    currentGroupState.showCell,

isGrouped: false,

isStatus: false,

statusClass: '',

statusItems: null,

isDuration:
    col.isDuration
});

return;

}
/*
* ---------------------------------------------------------
* DETAIL COLUMN AFTER 2+ GROUPING LEVELS
* ---------------------------------------------------------
*
* These columns must NOT be merged.
*
* They remain individual line-item rows.
*/
let value =
raw[col.fieldName] != null
? String(raw[col.fieldName])
: '';

    /*
        * Duration keeps the existing value.
        */
    if (
        col.id === 'duration' &&
        raw.duration != null
    ) {

        value =
            this._formatDurationValue(
                raw.duration
            );
    }

    /*
        * Status remains an individual status pill.
        */
    const statusItems =
        col.id === 'status'
            ? [{
                label: raw.status || '',
                className:
                    raw.statusClass ||
                    this._statusClass(
                        raw.status || ''
                    )
            }]
            : [];

    row.cells.push({
        id:
            col.id +
            '_' +
            row.id,

        colId:
            col.id,

        value,

        summaryValue: '',

        rowspan: 1,

        showCell: true,

        isGrouped: false,

        isStatus:
            col.id === 'status',

        statusClass:
            col.id === 'status'
                ? raw.statusClass
                : '',

        statusItems,

        isDuration:
            col.isDuration
    });
});

return row;
});

}

// Handles column sorting.
handleSort(event) {
event.stopPropagation();

const colId = event.currentTarget.dataset.colId;

if (!colId) {
return;
}
if (colId === 'timesheet') {
this._activeSortColId = 'timesheet';

this.timesheetSortDirection =
    this.timesheetSortDirection === 'asc'
        ? 'desc'
        : 'asc';

this._recompute();
return;
}

this._activeSortColId = colId;

this.columns = this.columns.map(col => {
if (col.id === colId) {
return {
...col,
sortDirection:
col.sortDirection === 'asc'
? 'desc'
: 'asc'
};
}

return col;
});

// Recomputes table rows.
this._recompute();
}
// Handles column grouping.
// Clicking the next available column adds one level. Clicking an active
// grouped column removes that level and every child level, returning to the

// Handles column grouping.
handleHeaderGroupBy(event) {
event.stopPropagation();

const columnIndex = Number(
event.currentTarget.dataset.columnIndex
);


if (
Number.isNaN(columnIndex) ||
columnIndex < 0 ||
columnIndex > 5
) {
return;
}

const currentLength = this.groupingIndexes.length;

// Only the next column can be newly grouped.
if (columnIndex === currentLength) {
this.groupingIndexes = [
    ...this.groupingIndexes,
    columnIndex
];
// Clicking any currently grouped column expands it and removes
// all grouping levels to its right.
} else if (columnIndex < currentLength) {
this.groupingIndexes = Array.from(
    { length: columnIndex },
    (_, index) => index
);
} else {
// Future columns are disabled until the previous level is grouped.
return;
}

this.fetchData();

}

// Toggles a column filter.
handleColFilterToggle(event) {
event.stopPropagation();

const colId = event.currentTarget.dataset.colId;

this.columns = this.columns.map(col =>
col.id === colId
? Object.assign({}, col, {
isFilterOpen: !col.isFilterOpen
})

: col
);
}

// Closes a column filter.
handleColFilterClose(event) {
event.stopPropagation();

const colId = event.currentTarget.dataset.colId;

this.columns = this.columns.map(col =>
col.id === colId
? Object.assign({}, col, { isFilterOpen: false })
: col
);

}

// Handles dropdown clicks.
handleDropdownClick(event) {
event.stopPropagation();
}

// Selects all filter values.
handleFilterSelectAll(event) {
event.stopPropagation();

const colId = event.currentTarget.dataset.colId;
const nextMap = Object.assign({}, this._columnFilterSelections);

nextMap[colId] = null;
this._columnFilterSelections = nextMap;

// Recomputes table rows.
this._recompute();

}

// Clears all filter values.
handleFilterClearAll(event) {
event.stopPropagation();

const colId = event.currentTarget.dataset.colId;
const nextMap = Object.assign({}, this._columnFilterSelections);

nextMap[colId] = new Set();
this._columnFilterSelections = nextMap;

// Recomputes table rows.
this._recompute();

}

// Updates filter values.
handleFilterOptionChange(event) {
event.stopPropagation();

const colId = event.currentTarget.dataset.colId;
const val = event.target.value;
const checked = event.target.checked;

const targetCol = this.columns.find(c => c.id === colId);

if (!targetCol) {
return;
}

let currentSet = this._columnFilterSelections[colId];

if (currentSet == null) {
currentSet = new Set();

const allValues = this.allFilterValues[colId] || [];
allValues.forEach(value => {
const v =
    value != null &&
    String(value).trim() !== ''
        ? String(value).trim()
        : '(Blank)';
currentSet.add(v);
});

} else {
currentSet = new Set(currentSet);
}

if (checked) {
currentSet.add(val);
} else {
currentSet.delete(val);
}

const allDistinct = new Set();

const allValuesForDistinct = this.allFilterValues[colId] || [];
allValuesForDistinct.forEach(value => {
const v =
    value != null &&
    String(value).trim() !== ''
        ? String(value).trim()
        : '(Blank)';
allDistinct.add(v);
});

const nextMap = Object.assign({}, this._columnFilterSelections);

nextMap[colId] =
currentSet.size === allDistinct.size
? null
: currentSet;

this._columnFilterSelections = nextMap;

// Recomputes table rows.
this._recompute();
}
handleTimesheetFilterToggle(event) {
event.stopPropagation();

this.isTimesheetFilterOpen =
    !this.isTimesheetFilterOpen;
}

handleTimesheetFilterClose(event) {
event.stopPropagation();

this.isTimesheetFilterOpen = false;
}

handleTimesheetFilterSelectAll(event) {
event.stopPropagation();

this.timesheetFilterSelections = null;
this.isTimesheetFilterOpen = true;

this._recompute();
}

handleTimesheetFilterClearAll(event) {
event.stopPropagation();

this.timesheetFilterSelections = new Set();
this.isTimesheetFilterOpen = true;

this._recompute();
}

handleTimesheetFilterOptionChange(event) {
event.stopPropagation();

const value = event.target.value;
const checked = event.target.checked;

let currentSet = this.timesheetFilterSelections;

if (currentSet == null) {
    currentSet = new Set(
        this.timesheetFilterOptions.map(
            option => option.value
        )
    );
} else {
    currentSet = new Set(currentSet);
}

if (checked) {
    currentSet.add(value);
} else {
    currentSet.delete(value);
}

const allValues = new Set(
    this.timesheetFilterOptions.map(
        option => option.value
    )
);

this.timesheetFilterSelections =
    currentSet.size === allValues.size
        ? null
        : currentSet;

this._recompute();
}

handleTimesheetSort(event) {
event.stopPropagation();

this._activeSortColId = 'timesheet';

this.timesheetSortDirection =
    this.timesheetSortDirection === 'asc'
        ? 'desc'
        : 'asc';

this._recompute();
}

// Starts column dragging.
handleColDragStart(event) {
const colId = event.currentTarget.dataset.colId;

this._dragColId = colId;
this._dragTarget = null;

if (event.dataTransfer) {
event.dataTransfer.effectAllowed = 'move';
event.dataTransfer.setData('text/plain', colId);
}

const sourceTh = event.currentTarget.closest('th');

if (sourceTh) {
sourceTh.classList.add('tli-column-dragging');
}
}

// Handles column drag-over.
handleColDragOver(event) {
event.preventDefault();
event.stopPropagation();

const targetId = event.currentTarget.dataset.colId;

if (
!this._dragColId ||
!targetId ||
targetId === this._dragColId
) {
return;
}

if (event.dataTransfer) {
event.dataTransfer.dropEffect = 'move';
}

this._dragTarget = targetId;

this.template
.querySelectorAll('.tli-column-drag-over')
.forEach(el => {
el.classList.remove('tli-column-drag-over');
});

event.currentTarget.classList.add(
'tli-column-drag-over'
);
}

// Handles column drag-leave.
handleColDragLeave(event) {
const th = event.currentTarget;

if (!th.contains(event.relatedTarget)) {
th.classList.remove(
'tli-column-drag-over'
);

if (
this._dragTarget ===
th.dataset.colId
) {
    this._dragTarget = null;
}

}
}

// Reorders a column.

// Swaps the positions of two columns.
handleColDrop(event) {
    event.preventDefault();
    event.stopPropagation();

    const sourceId =
        event.dataTransfer?.getData('text/plain') ||
        this._dragColId;

    const targetId =
        event.currentTarget.dataset.colId;

    if (!sourceId || !targetId || sourceId === targetId) {
        this._resetColumnDrag();
        return;
    }

    const sourceIndex = this.columns.findIndex(
        col => col.id === sourceId
    );

    const targetIndex = this.columns.findIndex(
        col => col.id === targetId
    );

    if (sourceIndex === -1 || targetIndex === -1) {
        this._resetColumnDrag();
        return;
    }

    const groupedCount = this.groupingIndexes.length;

    // Grouped columns must remain in the grouped section.
    // This preserves the existing grouping implementation.
    if (
        groupedCount > 0 &&
        (
            (sourceIndex < groupedCount) !==
            (targetIndex < groupedCount)
        )
    ) {
        this.showToast(
            'Column Reorder',
            'Please reorder grouped columns within the grouped section and other columns within the remaining section.',
            'warning'
        );

        this._resetColumnDrag();
        return;
    }

    // Copy the existing column configuration.
    const swappedColumns = [...this.columns];

    // Swap the two column objects.
    [
        swappedColumns[sourceIndex],
        swappedColumns[targetIndex]
    ] = [
        swappedColumns[targetIndex],
        swappedColumns[sourceIndex]
    ];

    // Update column order without changing column IDs or field mappings.
    this.columns = swappedColumns.map((col, index) => ({
        ...col,
        order: index + 1
    }));

    this._resetColumnDrag();

    // Refresh grouping summaries when grouped columns are swapped.
    if (
        groupedCount > 0 &&
        sourceIndex < groupedCount &&
        targetIndex < groupedCount
    ) {
        this.fetchData();
    } else {
        this._recompute();
    }
}


// Ends column dragging.
handleColDragEnd() {
// Resets column drag state.
this._resetColumnDrag();
}

// Resets column drag state.
_resetColumnDrag() {

this.template
.querySelectorAll(
'.tli-column-dragging, .tli-column-drag-over'
)
.forEach(el => {

el.classList.remove(
'tli-column-dragging',
'tli-column-drag-over'
);

});

this._dragColId = null;
this._dragTarget = null;
}
renderedCallback() {
    const checkboxes = this.template.querySelectorAll(
        'input.tli-col-checkbox[data-group-key]'
    );

    checkboxes.forEach(checkbox => {
        checkbox.indeterminate =
            checkbox.dataset.indeterminate === 'true';
    });
}

// Handles row selection.
handleRowSelect(event) {
const rowId = event.target.dataset.id;
const checked = event.target.checked;

const selectedRow = this.tableRows.find(
row => row.id === rowId
);

if (!selectedRow) {
return;
}

if (selectedRow.actioned) {
event.target.checked = false;
return;
}

this._selectedRowMap = {
...this._selectedRowMap,
[rowId]: checked
};

this.tableRows = this.tableRows.map(row => {
if (row.id === rowId) {
return {
...row,
selected: checked
};
}

return row;
});

// Syncs selected IDs.
this._syncSelectedIds();

// Refreshes group checkbox state.
this._recompute();
// Restore selected state after recompute.
this.tableRows = this.tableRows.map(row => ({
...row,
selected: !!this._selectedRowMap[row.id]
}));

}

// Handles group selection.
handleGroupSelect(event) {
event.stopPropagation();

const groupKey = event.currentTarget.dataset.groupKey;
const groupLevel = Number(event.currentTarget.dataset.groupLevel);
const checked = event.target.checked;


if (!groupKey || Number.isNaN(groupLevel)) {
return;
}

this._applyGroupSelection(groupKey, groupLevel, checked);

}

// Applies selection to all line items in a group.
_applyGroupSelection(groupKey, groupLevel, checked) {
const cols = this.orderedColumns;
const groupRecords = this._rawRows
.filter(record =>
record &&
!this._isLineItemProcessed(record) &&
this._getGroupingKey(record, cols, groupLevel) === groupKey
);

const groupRecordIds = new Set(
groupRecords.map(record => record.id)
);



groupRecords.forEach(record => {
if (checked) {
    this._selectedRowMap[record.id] = true;
} else {
    delete this._selectedRowMap[record.id];
}
});

this.tableRows = this.tableRows.map(row => {
const record = row.records && row.records[0];

if (record && groupRecordIds.has(record.id)) {
    return {
        ...row,
        selected: checked
    };
}

return row;
});

this._syncSelectedIds();
this._recompute();

}

// Handles select-all.
handleSelectAll(event) {
const checked = event.target.checked;
const newMap = {};

this.tableRows
.filter(row => !row.hidden && !row.actioned)
.forEach(row => {
newMap[row.id] = checked;
});

this._selectedRowMap = newMap;

this.tableRows = this.tableRows.map(row => {
if (row.actioned) {
return { ...row, selected: false };
}

return { ...row, selected: checked };
});

// Syncs selected IDs.
this._syncSelectedIds();

// Refreshes group checkbox state.
this._recompute();
}

// Syncs selected IDs.
_syncSelectedIds() {
const selectedRows = this.tableRows.filter(
row =>
!row.hidden &&
!row.actioned &&
this._selectedRowMap[row.id]
);

const lineItemSet = new Set();
const timesheetSet = new Set();

selectedRows.forEach(row => {
if (row.isPartialAllowed === false) {
    if (row.timesheetId) {
        timesheetSet.add(row.timesheetId);
    }
} else if (row.lineItemId && !this._processedRowIds.has(row.lineItemId)) {
    lineItemSet.add(row.lineItemId);
}
});

this.selectedLineItemIds = Array.from(lineItemSet);
this.selectedTimesheetIds = Array.from(timesheetSet);

}

// Clears row selection.
_clearSelection() {
this._selectedRowMap = {};
this.selectedLineItemIds = [];
this.selectedTimesheetIds = [];

this.tableRows = this.tableRows.map(row => ({
...row,
selected: false
}));

}

// Handles custom date changes.
handleCustomDateChange(event) {
const fieldName = event.target.name;

if (fieldName === 'startDate') {
this.customStartDate = event.detail.value;

window.localStorage.setItem(
'managerApprovalCustomStartDate',
this.customStartDate
);

} else if (fieldName === 'endDate') {
this.customEndDate = event.detail.value;

window.localStorage.setItem(
'managerApprovalCustomEndDate',
this.customEndDate
);

}

if (this.customStartDate && this.customEndDate) {
this.fetchData();
}
}

// Handles date range changes.
handleDateRangeChange(event) {
this.dateRange = event.detail.value;

// Remember selected date range after page refresh
window.localStorage.setItem(
'managerApprovalDateRange',
this.dateRange
);

// Normal date ranges fetch immediately
if (this.dateRange !== 'Custom') {
    this.fetchData();
}

}

// Handles status filter changes.
handleStatusFilterChange(event) {
this.statusFilter = event.detail.value;
// Recomputes table rows.
this._recompute();
}

// Handles employee search changes.
handleEmployeeSearchChange(event) {
this.employeeSearch = event.target.value;
// Recomputes table rows.
this._recompute();
}

// Handles project filter changes.
handleProjectFilterChange(event) {
this.projectFilter = event.detail.value;
// Recomputes table rows.
this._recompute();
}

// Resets table filters.
handleClearFilters() {
this.dateRange = 'All Pending';
window.localStorage.setItem(
'managerApprovalDateRange',
'All Pending'
);
this.statusFilter = 'All';
this.employeeSearch = '';
this.projectFilter = 'All';

this._columnFilterSelections = {};

// Clears row selection.
this._clearSelection();

this.fetchData();

}

// Validates submitted timesheets.
validateSubmittedTimesheets() {
const selectedIds = new Set(this.selectedLineItemIds || []);
const submittedTimesheetIds = new Set();

this._rawRows.forEach(row => {
if (
    row.isPartialAllowed === true &&
    row.timesheetId &&
    row.lineItemId &&
    row.timesheetStatus === 'Submitted' &&
    selectedIds.has(row.lineItemId)
) {
    submittedTimesheetIds.add(row.timesheetId);
}
});

if (submittedTimesheetIds.size === 0) {
return true;
}

for (const timesheetId of submittedTimesheetIds) {
const allLineItems = this._rawRows.filter(row =>
    row.isPartialAllowed === true &&
    row.timesheetId === timesheetId &&
    row.lineItemId
);

const selectedLineItems = allLineItems.filter(row =>
    selectedIds.has(row.lineItemId)
);

if (selectedLineItems.length !== allLineItems.length) {
    return false;
}
}

return true;

}
handleApproveMouseDown() {
console.log('🔥 APPROVE MOUSEDOWN FIRED');
}

// Approves selected line items.
// Approves selected line items or timesheets.
handleApprove() {

console.log('========== APPROVE CLICKED ==========');

console.log(
    '[Approve] isNoSelection:',
    this.isNoSelection
);


console.log(
    '[Approve] selectedLineItemIds:',
    JSON.stringify(this.selectedLineItemIds)
);

console.log(
    '[Approve] selectedTimesheetIds:',
    JSON.stringify(this.selectedTimesheetIds)
);

console.log(
    '[Approve] tableRows:',
    JSON.stringify(this.tableRows)
);

console.log(
    '[Approve] selectedRowMap:',
    JSON.stringify(this._selectedRowMap)
);

if (this.isNoSelection) {

    console.warn(
        '[Approve] STOPPED - No records selected'
    );

    this.showToast(
        'Warning',
        'Please select at least one record to approve.',
        'warning'
    );

    return;
}

const lineItemIds = [...this.selectedLineItemIds];
const timesheetIds = [...this.selectedTimesheetIds];

console.log(
    '[Approve] lineItemIds:',
    JSON.stringify(lineItemIds)
);

console.log(
    '[Approve] timesheetIds:',
    JSON.stringify(timesheetIds)
);

const requests = [];

// Partial Allowed = TRUE
if (lineItemIds.length > 0) {

    console.log(
        '[Approve] Calling approveLineItems Apex...'
    );

    requests.push(
        approveLineItems({ lineItemIds })
            .then(result => {

                console.log(
                    '[Approve] approveLineItems RESULT:',
                    result
                );

                if (result && result.startsWith('Error:')) {
                    console.error(
                        '[Approve] approveLineItems ERROR:',
                        result
                    );

                    throw new Error(result);
                }

                lineItemIds.forEach(id => {
                    this._processedRowIds.add(id);
                });

                console.log(
                    '[Approve] Line items processed:',
                    JSON.stringify(lineItemIds)
                );
            })
            .catch(error => {

                console.error(
                    '[Approve] approveLineItems CATCH:',
                    error
                );

                throw error;
            })
    );
}

// Partial Allowed = FALSE
if (timesheetIds.length > 0) {

    console.log(
        '[Approve] Calling approveTimesheets Apex...'
    );

    requests.push(
        approveTimesheets({ timesheetIds })
            .then(result => {

                console.log(
                    '[Approve] approveTimesheets RESULT:',
                    result
                );

                if (result && result.startsWith('Error:')) {
                    console.error(
                        '[Approve] approveTimesheets ERROR:',
                        result
                    );

                    throw new Error(result);
                }

                timesheetIds.forEach(id => {
                    this._processedRowIds.add(id);
                });

                console.log(
                    '[Approve] Timesheets processed:',
                    JSON.stringify(timesheetIds)
                );
            })
            .catch(error => {

                console.error(
                    '[Approve] approveTimesheets CATCH:',
                    error
                );

                throw error;
            })
    );
}

console.log(
    '[Approve] Number of Apex requests:',
    requests.length
);

if (requests.length === 0) {

    console.error(
        '[Approve] NO APEX REQUEST CREATED'
    );

    this.showToast(
        'Error',
        'No valid records found for approval.',
        'error'
    );

    return;
}

Promise.all(requests)
    .then(() => {

        console.log(
            '[Approve] ALL APPROVAL REQUESTS SUCCESSFUL'
        );

        console.log(
            '[Approve] Clearing selection...'
        );

        this._clearSelection();

        this.showToast(
            'Success',
            'Selected records approved successfully.',
            'success'
        );

        console.log(
            '[Approve] Refreshing data...'
        );

        this.fetchData();
    })
    .catch(error => {

        console.error(
            '[Approve] PROMISE.ALL ERROR:',
            error
        );

        console.error(
            '[Approve] Error body:',
            error?.body
        );

        console.error(
            '[Approve] Error message:',
            error?.body?.message || error?.message
        );

        this.showToast(
            'Error',
            error?.body?.message ||
            error?.message ||
            'Approval failed.',
            'error'
        );
    });

console.log(
    '========== APPROVE FLOW STARTED =========='
);
}

// Opens the rejection dialog.
handleBulkReject() {
if (this.isNoSelection) {
this.showToast(
'Warning',
'Please select at least one line item to reject.',
'warning'
);
return;
}



this.bulkRejectionReason = '';
this.isBulkRejectModalOpen = true;
}

// Closes the rejection dialog.
closeBulkRejectModal() {
this.isBulkRejectModalOpen = false;
this.bulkRejectionReason = '';
}

// Updates the rejection reason.
handleBulkRejectionReasonChange(event) {
this.bulkRejectionReason = event.target.value;
}

// Rejects selected line items.
confirmBulkReject() {
if (!this.bulkRejectionReason || !this.bulkRejectionReason.trim()) {
this.showToast('Warning', 'Please provide a reason for rejection.', 'warning');
return;
}

if (this.isNoSelection) {
this.showToast('Warning', 'Please select at least one record to reject.', 'warning');
return;
}

const lineItemIds = [...this.selectedLineItemIds];
const timesheetIds = [...this.selectedTimesheetIds];
const rejectionNotes = this.bulkRejectionReason.trim();
const requests = [];

if (lineItemIds.length > 0) {
requests.push(
    rejectLineItemsWithNotes({
        lineItemIds,
        rejectionNotes
    }).then(result => {
        if (result && result.startsWith('Error:')) {
            throw new Error(result);
        }
        lineItemIds.forEach(id => this._processedRowIds.add(id));
    })
);
}

if (timesheetIds.length > 0) {
requests.push(
    rejectTimesheets({ timesheetIds })
        .then(result => {
            if (result && result.startsWith('Error:')) {
                throw new Error(result);
            }
            timesheetIds.forEach(id => this._processedRowIds.add(id));
        })
);
}

Promise.all(requests)
.then(() => {
    this._clearSelection();
    this.closeBulkRejectModal();
    this.showToast(
        'Success',
        'Selected records rejected successfully.',
        'success'
    );
    this.fetchData();
})
.catch(error => {
    this.showToast(
        'Error',
        error.body ? error.body.message : error.message,
        'error'
    );
});

}

// Returns the status CSS class.
_statusClass(st) {
if (st === 'Approved') {
return 'status-pill status-approved';
}

if (st === 'Partial Approved') {
return 'status-pill status-partial-approved';
}

if (st === 'Partial Submitted') {
return 'status-pill status-partial';
}

if (st === 'New') {
return 'status-pill status-new';
}

if (st === 'Rejected') {
return 'status-pill status-rejected';
}

if (st === 'Submitted') {
return 'status-pill status-submitted';
}

return 'status-pill status-submitted';
}

// Displays a toast message.
showToast(title, message, variant) {
this.dispatchEvent(
new ShowToastEvent({
title,
message,
variant
})
);
}
}