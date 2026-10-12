import { LightningElement, api, track } from 'lwc';
import getPast from '@salesforce/apex/PtoController.getPast';
import getRequestLines from '@salesforce/apex/PtoController.getRequestLines';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const PAGE_SIZE = 25;

const COLUMNS = [
    { fieldName: 'name', label: 'Request', type: 'text', width: '7.5rem' },
    { fieldName: 'startDate', label: 'From', type: 'text', width: '6.75rem' },
    { fieldName: 'endDate', label: 'To', type: 'text', width: '6.75rem' },
    { fieldName: 'dayCount', label: 'Days', type: 'number', align: 'right', width: '3.75rem' },
    { fieldName: 'totalHours', label: 'Hours', type: 'number', align: 'right', width: '4.25rem' },
    { fieldName: 'displayStatus', label: 'Status', type: 'status' }
];

/**
 * Past requests, side by side: the employee's requests on the left (25 per page), the selected
 * request's details and days on the right.
 */
export default class PtoPast extends LightningElement {
    @api canRetry = false;
    @api context;
    // Request to select on the first load (from an email link), even when it isn't on this page.
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
                this.loadData();
            }
        }
    }
    _linkedRequestId;

    @track records = [];
    @track isLoading = false;
    @track pageNumber = 1;
    @track offset = 0;
    @track hasMore = false;
    selectedId;
    isLinkApplied = false;

    columns = COLUMNS;
    _employeeId;

    @api
    get employeeId() {
        return this._employeeId;
    }
    set employeeId(value) {
        const isChanged = this._employeeId !== value;
        this._employeeId = value;
        if (isChanged && this.isConnected) {
            this.pageNumber = 1;
            this.offset = 0;
            this.selectedId = undefined;
            this.loadData();
        }
    }

    connectedCallback() {
        this.loadData();
    }

    @api
    refresh() {
        this.pageNumber = 1;
        this.offset = 0;
        return this.loadData();
    }

    async loadData() {
        this.isLoading = true;
        try {
            const page = await getPast({
                employeeId: this.employeeId,
                offsetRows: this.offset
            });
            this.records = page && Array.isArray(page.rows) ? page.rows : [];
            this.hasMore = Boolean(page && page.hasMore);
            const linkedId = await this.resolveLinkedRequest();
            if (linkedId) {
                this.selectedId = linkedId;
            } else if (!this.records.some((r) => r.id === this.selectedId)) {
                this.selectedId = this.records.length ? this.records[0].id : undefined;
            }
        } catch (error) {
            this.records = [];
            this.hasMore = false;
            this.selectedId = undefined;
            const message = error && error.body && error.body.message
                ? error.body.message
                : 'Past leave could not load.';
            this.dispatchEvent(new ShowToastEvent({
                title: 'Past leave',
                message,
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    // The linked request's Id if this user can see it, otherwise undefined (deleted, no access, wrong Id), so the
    // tab opens as usual. Applied once per link.
    async resolveLinkedRequest() {
        if (!this.linkedRequestId || this.isLinkApplied) {
            return undefined;
        }
        this.isLinkApplied = true;
        const listed = this.records.find((r) => sameId(r.id, this.linkedRequestId));
        if (listed) {
            return listed.id;
        }
        try {
            const detail = await getRequestLines({ requestId: this.linkedRequestId });
            return detail?.request?.id;
        } catch (e) {
            return undefined;
        }
    }

    get canPickEmployee() {
        return (this.context?.employees || []).length > 0;
    }

    get employeeOptions() {
        const options = [];
        const self = this.context?.employee;
        if (self) {
            options.push({ label: `Me (${self.name})`, value: self.id });
        }
        (this.context?.employees || []).forEach((e) => options.push({ label: e.name, value: e.id }));
        return options;
    }

    handleEmployee(event) {
        if (event.detail.value === this._employeeId) {
            return;
        }
        this._employeeId = event.detail.value;
        this.pageNumber = 1;
        this.offset = 0;
        this.selectedId = undefined;
        this.loadData();
    }

    get tableRows() {
        return this.records.map((r) => ({
            key: r.id,
            name: r.name,
            startDate: r.startDate,
            endDate: r.endDate,
            dayCount: r.dayCount,
            totalHours: formatHours(r.totalHours),
            displayStatus: r.displayStatus
        }));
    }

    get isPreviousDisabled() {
        return this.pageNumber <= 1 || this.isLoading;
    }

    get isNextDisabled() {
        return !this.hasMore || this.isLoading;
    }

    get pageText() {
        return `Page ${this.pageNumber}`;
    }

    get showingText() {
        if (!this.records || this.records.length === 0) {
            return 'No requests';
        }
        const start = this.offset + 1;
        const end = this.offset + this.records.length;
        return `Showing ${start} to ${end}`;
    }

    handleSelect(event) {
        this.selectedId = event.detail.rowKey;
    }

    handleDecided() {
        // A retry changes the request's status label; reload the page and keep the selection.
        this.loadData();
    }

    handlePrevious() {
        if (this.pageNumber > 1) {
            this.pageNumber -= 1;
            this.offset = (this.pageNumber - 1) * PAGE_SIZE;
            this.loadData();
        }
    }

    handleNext() {
        if (this.hasMore) {
            this.pageNumber += 1;
            this.offset = (this.pageNumber - 1) * PAGE_SIZE;
            this.loadData();
        }
    }
}

function formatHours(value) {
    const n = Number(value) || 0;
    return Number.isInteger(n) ? String(n) : n.toFixed(2).replace(/0$/, '');
}

function sameId(a, b) {
    return !!a && !!b && a.substring(0, 15) === b.substring(0, 15);
}
