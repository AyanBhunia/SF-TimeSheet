import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getRequestLines from '@salesforce/apex/PtoController.getRequestLines';
import approveRequests from '@salesforce/apex/PtoController.approveRequests';
import rejectRequests from '@salesforce/apex/PtoController.rejectRequests';
import retrySync from '@salesforce/apex/PtoController.retrySync';
import PtoConfirmModal from 'c/ptoConfirmModal';

const DAY_NAMES = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

const STATUS_BADGE = {
    Submitted: 'slds-badge badge-submitted',
    Approved: 'slds-badge badge-approved',
    Rejected: 'slds-badge badge-rejected',
    'Approved, sync error': 'slds-badge badge-rejected'
};

/**
 * Right-hand pane of Past and Approve: one request's details and its leave days.
 * mode 'approve' adds Approve / Reject; mode 'past' with canRetry adds Retry timesheet sync.
 */
export default class PtoRequestDetail extends LightningElement {
    @api mode = 'past';
    @api canRetry = false;

    detail;
    error;
    isLoading = false;
    isWorking = false;
    _requestId;
    loadSeq = 0;

    @api
    get requestId() {
        return this._requestId;
    }
    set requestId(value) {
        const changed = this._requestId !== value;
        this._requestId = value;
        if (changed) {
            this.load();
        }
    }

    @api
    refresh() {
        return this.load();
    }

    async load() {
        const seq = ++this.loadSeq;
        this.error = undefined;
        if (!this._requestId) {
            this.detail = undefined;
            this.isLoading = false;
            return;
        }
        this.isLoading = true;
        try {
            const result = await getRequestLines({ requestId: this._requestId });
            if (seq === this.loadSeq) {
                this.detail = result;
            }
        } catch (e) {
            if (seq === this.loadSeq) {
                this.detail = undefined;
                this.error = reduceError(e);
            }
        } finally {
            if (seq === this.loadSeq) {
                this.isLoading = false;
            }
        }
    }

    // ------------------------------------------------------------------ view

    get request() {
        return this.detail?.request;
    }

    get hasRequest() {
        return !!this.request;
    }

    get showEmpty() {
        return !this._requestId && !this.error;
    }

    get statusBadgeClass() {
        return STATUS_BADGE[this.request?.displayStatus] || 'slds-badge';
    }

    get summaryLine() {
        const r = this.request;
        if (!r) {
            return '';
        }
        const parts = [];
        if (r.employeeName) {
            parts.push(r.employeeName);
        }
        if (r.startDate) {
            parts.push(r.startDate === r.endDate ? r.startDate : `${r.startDate} to ${r.endDate}`);
        }
        parts.push(`${r.dayCount} day${r.dayCount === 1 ? '' : 's'}`);
        parts.push(`${formatHours(r.totalHours)} h`);
        return parts.join(' · ');
    }

    get approverText() {
        const r = this.request;
        if (!r) {
            return '';
        }
        return r.hasManager ? r.approverName || '' : 'No manager, waiting for HR';
    }

    get approverClass() {
        return this.request && !this.request.hasManager ? 'slds-text-color_error' : '';
    }

    get reasonText() {
        return this.request?.notes || '—';
    }

    get hasDecision() {
        return !!this.request?.decisionNotes;
    }

    get isApproveMode() {
        return this.mode === 'approve' && this.request?.status === 'Submitted';
    }

    get showRetry() {
        return this.mode === 'past' && this.canRetry && this.request?.status === 'Approved' && this.request.syncErrorCount > 0;
    }

    get isRejected() {
        return this.request?.status === 'Rejected';
    }

    get showSync() {
        return this.request?.status === 'Approved';
    }

    get hasLineErrors() {
        return (this.detail?.lines || []).some((l) => l.syncError);
    }

    get lineColumns() {
        const cols = [
            { fieldName: 'date', label: 'Date', type: 'text', width: '7.5rem' },
            { fieldName: 'day', label: 'Day', type: 'text', width: '3.5rem' },
            { fieldName: 'category', label: 'Category', type: 'text' },
            { fieldName: 'hours', label: 'Hours', type: 'number', align: 'right', width: '4.5rem' }
        ];
        if (this.showSync) {
            cols.push({ fieldName: 'syncStatus', label: 'Timesheet', type: 'status', width: '10rem' });
        }
        return cols;
    }

    get lineRows() {
        return (this.detail?.lines || []).map((l) => ({
            key: l.id,
            date: l.leaveDate,
            day: dayName(l.leaveDate),
            category: l.category,
            hours: formatHours(l.hours),
            syncStatus: l.syncStatus,
            error: this.showSync && l.syncError ? l.syncError : undefined
        }));
    }

    // ------------------------------------------------------------------ actions

    handleApprove() {
        this.decide('approve');
    }

    handleReject() {
        this.decide('reject');
    }

    async decide(action) {
        const r = this.request;
        if (!r) {
            return;
        }
        const result = await PtoConfirmModal.open({
            size: 'small',
            mode: action,
            summary: `${r.name} · ${this.summaryLine}`
        });
        if (!result || !result.confirmed) {
            return;
        }
        this.isWorking = true;
        try {
            const res = action === 'approve'
                ? await approveRequests({ requestIds: [r.id] })
                : await rejectRequests({ requestIds: [r.id], reason: result.reason });
            if (res.errors && res.errors.length) {
                this.toast(action === 'approve' ? 'Not approved' : 'Not rejected', res.errors.join(' '), 'error');
            } else if (action === 'approve') {
                this.toast('Approved', `${r.name} for ${r.employeeName} is approved.`, 'success');
            } else {
                this.toast('Rejected', `${r.name} for ${r.employeeName} is rejected. The reason is shown to the employee.`, 'success');
            }
            if (res.syncErrors && res.syncErrors.length) {
                this.toast('Some days are not on the timesheet', res.syncErrors.join(' '), 'warning');
            }
            this.dispatchEvent(new CustomEvent('decided', { detail: { requestId: r.id } }));
        } catch (e) {
            this.toast(action === 'approve' ? 'Not approved' : 'Not rejected', reduceError(e), 'error');
        } finally {
            this.isWorking = false;
        }
    }

    async handleRetry() {
        const r = this.request;
        this.isWorking = true;
        try {
            const res = await retrySync({ requestId: r.id });
            if (res.syncErrors && res.syncErrors.length) {
                this.toast('Still not on the timesheet', res.syncErrors.join(' '), 'warning');
            } else {
                this.toast('Added to the timesheet', `Every day of ${r.name} that has a timesheet is on it now.`, 'success');
            }
            await this.load();
            this.dispatchEvent(new CustomEvent('decided', { detail: { requestId: r.id } }));
        } catch (e) {
            this.toast('Retry failed', reduceError(e), 'error');
        } finally {
            this.isWorking = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

function dayName(value) {
    if (!value) {
        return '';
    }
    const [y, m, d] = value.split('-').map(Number);
    return DAY_NAMES[new Date(y, m - 1, d).getDay()];
}

function formatHours(value) {
    const n = Number(value) || 0;
    return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/0$/, '');
}

function reduceError(e) {
    return e?.body?.message || e?.message || 'Something went wrong.';
}
