import { LightningElement, track } from 'lwc';
import getTimesheetData from '@salesforce/apex/TimesheetApprovalController.getTimesheetData';
import approveTimesheets from '@salesforce/apex/TimesheetApprovalController.approveTimesheets';
import rejectTimesheets from '@salesforce/apex/TimesheetApprovalController.rejectTimesheets';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const MAIN_MAX = 200;

// isExpanded=true  → Expanded (group-by): each distinct value gets its own row, with merged cells (rowspan)
// isExpanded=false → Collapsed: values within the left-context are summarised as "Distinct: N" or "N hrs" for duration
const MAIN_COLUMN_DEFS = [
    { id: 'employeeName', label: 'Employee', fieldName: 'employeeName', order: 1, isExpanded: true,  isDuration: false, sortDirection: 'asc', isFilterOpen: false },
    { id: 'date',         label: 'Date',     fieldName: 'date',         order: 2, isExpanded: false, isDuration: false, sortDirection: 'asc', isFilterOpen: false },
    { id: 'projectName',  label: 'Project',  fieldName: 'projectName',  order: 3, isExpanded: false, isDuration: false, sortDirection: 'asc', isFilterOpen: false },
    { id: 'activityName', label: 'Activity', fieldName: 'activityName', order: 4, isExpanded: false, isDuration: false, sortDirection: 'asc', isFilterOpen: false },
    { id: 'duration',     label: 'Duration', fieldName: 'duration',     order: 5, isExpanded: false, isDuration: true,  sortDirection: 'asc', isFilterOpen: false },
    { id: 'status',       label: 'Status',   fieldName: 'status',       order: 6, isExpanded: false, isDuration: false, sortDirection: 'asc', isFilterOpen: false }
];

export default class TimesheetApprovalScreen extends LightningElement {
    @track dateRange        = 'Current Week';
    @track statusFilter     = 'All';
    @track employeeSearch   = '';
    @track projectFilter    = 'All';
    @track isBulkRejectModalOpen = false;
    @track bulkRejectionReason   = '';
    @track customStartDate;
    @track customEndDate;
    @track isTableLoading   = false;

    // Column definitions (mutable for order / expand state)
    @track columns = MAIN_COLUMN_DEFS.map(c => Object.assign({}, c));

    // Raw flat leaf rows from Apex (never mutated after fetch)
    _rawRows = [];

    // Computed flat display rows (with rowspan / hidden / displayValue)
    @track tableRows = [];
    @track totalCount = 0;

    // Row selection
    @track _selectedRowMap = {};
    selectedTimesheetIds   = [];

    // Per-column multi-checkbox filter selections
    @track _columnFilterSelections = {};

    // Active column being sorted
    @track _activeSortColId = 'employeeName';

    // Drag state
    _dragColId   = null;
    _dragTarget  = null;

    // ─── Lifecycle ───────────────────────────────────────────────────────────────
    connectedCallback() { this.fetchData(); }

    // ─── Filter / Date Options ───────────────────────────────────────────────────
    get isCustomDate()  { return this.dateRange === 'Custom'; }
    get isNoSelection() { return !this.selectedTimesheetIds || this.selectedTimesheetIds.length === 0; }
    get isTableEmpty()  { return !this.tableRows || this.tableRows.length === 0; }
    get isCountExceeded() { return this.totalCount > MAIN_MAX; }
    get maxLimit() { return MAIN_MAX; }

    get dateRangeOptions() {
        return [
            { label: 'Current Week',  value: 'Current Week'  },
            { label: 'Last Week',     value: 'Last Week'     },
            { label: 'Current Month', value: 'Current Month' },
            { label: 'Last Month',    value: 'Last Month'    },
            { label: 'All Pending',   value: 'All Pending'   },
            { label: 'Custom',        value: 'Custom'        }
        ];
    }

    get statusOptions() {
        return [
            { label: 'All Statuses', value: 'All'       },
            { label: 'Submitted',    value: 'Submitted'  },
            { label: 'Partial',      value: 'Partial'    }
        ];
    }

    get projectOptions() {
        const projects = new Set();
        this._rawRows.forEach(r => { if (r.projectName) projects.add(r.projectName); });
        const opts = [{ label: 'All Projects', value: 'All' }];
        Array.from(projects).sort().forEach(p => opts.push({ label: p, value: p }));
        return opts;
    }

    // ─── Computed column list (ordered) ─────────────────────────────────────────
    get orderedColumns() {
        return [...this.columns].sort((a, b) => a.order - b.order).map(col => {
            const isAsc = col.sortDirection !== 'desc';
            const isSortActive = this._activeSortColId === col.id;
            const selectedSet = this._columnFilterSelections[col.id];
            const isFiltered = selectedSet != null;

            const distinctValues = new Set();
            this._rawRows.forEach(r => {
                const val = r[col.fieldName] != null && String(r[col.fieldName]).trim() !== ''
                    ? String(r[col.fieldName])
                    : '(Blank)';
                distinctValues.add(val);
            });

            const filterOptions = Array.from(distinctValues).sort().map(val => {
                const isChecked = selectedSet == null ? true : selectedSet.has(val);
                return {
                    label: val,
                    value: val,
                    checked: isChecked
                };
            });

            return Object.assign({}, col, {
                typeTitle: col.isExpanded ? 'Expanded — click to collapse' : 'Collapsed — click to expand',
                sortIcon: isAsc ? '↑' : '↓',
                sortTitle: isAsc ? 'Sort Ascending — click for Descending' : 'Sort Descending — click for Ascending',
                sortBtnClass: 'tli-col-action-btn' + (isSortActive ? ' tli-sort-active' : ''),
                filterBtnClass: 'tli-col-filter-btn' + (isFiltered ? ' tli-filter-active' : ''),
                filterOptions: filterOptions
            });
        });
    }

    // Number of <td> cols = data columns + 2 (checkbox + row#)
    get colSpan() { return this.orderedColumns.length + 2; }

    get isAllSelected() {
        return this.tableRows.length > 0 &&
               this.tableRows.filter(r => !r.hidden).every(r => !!this._selectedRowMap[r.id]);
    }

    // ─── Data Fetching ───────────────────────────────────────────────────────────
    fetchData() {
        getTimesheetData({
            dateRange:       this.dateRange,
            customStartDate: this.customStartDate,
            customEndDate:   this.customEndDate
        })
        .then(result => {
            this._rawRows = this._parseApexResult(result);
            this._recompute();
        })
        .catch(error => {
            this.showToast('Error', error.body ? error.body.message : error.message, 'error');
        });
    }

    // Convert Apex wrapper list → flat leaf row array
    _parseApexResult(rawList) {
        if (!rawList) return [];
        const rows = [];
        rawList.forEach((wrapper, wIdx) => {
            const empName     = wrapper.employeeName || 'Unknown Employee';
            const tsStatus    = wrapper.timesheetStatus || 'Submitted';
            const fallbackDate = wrapper.startDate ? String(wrapper.startDate) : '';
            const tsId        = wrapper.timesheetId || wrapper.id;

            if (wrapper.lineItems && wrapper.lineItems.length > 0) {
                wrapper.lineItems.forEach((li, lIdx) => {
                    const typeVal    = li.dbt__Type__c;
                    const isAbsence  = typeVal === 'Absence';
                    const absenceCat = li.dbt__Absence_Category__c || 'Absence';
                    const projObj    = li.dbt__Project__r;
                    const projId     = li.dbt__Project__c;
                    const pName      = isAbsence ? absenceCat : (projObj ? projObj.Name : (projId || wrapper.projectName || 'N/A'));
                    const aName      = isAbsence ? '-' : (li.dbt__Activity__c || li.dbt__Description__c || typeVal || '-');
                    const durVal     = li.dbt__Duration__c;
                    const dur        = (durVal !== undefined && durVal !== null) ? parseFloat(durVal) : 0;
                    const st         = li.dbt__Line_Item_Status__c || tsStatus;
                    const lineDate   = li.dbt__Date__c || fallbackDate;

                    rows.push({
                        id:           li.Id || (tsId + '_li_' + lIdx),
                        timesheetId:  tsId,
                        employeeName: empName,
                        date:         lineDate,
                        projectName:  pName,
                        activityName: aName,
                        duration:     dur,
                        status:       st,
                        statusClass:  this._statusClass(st)
                    });
                });
            } else {
                rows.push({
                    id:           wrapper.id || ('ts_' + wIdx),
                    timesheetId:  tsId,
                    employeeName: empName,
                    date:         fallbackDate,
                    projectName:  wrapper.projectName || 'N/A',
                    activityName: '-',
                    duration:     wrapper.duration || 0,
                    status:       tsStatus,
                    statusClass:  this._statusClass(tsStatus)
                });
            }
        });
        return rows;
    }

    // ─── Core Table Computation ──────────────────────────────────────────────────
    // Called whenever columns change or filters change.
    _recompute() {
        // 1. Apply filters to raw rows
        let filtered = [...this._rawRows];
        if (this.statusFilter && this.statusFilter !== 'All') {
            filtered = filtered.filter(r => r.status === this.statusFilter);
        }
        if (this.employeeSearch && this.employeeSearch.trim()) {
            const q = this.employeeSearch.trim().toLowerCase();
            filtered = filtered.filter(r => r.employeeName && r.employeeName.toLowerCase().includes(q));
        }
        if (this.projectFilter && this.projectFilter !== 'All') {
            filtered = filtered.filter(r => r.projectName === this.projectFilter);
        }
        // Apply column multi-checkbox filters
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

        this.totalCount = filtered.length;
        const capped = filtered.slice(0, MAIN_MAX);

        // 2. Sort by all ordered columns left-to-right respecting column status (Expanded vs Collapsed)
        const cols = this.orderedColumns;

        // Build lookup cache for collapsed columns so sort comparisons compare calculated Distinct Values / Duration Sums
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
                        const totalDur = groupRecs.reduce((s, rec) => s + (parseFloat(rec[col.fieldName]) || 0), 0);
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
                colCache[ci] = { contextColIds, valueMap };
            }
        }

        const getSortVal = (r, ci) => {
            const col = cols[ci];
            const cache = colCache[ci];
            if (!cache) {
                const rawVal = r[col.fieldName];
                if (col.isDuration) return parseFloat(rawVal) || 0;
                return rawVal != null ? String(rawVal).toLowerCase() : '';
            } else {
                const ctxKey = this._getRowContextKey(r, cache.contextColIds, cols);
                return cache.valueMap.get(ctxKey) || 0;
            }
        };

        const activeCol = cols.find(c => c.id === this._activeSortColId) || cols[0];
        const activeIdx = cols.indexOf(activeCol);

        capped.sort((a, b) => {
            // 1. Primary sort: active column that user clicked
            if (activeIdx >= 0) {
                const va = getSortVal(a, activeIdx);
                const vb = getSortVal(b, activeIdx);
                if (va < vb) return activeCol.sortDirection === 'desc' ? 1 : -1;
                if (va > vb) return activeCol.sortDirection === 'desc' ? -1 : 1;
            }

            // 2. Secondary sort (tie-breaker): all ordered columns left-to-right
            for (let ci = 0; ci < cols.length; ci++) {
                if (ci === activeIdx) continue;
                const col = cols[ci];
                const va = getSortVal(a, ci);
                const vb = getSortVal(b, ci);
                if (va < vb) return col.sortDirection === 'desc' ? 1 : -1;
                if (va > vb) return col.sortDirection === 'desc' ? -1 : 1;
            }
            return 0;
        });

        // 3. Build flat display rows with rowspan logic
        this.tableRows = this._buildDisplayRows(capped, cols);
        this._selectedRowMap = {};
        this.selectedTimesheetIds = [];
    }

    /**
     * Builds a flat array of display rows.
     * Step 1: Identify leaf rows from distinct combinations of all EXPANDED columns.
     * Step 2: For each column left to right, compute cell value and rowspan across leaf rows.
     */
    _buildDisplayRows(data, cols) {
        if (!data || !data.length) return [];

        // 1. Identify which columns are EXPANDED
        const expandedCols = cols.filter(c => c.isExpanded);

        // 2. Build LEAF ROWS by grouping data by unique combination of expandedCols values
        const leafGroups = new Map();
        for (const raw of data) {
            let key = 'GLOBAL';
            if (expandedCols.length > 0) {
                key = '';
                for (const col of expandedCols) {
                    const val = raw[col.fieldName] != null ? String(raw[col.fieldName]) : '';
                    key += '§' + col.id + ':' + val;
                }
            }
            if (!leafGroups.has(key)) {
                leafGroups.set(key, []);
            }
            leafGroups.get(key).push(raw);
        }

        const leafEntries = Array.from(leafGroups.entries());
        const display = leafEntries.map(([leafKey, records], idx) => {
            const firstRaw = records[0];
            return {
                id:          firstRaw.id || ('row_' + idx),
                timesheetId: firstRaw.timesheetId,
                rowNum:      idx + 1,
                records:     records,
                cells:       [],
                hidden:      false,
                selected:    false
            };
        });

        // 3. For each column from left to right, compute cell value and rowspan
        for (let ci = 0; ci < cols.length; ci++) {
            const col = cols[ci];

            const contextColIds = [];
            for (let j = 0; j <= (col.isExpanded ? ci : ci - 1); j++) {
                if (cols[j] && cols[j].isExpanded) {
                    contextColIds.push(cols[j].id);
                }
            }

            let r = 0;
            while (r < display.length) {
                const startRow = r;
                const contextKey = this._getRowContextKey(display[startRow].records[0], contextColIds, cols);

                let endRow = startRow + 1;
                while (endRow < display.length &&
                       this._getRowContextKey(display[endRow].records[0], contextColIds, cols) === contextKey) {
                    endRow++;
                }

                const groupLength = endRow - startRow;

                let allRecordsInGroup = [];
                for (let k = startRow; k < endRow; k++) {
                    allRecordsInGroup = allRecordsInGroup.concat(display[k].records);
                }

                let cellValue = '';
                let statusCls = '';
                if (col.isExpanded) {
                    const firstRec = display[startRow].records[0];
                    cellValue = firstRec[col.fieldName] != null ? String(firstRec[col.fieldName]) : '';
                    statusCls = col.id === 'status' ? firstRec.statusClass : '';
                } else {
                    if (col.isDuration) {
                        const totalDur = allRecordsInGroup.reduce((s, rec) => s + (parseFloat(rec[col.fieldName]) || 0), 0);
                        cellValue = totalDur.toFixed(1).replace(/\.0$/, '') + ' hrs';
                    } else {
                        const distinctVals = new Set(
                            allRecordsInGroup
                                .map(rec => rec[col.fieldName])
                                .filter(v => v != null && v !== '')
                                .map(String)
                        );
                        cellValue = 'Distinct: ' + distinctVals.size;
                    }
                    statusCls = col.id === 'status' && allRecordsInGroup.length > 0 ? allRecordsInGroup[0].statusClass : '';
                }

                for (let k = startRow; k < endRow; k++) {
                    const isFirst = (k === startRow);
                    display[k].cells.push({
                        id:          col.id + '_' + k,
                        colId:       col.id,
                        value:       isFirst ? cellValue : '',
                        rowspan:     isFirst ? groupLength : 0,
                        isStatus:    col.id === 'status' && isFirst,
                        statusClass: isFirst ? statusCls : '',
                        isDuration:  col.isDuration
                    });
                }

                r = endRow;
            }
        }

        // 4. Attach selected state
        display.forEach(row => {
            row.selected = !!this._selectedRowMap[row.id];
        });

        return display;
    }

    _getRowContextKey(record, colIds, allCols) {
        if (!colIds.length) return 'GLOBAL';
        let key = '';
        for (const colId of colIds) {
            const col = allCols.find(c => c.id === colId);
            const val = col && record[col.fieldName] != null ? String(record[col.fieldName]) : '';
            key += '§' + colId + ':' + val;
        }
        return key;
    }

    // ─── Column Header Toggle (Expanded ↔ Collapsed) ─────────────────────────────
    handleColTypeToggle(event) {
        const colId = event.currentTarget.dataset.colId;
        this.columns = this.columns.map(col =>
            col.id === colId ? Object.assign({}, col, { isExpanded: !col.isExpanded }) : col
        );
        this._recompute();
    }

    // ─── Column Sort Toggle (ASC ↔ DESC) ─────────────────────────────────────────
    handleColSortToggle(event) {
        event.stopPropagation();
        const colId = event.currentTarget.dataset.colId;
        this._activeSortColId = colId;
        this.columns = this.columns.map(col =>
            col.id === colId
                ? Object.assign({}, col, { sortDirection: col.sortDirection === 'desc' ? 'asc' : 'desc' })
                : col
        );
        this._recompute();
    }

    // ─── Column Filter Dropdown Handlers ─────────────────────────────────────────
    handleColFilterToggle(event) {
        event.stopPropagation();
        const colId = event.currentTarget.dataset.colId;
        this.columns = this.columns.map(col =>
            col.id === colId
                ? Object.assign({}, col, { isFilterOpen: !col.isFilterOpen })
                : Object.assign({}, col, { isFilterOpen: false }) // close others
        );
    }

    handleColFilterClose(event) {
        event.stopPropagation();
        const colId = event.currentTarget.dataset.colId;
        this.columns = this.columns.map(col =>
            col.id === colId ? Object.assign({}, col, { isFilterOpen: false }) : col
        );
    }

    handleDropdownClick(event) {
        event.stopPropagation(); // prevent drag or outside click handlers
    }

    handleFilterSelectAll(event) {
        event.stopPropagation();
        const colId = event.currentTarget.dataset.colId;
        const nextMap = Object.assign({}, this._columnFilterSelections);
        nextMap[colId] = null; // null = all checked / no filter
        this._columnFilterSelections = nextMap;
        this._recompute();
    }

    handleFilterClearAll(event) {
        event.stopPropagation();
        const colId = event.currentTarget.dataset.colId;
        const nextMap = Object.assign({}, this._columnFilterSelections);
        nextMap[colId] = new Set(); // empty Set = 0 items match
        this._columnFilterSelections = nextMap;
        this._recompute();
    }

    handleFilterOptionChange(event) {
        event.stopPropagation();
        const colId   = event.currentTarget.dataset.colId;
        const val     = event.target.value;
        const checked = event.target.checked;

        const targetCol = this.columns.find(c => c.id === colId);
        if (!targetCol) return;

        let currentSet = this._columnFilterSelections[colId];
        if (currentSet == null) {
            currentSet = new Set();
            this._rawRows.forEach(r => {
                const v = r[targetCol.fieldName] != null && String(r[targetCol.fieldName]).trim() !== ''
                    ? String(r[targetCol.fieldName])
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
        this._rawRows.forEach(r => {
            const v = r[targetCol.fieldName] != null && String(r[targetCol.fieldName]).trim() !== ''
                ? String(r[targetCol.fieldName])
                : '(Blank)';
            allDistinct.add(v);
        });

        const nextMap = Object.assign({}, this._columnFilterSelections);
        if (currentSet.size === allDistinct.size) {
            nextMap[colId] = null; // all selected -> clear filter
        } else {
            nextMap[colId] = currentSet;
        }
        this._columnFilterSelections = nextMap;
        this._recompute();
    }

    // ─── Column Drag to Reorder ───────────────────────────────────────────────────
    handleColDragStart(event) {
        this._dragColId = event.currentTarget.dataset.colId;
        event.dataTransfer.setData('text/plain', this._dragColId);
        event.dataTransfer.effectAllowed = 'move';
    }
    handleColDragOver(event) {
        event.preventDefault();
        const targetId = event.currentTarget.dataset.colId;
        if (targetId !== this._dragColId) {
            this._dragTarget = targetId;
            this.columns = [...this.columns];
        }
    }
    handleColDragLeave(event) {
        if (this._dragTarget === event.currentTarget.dataset.colId) {
            this._dragTarget = null;
            this.columns = [...this.columns];
        }
    }
    handleColDrop(event) {
        event.preventDefault();
        const targetId = event.dataTransfer.getData('text/plain') !== event.currentTarget.dataset.colId
            ? event.currentTarget.dataset.colId : null;
        const sourceId = event.dataTransfer.getData('text/plain');
        if (sourceId && targetId && sourceId !== targetId) {
            const src = this.columns.find(c => c.id === sourceId);
            const tgt = this.columns.find(c => c.id === targetId);
            if (src && tgt) {
                const tmp = src.order;
                this.columns = this.columns.map(col => {
                    if (col.id === sourceId) return Object.assign({}, col, { order: tgt.order });
                    if (col.id === targetId) return Object.assign({}, col, { order: tmp });
                    return col;
                });
                this.isTableLoading = true;
                setTimeout(() => {
                    this._recompute();
                    this.isTableLoading = false;
                }, 150);
            }
        }
        this._dragTarget = null;
        this._dragColId  = null;
    }

    // ─── Row Selection ────────────────────────────────────────────────────────────
    handleRowSelect(event) {
        const rowId  = event.target.dataset.id;
        const checked = event.target.checked;
        this._selectedRowMap = Object.assign({}, this._selectedRowMap, { [rowId]: checked });
        this._syncSelectedIds();
    }
    handleSelectAll(event) {
        const checked = event.target.checked;
        const newMap  = {};
        this.tableRows.filter(r => !r.hidden).forEach(r => { newMap[r.id] = checked; });
        this._selectedRowMap = newMap;
        this._syncSelectedIds();
    }
    _syncSelectedIds() {
        const tsSet = new Set();
        this.tableRows.filter(r => !r.hidden && this._selectedRowMap[r.id])
            .forEach(r => tsSet.add(r.timesheetId));
        this.selectedTimesheetIds = Array.from(tsSet);
    }

    // ─── Filter Handlers ──────────────────────────────────────────────────────────
    handleDateRangeChange(event) {
        this.dateRange = event.detail.value;
        if (this.dateRange !== 'Custom') this.fetchData();
    }
    handleCustomDateChange(event) {
        const fieldName = event.target.name;
        if (fieldName === 'startDate')    this.customStartDate = event.detail.value;
        else if (fieldName === 'endDate') this.customEndDate   = event.detail.value;
        if (this.customStartDate && this.customEndDate) this.fetchData();
    }
    handleStatusFilterChange(event) {
        this.statusFilter = event.detail.value;
        this._recompute();
    }
    handleEmployeeSearchChange(event) {
        this.employeeSearch = event.target.value;
        this._recompute();
    }
    handleProjectFilterChange(event) {
        this.projectFilter = event.detail.value;
        this._recompute();
    }

    // ─── Approve / Reject ─────────────────────────────────────────────────────────
    handleApprove() {
        if (this.isNoSelection) { this.showToast('Warning', 'Please select at least one row to approve.', 'warning'); return; }
        approveTimesheets({ timesheetIds: this.selectedTimesheetIds })
            .then(() => {
                this.showToast('Success', 'Selected timesheets approved successfully.', 'success');
                this.selectedTimesheetIds = [];
                this.fetchData();
            })
            .catch(error => this.showToast('Error', error.body ? error.body.message : error.message, 'error'));
    }
    handleBulkReject() {
        if (this.isNoSelection) { this.showToast('Warning', 'Please select at least one timesheet to reject.', 'warning'); return; }
        this.bulkRejectionReason = '';
        this.isBulkRejectModalOpen = true;
    }
    closeBulkRejectModal()                 { this.isBulkRejectModalOpen = false; this.bulkRejectionReason = ''; }
    handleBulkRejectionReasonChange(event) { this.bulkRejectionReason = event.target.value; }
    confirmBulkReject() {
        if (!this.bulkRejectionReason || !this.bulkRejectionReason.trim()) {
            this.showToast('Warning', 'Please provide a reason for rejection.', 'warning');
            return;
        }
        rejectTimesheets({ timesheetIds: this.selectedTimesheetIds })
            .then(() => {
                this.showToast('Success', 'Selected timesheets rejected successfully.', 'success');
                this.selectedTimesheetIds = [];
                this.closeBulkRejectModal();
                this.fetchData();
            })
            .catch(error => this.showToast('Error', error.body ? error.body.message : error.message, 'error'));
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────
    _statusClass(st) {
        if (st === 'Approved') return 'status-pill status-approved';
        if (st === 'Partial' || st === 'Partial Approved') return 'status-pill status-partial';
        if (st === 'Rejected' || st === 'New') return 'status-pill status-rejected';
        return 'status-pill status-submitted';
    }
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}