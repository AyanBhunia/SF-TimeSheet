import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getDayRecords from '@salesforce/apex/PtoController.getDayRecords';
import submitLeave from '@salesforce/apex/PtoController.submitLeave';

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MAX_RANGE_DAYS = 62;
const ACTIVE = ['Submitted', 'Approved'];

let rowSeq = 0;
const newKey = () => `n${++rowSeq}`;

export default class PtoApply extends LightningElement {
    _context;
    employeeId;
    startDate = '';
    endDate = '';
    category;
    hoursPerDay;
    includeWeekends = false;
    reason = '';
    rows = [];
    records = { leaves: [], lineItems: [] };
    loadedEmployee;
    serverErrors = {};
    showMissing = false;
    // setup: pick employee, dates and category; edit: the days (setup fields greyed out); review: confirm.
    step = 'setup';
    isLoading = false;
    isSubmitting = false;
    rangeError;
    loadSeq = 0;

    @api
    get context() {
        return this._context;
    }
    set context(value) {
        const first = !this._context;
        this._context = value;
        if (first && value) {
            this.employeeId = value.employee ? value.employee.id : undefined;
            const categories = value.categories || [];
            const firstCategory = categories.find((c) => c.value === 'PTO-Planned') || categories[0];
            this.category = firstCategory ? firstCategory.value : undefined;
            this.hoursPerDay = firstCategory ? Math.min(8, firstCategory.maxHours) : 8;
            this.rows = [this.blankRow()];
        }
    }

    // ------------------------------------------------------------------ options and labels

    get employeeOptions() {
        const options = [];
        const self = this._context?.employee;
        if (self) {
            options.push({ label: `Me (${self.name})`, value: self.id });
        }
        (this._context?.employees || []).forEach((e) => {
            options.push({ label: e.hasManager ? e.name : `${e.name} (no manager)`, value: e.id });
        });
        return options;
    }

    get canPickEmployee() {
        return (this._context?.employees || []).length > 0;
    }

    get selfName() {
        return this._context?.employee?.name || '';
    }

    get categoryOptions() {
        return (this._context?.categories || []).map((c) => ({
            label: `${c.label} (max ${formatHours(c.maxHours)} h)`,
            value: c.value
        }));
    }

    get tableCategoryOptions() {
        return (this._context?.categories || []).map((c) => ({ label: c.label, value: c.value }));
    }

    get categoryMax() {
        return this.maxFor(this.category);
    }

    get dailyMax() {
        return Number(this._context?.dailyMax) || 24;
    }

    get isSetup() {
        return this.step === 'setup';
    }

    get isEdit() {
        return this.step === 'edit';
    }

    get isSetupOrEdit() {
        return this.isSetup || this.isEdit;
    }

    get hint() {
        return this.isSetup
            ? 'Pick a start and end date to get one row per day, or skip the dates and add days yourself after Next.'
            : 'Grey rows are already on a request or the timesheet. Use Back to change the selections above.';
    }

    get isReview() {
        return this.step === 'review';
    }

    get noEmployeeSelected() {
        return !this.employeeId;
    }

    // Leave can't start in the past. Today comes from the server (the user's Salesforce time zone, the same day the
    // date picker marks as today); the browser's own date only if the context hasn't loaded.
    get today() {
        return this._context?.today || formatYmd(new Date());
    }

    get endMin() {
        return this.startDate && this.startDate > this.today ? this.startDate : this.today;
    }

    get columns() {
        return [
            { fieldName: 'date', label: 'Date', type: 'date', editable: true, width: '10rem', min: this.today },
            { fieldName: 'day', label: 'Day', type: 'text', width: '4rem' },
            {
                fieldName: 'category',
                label: 'Absence category',
                type: 'picklist',
                editable: true,
                options: this.tableCategoryOptions,
                width: '12rem'
            },
            { fieldName: 'hours', label: 'Hours', type: 'number', editable: true, align: 'right', width: '7rem' },
            { fieldName: 'status', label: 'Status', type: 'status', width: '10rem' }
        ];
    }

    get rowActions() {
        return [{ name: 'remove', label: 'Remove', variant: 'base' }];
    }

    // ------------------------------------------------------------------ table rows

    get tableRows() {
        const checked = this.checkRows();
        const locked = this.lockedRows().map((r) => ({ ...r, locked: true }));
        const editable = this.rows.map((r) => {
            const result = checked[r.key] || {};
            return {
                key: r.key,
                date: r.date,
                day: dayName(r.date),
                category: r.category,
                hours: r.hours,
                status: '',
                error: result.error
            };
        });
        return [...locked, ...editable].sort((a, b) => {
            const da = a.date || '9999-99-99';
            const db = b.date || '9999-99-99';
            if (da !== db) {
                return da < db ? -1 : 1;
            }
            return a.locked === b.locked ? 0 : a.locked ? -1 : 1;
        });
    }

    lockedRows() {
        const rows = [];
        const activeLeave = this.records.leaves.filter((l) => ACTIVE.includes(l.status));
        const leaveKeys = new Set(activeLeave.map((l) => `${l.date}|${l.category}`));
        activeLeave.forEach((l) => {
            rows.push({
                key: `L${l.id}`,
                date: l.date,
                day: dayName(l.date),
                category: l.category,
                hours: l.hours,
                status: l.status,
                info: `On ${l.requestName}`
            });
        });
        this.records.lineItems
            .filter((li) => li.type === 'Absence' && !leaveKeys.has(`${li.date}|${li.category}`))
            .forEach((li) => {
                rows.push({
                    key: `T${li.id}`,
                    date: li.date,
                    day: dayName(li.date),
                    category: li.category,
                    hours: li.hours,
                    status: 'On timesheet',
                    info: 'Already on the timesheet'
                });
            });
        return rows;
    }

    /**
     * Same rules as LeaveValidator on the server; the server answer wins on submit.
     */
    checkRows() {
        const result = {};
        const items = this.records.lineItems;
        const activeLeave = this.records.leaves.filter((l) => ACTIVE.includes(l.status));
        const counts = {};
        const newHoursByDay = {};
        this.rows.forEach((r) => {
            if (r.date) {
                newHoursByDay[r.date] = (newHoursByDay[r.date] || 0) + (Number(r.hours) || 0);
                if (r.category) {
                    const k = `${r.date}|${r.category}`;
                    counts[k] = (counts[k] || 0) + 1;
                }
            }
        });

        this.rows.forEach((r) => {
            let error = this.serverErrors[r.key] || '';
            const hours = Number(r.hours);
            const blank = !r.date;
            if (!error) {
                if (!r.date) {
                    error = this.showMissing && !blank ? 'Pick a date.' : '';
                } else if (r.date < this.today) {
                    error = `${r.date} is in the past. Pick today or a later date.`;
                } else if (!r.category) {
                    error = 'Pick an absence category.';
                } else if (r.hours === '' || r.hours === null || r.hours === undefined || !(hours > 0)) {
                    error = 'Hours must be more than 0.';
                } else if (hours > this.maxFor(r.category)) {
                    error = `${r.category} allows up to ${formatHours(this.maxFor(r.category))} hours per day.`;
                } else if (counts[`${r.date}|${r.category}`] > 1) {
                    error = `${r.category} on ${r.date} is entered more than once.`;
                } else {
                    const sameLeave = activeLeave.find((l) => l.date === r.date && l.category === r.category);
                    const dayItems = items.filter((li) => li.date === r.date);
                    if (sameLeave) {
                        error = `${r.category} on ${r.date} is already on ${sameLeave.requestName}, ${
                            sameLeave.status === 'Approved' ? 'approved' : 'waiting for approval'
                        }.`;
                    } else if (dayItems.some((li) => li.type === 'Absence' && li.category === r.category)) {
                        error = `${r.category} on ${r.date} is already on the timesheet.`;
                    } else {
                        const absenceCats = new Set(
                            dayItems.filter((li) => li.type === 'Absence').map((li) => li.category)
                        );
                        let total = dayItems.reduce((s, li) => s + (Number(li.hours) || 0), 0);
                        activeLeave
                            .filter((l) => l.date === r.date && !absenceCats.has(l.category))
                            .forEach((l) => {
                                total += Number(l.hours) || 0;
                            });
                        total += newHoursByDay[r.date] || 0;
                        if (total > this.dailyMax) {
                            const logged = dayItems
                                .filter((li) => li.type !== 'Absence')
                                .reduce((s, li) => s + (Number(li.hours) || 0), 0);
                            error = `The total for ${r.date} would be ${formatHours(total)} hours, over the ${formatHours(
                                this.dailyMax
                            )}-hour daily limit${logged ? ` (${formatHours(logged)} h already logged)` : ''}.`;
                        }
                    }
                }
            }
            result[r.key] = { error };
        });
        return result;
    }

    // ------------------------------------------------------------------ review summary

    get submitRows() {
        return this.rows.filter((r) => r.date);
    }

    get totalHours() {
        return this.submitRows.reduce((s, r) => s + (Number(r.hours) || 0), 0);
    }

    get totalHoursLabel() {
        return `${formatHours(this.totalHours)} h`;
    }

    get dayCount() {
        return this.submitRows.length;
    }

    get dateSpan() {
        const dates = this.submitRows.map((r) => r.date).filter(Boolean).sort();
        return dates.length ? `${dates[0]} to ${dates[dates.length - 1]}` : '';
    }

    get categorySummary() {
        const byCat = {};
        this.submitRows.forEach((r) => {
            byCat[r.category] = (byCat[r.category] || 0) + (Number(r.hours) || 0);
        });
        return Object.keys(byCat)
            .map((c) => `${c} ${formatHours(byCat[c])} h`)
            .join(' · ');
    }

    get available() {
        const value = this.loadedEmployee?.available;
        return value === null || value === undefined ? null : Number(value);
    }

    get balanceAfterLabel() {
        return this.available === null ? '—' : `${formatHours(this.available - this.totalHours)} h`;
    }

    get balanceNowLabel() {
        return this.available === null ? '' : `Now ${formatHours(this.available)} h`;
    }

    get overBalance() {
        return this.available !== null && this.available - this.totalHours < 0;
    }

    get overBalanceMessage() {
        return `This goes over the leave balance by ${formatHours(this.totalHours - this.available)} hours. You can still submit.`;
    }

    get noManager() {
        return this.loadedEmployee && !this.loadedEmployee.hasManager;
    }

    get reasonSummary() {
        return this.reason && this.reason.trim() ? `Reason: ${firstLine(this.reason.trim())}` : 'No reason given';
    }

    get applyingFor() {
        const self = this._context?.employee;
        if (self && self.id === this.employeeId) {
            return '';
        }
        return this.loadedEmployee ? `Applying for ${this.loadedEmployee.name}.` : '';
    }

    get submitLabel() {
        return 'Submit request';
    }

    // ------------------------------------------------------------------ handlers

    handleEmployee(event) {
        this.employeeId = event.detail.value;
        this.serverErrors = {};
        this.loadRecords();
    }

    handleStart(event) {
        this.startDate = event.target.value || '';
        if (this.startDate && (!this.endDate || this.endDate < this.startDate)) {
            this.endDate = this.startDate;
        }
        this.fillFromRange();
    }

    handleEnd(event) {
        this.endDate = event.target.value || '';
        this.fillFromRange();
    }

    handleCategory(event) {
        this.category = event.detail.value;
        const max = this.maxFor(this.category);
        if (Number(this.hoursPerDay) > max) {
            this.hoursPerDay = max;
        }
        this.rows = this.rows.map((r) => ({
            ...r,
            category: this.category,
            hours: Number(r.hours) > max ? max : r.hours
        }));
        this.serverErrors = {};
    }

    handleHoursPerDay(event) {
        this.hoursPerDay = event.target.value;
        this.rows = this.rows.map((r) => ({ ...r, hours: this.hoursPerDay }));
        this.serverErrors = {};
    }

    handleReason(event) {
        this.reason = event.target.value || '';
    }

    handleWeekends(event) {
        this.includeWeekends = event.target.checked;
        this.fillFromRange();
    }

    handleCellChange(event) {
        const { rowKey, fieldName, value } = event.detail;
        let dateChanged = false;
        this.rows = this.rows.map((r) => {
            if (r.key !== rowKey) {
                return r;
            }
            dateChanged = fieldName === 'date' && r.date !== value;
            return { ...r, [fieldName]: value };
        });
        if (this.serverErrors[rowKey]) {
            const copy = { ...this.serverErrors };
            delete copy[rowKey];
            this.serverErrors = copy;
        }
        if (dateChanged) {
            this.loadRecords();
        }
    }

    handleRowAction(event) {
        const { rowKey, action } = event.detail;
        if (action === 'remove') {
            this.rows = this.rows.filter((r) => r.key !== rowKey);
            if (!this.rows.length) {
                this.rows = [this.blankRow()];
            }
        }
    }

    handleAddRow() {
        this.rows = [...this.rows, this.blankRow()];
    }

    handleClear() {
        this.startDate = '';
        this.endDate = '';
        this.reason = '';
        this.rangeError = undefined;
        this.rows = [this.blankRow()];
        this.records = { leaves: [], lineItems: [] };
        this.serverErrors = {};
        this.showMissing = false;
        this.step = 'setup';
    }

    handleNext() {
        if (!this.employeeId) {
            this.toast('Pick an employee', 'Choose who the leave is for.', 'error');
            return;
        }
        if (this.rangeError) {
            this.toast('Check the dates', this.rangeError, 'error');
            return;
        }
        if (!this.rows.length) {
            this.rows = [this.blankRow()];
        }
        this.step = 'edit';
    }

    handleBackToSetup() {
        this.step = 'setup';
    }

    async handleReview() {
        this.showMissing = true;
        if (!this.employeeId) {
            this.toast('Pick an employee', 'Choose who the leave is for.', 'error');
            return;
        }
        const filled = this.submitRows;
        if (!filled.length) {
            this.toast('Nothing to submit', 'Add at least one day with a date.', 'error');
            return;
        }
        this.rows = filled;
        await this.loadRecords();
        if (this.rangeError) {
            this.toast('Check the dates', this.rangeError, 'error');
            return;
        }
        const checked = this.checkRows();
        const firstError = this.rows.map((r) => checked[r.key]?.error).find((e) => e);
        if (firstError) {
            this.toast('Fix the highlighted rows', firstError, 'error');
            return;
        }
        this.step = 'review';
    }

    handleBack() {
        this.step = 'edit';
    }

    async handleSubmit() {
        const rows = this.submitRows;
        const payload = rows.map((r) => ({
            date: r.date,
            category: r.category,
            hours: Number(r.hours)
        }));
        this.isSubmitting = true;
        try {
            const response = await submitLeave({
                employeeId: this.employeeId,
                rowsJson: JSON.stringify(payload),
                notes: this.reason || ''
            });
            if (!response.success) {
                const errors = {};
                (response.rowErrors || []).forEach((message, index) => {
                    if (message && rows[index]) {
                        errors[rows[index].key] = message;
                    }
                });
                this.serverErrors = errors;
                this.step = 'edit';
                const first = (response.rowErrors || []).find((m) => m) || (response.warnings || [])[0];
                this.toast('Not submitted', first || 'Fix the highlighted rows and try again.', 'error');
                return;
            }
            const days = response.dayCount;
            this.toast('Submitted for approval', `${response.requestName} submitted, ${days} day${days === 1 ? '' : 's'}.`, 'success');
            (response.warnings || []).forEach((w) => this.toast('Note', w, 'warning'));
            this.handleClear();
            this.dispatchEvent(new CustomEvent('changed'));
        } catch (e) {
            this.toast('Not submitted', reduceError(e), 'error');
        } finally {
            this.isSubmitting = false;
        }
    }

    // ------------------------------------------------------------------ data

    fillFromRange() {
        this.serverErrors = {};
        this.rangeError = undefined;
        if (!this.startDate || !this.endDate) {
            this.loadRecords();
            return;
        }
        if (this.startDate < this.today) {
            this.rangeError = 'Pick a start date of today or later.';
            return;
        }
        if (this.endDate < this.startDate) {
            this.rangeError = 'Pick an end date on or after the start date.';
            return;
        }
        const days = daysBetween(this.startDate, this.endDate);
        if (days > MAX_RANGE_DAYS) {
            this.rangeError = `Pick a range of ${MAX_RANGE_DAYS} days or fewer.`;
            return;
        }
        const rows = [];
        for (let i = 0; i <= days; i++) {
            const date = addDays(this.startDate, i);
            const weekday = parseDate(date).getDay();
            if (!this.includeWeekends && (weekday === 0 || weekday === 6)) {
                continue;
            }
            rows.push({ key: newKey(), date, category: this.category, hours: this.hoursPerDay });
        }
        this.rows = rows.length ? rows : [this.blankRow()];
        this.loadRecords();
    }

    get loadRange() {
        const dates = this.rows.map((r) => r.date).filter(Boolean);
        if (this.startDate) {
            dates.push(this.startDate);
        }
        if (this.endDate) {
            dates.push(this.endDate);
        }
        if (!dates.length) {
            return null;
        }
        dates.sort();
        return { start: dates[0], end: dates[dates.length - 1] };
    }

    async loadRecords() {
        const range = this.loadRange;
        if (!this.employeeId || !range) {
            this.records = { leaves: [], lineItems: [] };
            return;
        }
        if (daysBetween(range.start, range.end) > MAX_RANGE_DAYS) {
            this.rangeError = `Keep all days within ${MAX_RANGE_DAYS} days of each other.`;
            return;
        }
        const seq = ++this.loadSeq;
        this.isLoading = true;
        try {
            const result = await getDayRecords({
                employeeId: this.employeeId,
                startDate: range.start,
                endDate: range.end
            });
            if (seq !== this.loadSeq) {
                return;
            }
            const withDate = (list) => (list || []).map((x) => ({ ...x, date: x.leaveDate }));
            this.records = { leaves: withDate(result.leaves), lineItems: withDate(result.lineItems) };
            this.loadedEmployee = result.employee;
            this.rangeError = undefined;
        } catch (e) {
            if (seq === this.loadSeq) {
                this.rangeError = reduceError(e);
            }
        } finally {
            if (seq === this.loadSeq) {
                this.isLoading = false;
            }
        }
    }

    blankRow() {
        return { key: newKey(), date: '', category: this.category, hours: this.hoursPerDay };
    }

    maxFor(category) {
        const c = (this._context?.categories || []).find((x) => x.value === category);
        return c ? Number(c.maxHours) : 8;
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

function parseDate(value) {
    const [y, m, d] = value.split('-').map(Number);
    return new Date(y, m - 1, d);
}

function addDays(value, n) {
    const date = parseDate(value);
    date.setDate(date.getDate() + n);
    return formatYmd(date);
}

// Local yyyy-mm-dd; never toISOString, which shifts the day through UTC.
function formatYmd(date) {
    const mm = String(date.getMonth() + 1).padStart(2, '0');
    const dd = String(date.getDate()).padStart(2, '0');
    return `${date.getFullYear()}-${mm}-${dd}`;
}

function daysBetween(a, b) {
    return Math.round((parseDate(b) - parseDate(a)) / 86400000);
}

function dayName(value) {
    return value ? DAY_NAMES[parseDate(value).getDay()] : '';
}

function firstLine(text) {
    return text ? String(text).split('\n')[0] : '';
}

function formatHours(value) {
    const n = Number(value) || 0;
    return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/0$/, '');
}

function reduceError(e) {
    return e?.body?.message || e?.message || 'Something went wrong.';
}
