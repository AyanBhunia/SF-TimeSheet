import { LightningElement, api, track } from 'lwc';
import getPendingApprovals from '@salesforce/apex/PtoController.getPendingApprovals';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    { fieldName: 'name', label: 'Request', type: 'text', sortable: true, width: '7.5rem' },
    { fieldName: 'employeeName', label: 'Employee', type: 'text', sortable: true },
    { fieldName: 'startDate', label: 'From', type: 'text', sortable: true, width: '6.75rem' },
    { fieldName: 'endDate', label: 'To', type: 'text', sortable: true, width: '6.75rem' },
    { fieldName: 'dayCount', label: 'Days', type: 'number', align: 'right', sortable: true, width: '4.25rem' },
    { fieldName: 'totalHours', label: 'Hours', type: 'number', align: 'right', sortable: true, width: '4.75rem' },
    { fieldName: 'submittedOn', label: 'Submitted', type: 'text', sortable: true, width: '7rem' }
];

/**
 * Requests waiting for this approver, side by side: the list on the left (sortable), the selected
 * request's details and days on the right, where it is approved or rejected as a whole.
 */
export default class PtoApprove extends LightningElement {
    // Request to select on the first load (from an email link).
    @api
    get linkedRequestId() {
        return this._linkedRequestId;
    }
    set linkedRequestId(value) {
        const isChanged = this._linkedRequestId !== value;
        this._linkedRequestId = value;
        if (isChanged && value) {
            this.isLinkApplied = false;
            if (this.isConnected) {
                this.loadPending();
            }
        }
    }
    _linkedRequestId;
    isLinkApplied = false;

    @track records = [];
    @track isLoading = false;
    @track sortedBy = 'startDate';
    @track sortedDirection = 'asc';
    selectedId;

    columns = COLUMNS;
    emptyMessage = 'No leave requests are waiting for your approval.';

    connectedCallback() {
        this.loadPending();
    }

    @api
    refresh() {
        return this.loadPending();
    }

    async loadPending(nextIndex) {
        this.isLoading = true;
        try {
            const result = await getPendingApprovals();
            this.records = Array.isArray(result) ? result : [];
            this.sortData(this.sortedBy, this.sortedDirection);
            if (this.linkedRequestId && !this.isLinkApplied) {
                // A request that isn't waiting for this approver (decided, deleted, wrong Id) is ignored.
                this.isLinkApplied = true;
                const linked = this.records.find((r) => sameId(r.id, this.linkedRequestId));
                if (linked) {
                    this.selectedId = linked.id;
                }
            }
            if (!this.records.some((r) => r.id === this.selectedId)) {
                const index = nextIndex === undefined ? 0 : Math.min(nextIndex, this.records.length - 1);
                this.selectedId = this.records.length ? this.records[index].id : undefined;
            }
        } catch (error) {
            this.records = [];
            this.selectedId = undefined;
            const message = error && error.body && error.body.message
                ? error.body.message
                : 'Pending leave could not load.';
            this.dispatchEvent(new ShowToastEvent({ title: 'Approvals', message, variant: 'error' }));
        } finally {
            this.isLoading = false;
        }
    }

    get tableRows() {
        return this.records.map((r) => ({
            key: r.id,
            name: r.name,
            employeeName: r.employeeName,
            startDate: r.startDate,
            endDate: r.endDate,
            dayCount: r.dayCount,
            totalHours: formatHours(r.totalHours),
            submittedOn: r.submittedOn
        }));
    }

    get isEmpty() {
        return !this.isLoading && this.records.length === 0;
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

    handleSelect(event) {
        this.selectedId = event.detail.rowKey;
    }

    async handleDecided() {
        // Select the request that takes the decided one's place in the list.
        const index = this.records.findIndex((r) => r.id === this.selectedId);
        this.selectedId = undefined;
        await this.loadPending(index < 0 ? 0 : index);
        this.dispatchEvent(new CustomEvent('changed', { bubbles: false }));
    }
}

function formatHours(value) {
    const n = Number(value) || 0;
    return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/0$/, '');
}

function sameId(a, b) {
    return !!a && !!b && a.substring(0, 15) === b.substring(0, 15);
}
