import { LightningElement, api, track } from 'lwc';
import getPast from '@salesforce/apex/PtoController.getPast';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const PAGE_SIZE = 25;

const COLUMNS = [
    { fieldName: 'date', label: 'Date', type: 'date' },
    { fieldName: 'type', label: 'Type', type: 'text' },
    { fieldName: 'category', label: 'Category', type: 'text' },
    { fieldName: 'hours', label: 'Hours', type: 'number', align: 'right' },
    { fieldName: 'displayStatus', label: 'Status', type: 'status' },
    { fieldName: 'notes', label: 'Notes', type: 'text' }
];

export default class PtoPast extends LightningElement {
    @track records = [];
    @track isLoading = false;
    @track pageNumber = 1;
    @track offset = 0;
    @track hasMore = false;

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
        } catch (error) {
            this.records = [];
            this.hasMore = false;
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

    get tableRows() {
        return this.records.map(r => ({
            key: r.id,
            id: r.id,
            date: r.leaveDate,
            type: r.type,
            category: r.category,
            hours: r.hours,
            displayStatus: r.displayStatus,
            notes: r.notes
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
            return 'No records';
        }
        const start = this.offset + 1;
        const end = this.offset + this.records.length;
        return `Showing ${start} to ${end}`;
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
