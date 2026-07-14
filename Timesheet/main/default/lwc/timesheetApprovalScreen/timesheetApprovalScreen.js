import { LightningElement, track } from 'lwc';
import getTimesheetData from '@salesforce/apex/TimesheetApprovalController.getTimesheetData';
import approveTimesheets from '@salesforce/apex/TimesheetApprovalController.approveTimesheets';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    { label: 'Employee Name', fieldName: 'employeeName', sortable: true },
    { label: 'Project / Type', fieldName: 'projectName', sortable: true },
    { label: 'Period', fieldName: 'timesheetPeriod', sortable: true },
    { label: 'Total Duration', fieldName: 'duration', type: 'number', sortable: true },
    {
        type: 'button-icon',
        typeAttributes: {
            iconName: 'utility:chevronright',
            name: 'view_details',
            title: 'View Details',
            variant: 'border-filled',
            alternativeText: 'View Details'
        }
    }
];

const LINE_ITEM_COLUMNS = [
    { label: 'Date', fieldName: 'Date__c', type: 'date' },
    { label: 'Type', fieldName: 'Type__c' },
    { label: 'Duration', fieldName: 'Duration__c', type: 'number' },
    { label: 'Description', fieldName: 'Description__c' }
];

export default class TimesheetApprovalScreen extends LightningElement {
    @track dateRange = 'Current Week';
    @track timesheets = [];
    @track columns = COLUMNS;
    @track lineItemColumns = LINE_ITEM_COLUMNS;
    @track isModalOpen = false;
    @track selectedLineItems = [];
    @track projectSummaries = [];
    @track sortBy;
    @track sortDirection;
    
    @track customStartDate;
    @track customEndDate;
    
    selectedTimesheetIds = [];
    
    get isCustomDate() {
        return this.dateRange === 'Custom';
    }
    
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
    
    connectedCallback() {
        this.fetchData();
    }
    
    handleDateRangeChange(event) {
        this.dateRange = event.detail.value;
        if (this.dateRange !== 'Custom') {
            this.fetchData();
        }
    }
    
    handleCustomDateChange(event) {
        const fieldName = event.target.name;
        if (fieldName === 'startDate') {
            this.customStartDate = event.detail.value;
        } else if (fieldName === 'endDate') {
            this.customEndDate = event.detail.value;
        }
        
        if (this.customStartDate && this.customEndDate) {
            this.fetchData();
        }
    }
    
    fetchData() {
        getTimesheetData({ 
            dateRange: this.dateRange, 
            customStartDate: this.customStartDate, 
            customEndDate: this.customEndDate 
        })
            .then(result => {
                this.timesheets = result;
                this.calculateProjectSummaries();
            })
            .catch(error => {
                this.showToast('Error', error.body ? error.body.message : error.message, 'error');
            });
    }
    
    calculateProjectSummaries() {
        let summaries = {};
        this.timesheets.forEach(ts => {
            if (!summaries[ts.projectName]) {
                summaries[ts.projectName] = 0;
            }
            summaries[ts.projectName] += ts.duration;
        });
        
        this.projectSummaries = Object.keys(summaries).map(key => ({
            id: key,
            projectName: key,
            totalDuration: summaries[key]
        }));
    }
    
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        if (actionName === 'view_details') {
            this.selectedLineItems = row.lineItems.map(item => {
                return {
                    Id: item.Id,
                    Date__c: item.Date__c || item.dbt__Date__c,
                    Type__c: item.Type__c || item.dbt__Type__c,
                    Duration__c: item.Duration__c || item.dbt__Duration__c,
                    Description__c: item.Description__c || item.dbt__Description__c
                };
            });
            this.isModalOpen = true;
        }
    }
    
    closeModal() {
        this.isModalOpen = false;
        this.selectedLineItems = [];
    }
    
    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedTimesheetIds = selectedRows.map(row => row.timesheetId);
    }
    
    handleApprove() {
        if (this.selectedTimesheetIds.length === 0) {
            this.showToast('Warning', 'Please select at least one row to approve.', 'warning');
            return;
        }
        
        approveTimesheets({ timesheetIds: this.selectedTimesheetIds })
            .then(() => {
                this.showToast('Success', 'Timesheets approved successfully.', 'success');
                this.fetchData(); 
            })
            .catch(error => {
                this.showToast('Error', error.body ? error.body.message : error.message, 'error');
            });
    }
    
    handleSort(event) {
        this.sortBy = event.detail.fieldName;
        this.sortDirection = event.detail.sortDirection;
        this.sortData(this.sortBy, this.sortDirection);
    }
    
    sortData(fieldname, direction) {
        let parseData = JSON.parse(JSON.stringify(this.timesheets));
        let keyValue = (a) => {
            return a[fieldname];
        };
        let isReverse = direction === 'asc' ? 1: -1;
        parseData.sort((x, y) => {
            x = keyValue(x) ? keyValue(x) : '';
            y = keyValue(y) ? keyValue(y) : '';
            return isReverse * ((x > y) - (y > x));
        });
        this.timesheets = parseData;
    }
    
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
}