import { LightningElement, api, track } from 'lwc';
import getPendingApprovals from '@salesforce/apex/PtoController.getPendingApprovals';
import approveLeave from '@salesforce/apex/PtoController.approveLeave';
import rejectLeave from '@salesforce/apex/PtoController.rejectLeave';
import PtoConfirmModal from 'c/ptoConfirmModal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    { fieldName: 'employeeName', label: 'Employee', type: 'text', sortable: true },
    { fieldName: 'date', label: 'Date', type: 'date', sortable: true },
    { fieldName: 'category', label: 'Category', type: 'text', sortable: true },
    { fieldName: 'hours', label: 'Hours', type: 'number', align: 'right', sortable: true },
    { fieldName: 'notes', label: 'Notes', type: 'text', sortable: true }
];

const ROW_ACTIONS = [
    { name: 'approve', label: 'Approve', variant: 'success' },
    { name: 'reject', label: 'Reject', variant: 'destructive' }
];

export default class PtoApprove extends LightningElement {
    @track records = [];
    @track isLoading = false;
    @track sortedBy = 'date';
    @track sortedDirection = 'asc';

    columns = COLUMNS;
    rowActions = ROW_ACTIONS;
    emptyMessage = 'No leave is waiting for your approval.';

    connectedCallback() {
        this.loadPending();
    }

    @api
    refresh() {
        return this.loadPending();
    }

    async loadPending() {
        this.isLoading = true;
        try {
            const result = await getPendingApprovals();
            this.records = Array.isArray(result) ? result.map((r) => ({ ...r, date: r.leaveDate })) : [];
            this.sortData(this.sortedBy, this.sortedDirection);
        } catch (error) {
            this.records = [];
            const message = error && error.body && error.body.message
                ? error.body.message
                : 'Pending leave could not load.';
            this.showToast('Approvals', message, 'error');
        } finally {
            this.isLoading = false;
        }
    }

    get tableRows() {
        return this.records.map(r => ({
            key: r.id,
            id: r.id,
            employeeId: r.employeeId,
            employeeName: r.employeeName,
            date: r.date,
            category: r.category,
            hours: r.hours,
            notes: r.notes
        }));
    }

    handleSort(event) {
        const { fieldName, direction } = event.detail;
        this.sortedBy = fieldName;
        this.sortedDirection = direction;
        this.sortData(fieldName, direction);
    }

    sortData(fieldName, direction) {
        if (!fieldName || !this.records || this.records.length === 0) {
            return;
        }
        const isReverse = direction === 'desc' ? -1 : 1;
        this.records = [...this.records].sort((a, b) => {
            let valA = a[fieldName] !== undefined && a[fieldName] !== null ? a[fieldName] : '';
            let valB = b[fieldName] !== undefined && b[fieldName] !== null ? b[fieldName] : '';
            if (typeof valA === 'string') {
                valA = valA.toLowerCase();
            }
            if (typeof valB === 'string') {
                valB = valB.toLowerCase();
            }
            if (valA > valB) {
                return 1 * isReverse;
            }
            if (valA < valB) {
                return -1 * isReverse;
            }
            return 0;
        });
    }

    async handleRowAction(event) {
        const { rowKey, action } = event.detail;
        const row = this.records.find(r => r.id === rowKey);
        if (!row) {
            return;
        }

        const employeeName = row.employeeName || '';
        const leaveDate = row.date || '';
        const category = row.category || '';
        const hours = row.hours !== undefined && row.hours !== null ? row.hours : 0;
        const summary = `${employeeName} · ${leaveDate} · ${category} · ${hours} h`;

        this.lastRow = row;
        const result = await PtoConfirmModal.open({
            size: 'small',
            mode: action,
            summary
        });

        if (result && result.confirmed) {
            if (action === 'approve') {
                await this.executeApprove(row.id);
            } else if (action === 'reject') {
                await this.executeReject(row.id, result.reason);
            }
        }
    }

    async executeApprove(leaveId) {
        this.isLoading = true;
        try {
            const res = await approveLeave({ leaveIds: [leaveId] });
            if (res && res.errors && res.errors.length > 0) {
                this.showToast('Not all approved', res.errors.join('; '), 'warning');
            } else {
                this.showToast('Approved', summaryOf(this.lastRow), 'success');
            }
            this.dispatchEvent(new CustomEvent('changed', { bubbles: false }));
            await this.loadPending();
        } catch (error) {
            const message = error && error.body && error.body.message
                ? error.body.message
                : 'The leave could not be approved.';
            this.showToast('Not approved', message, 'error');
            this.isLoading = false;
        }
    }

    async executeReject(leaveId, reason) {
        this.isLoading = true;
        try {
            const res = await rejectLeave({ leaveIds: [leaveId], reason });
            if (res && res.errors && res.errors.length > 0) {
                this.showToast('Not all rejected', res.errors.join('; '), 'warning');
            } else {
                this.showToast('Rejected', summaryOf(this.lastRow) + '. The reason was added to the notes.', 'success');
            }
            this.dispatchEvent(new CustomEvent('changed', { bubbles: false }));
            await this.loadPending();
        } catch (error) {
            const message = error && error.body && error.body.message
                ? error.body.message
                : 'The leave could not be rejected.';
            this.showToast('Not rejected', message, 'error');
            this.isLoading = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}

function summaryOf(row) {
    return row ? `${row.employeeName}, ${row.category} on ${row.date}` : '';
}
