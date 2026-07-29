import { LightningElement, track } from 'lwc';
import getTimesheetData from '@salesforce/apex/TimesheetApprovalController.getTimesheetData';
import approveTimesheets from '@salesforce/apex/TimesheetApprovalController.approveTimesheets';
import approveLineItems from '@salesforce/apex/TimesheetApprovalController.approveLineItems';
import rejectLineItemsWithNotes from '@salesforce/apex/TimesheetApprovalController.rejectLineItemsWithNotes';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

const COLUMNS = [
    { 
        label: 'Timesheet', 
        fieldName: 'timesheetName',
        type: 'button', 
        sortable: true,
        typeAttributes: { 
            label: { fieldName: 'timesheetName' }, 
            name: 'timesheet_action', 
            variant: 'base',
            iconName: 'utility:chevronright',
            iconPosition: 'right'
        } 
    },
    { 
        label: 'Project', 
        fieldName: 'projectName',
        type: 'button', 
        sortable: true,
        typeAttributes: { 
            label: { fieldName: 'projectName' }, 
            name: 'project_action', 
            variant: 'base',
            iconName: 'utility:chevronright',
            iconPosition: 'right'
        } 
    },
    { 
        label: 'Employee', 
        fieldName: 'employeeName',
        type: 'button', 
        sortable: true,
        typeAttributes: { 
            label: { fieldName: 'employeeName' }, 
            name: 'employee_action', 
            variant: 'base',
            iconName: 'utility:chevronright',
            iconPosition: 'right'
        } 
    },
    { label: 'Cumulative Duration', fieldName: 'duration', type: 'number', sortable: true }
];

export default class TimesheetApprovalScreen extends LightningElement {
    @track dateRange = 'Current Week';
    @track timesheets = [];
    @track columns = COLUMNS;
    @track isModalOpen = false;
    @track popupColumns = [];
    @track popupData = [];
    @track popupTitle = '';
    @track projectSummaries = [];
    @track sortBy;
    @track sortDirection;
    @track isEmployeePopup = false;
    @track rejectionNoteInput = '';
    selectedPopupRowIds = [];

    get hidePopupCheckboxes() {
        return !this.isEmployeePopup;
    }
    
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
        
        if (actionName === 'timesheet_action') {
            this.isEmployeePopup = false;
            let billable = 0;
            let nonBillable = 0;
            let absence = 0;
            let employees = new Set();
            
            this.timesheets.forEach(ts => {
                if (ts.timesheetId === row.timesheetId) {
                    employees.add(ts.employeeName);
                    if (ts.lineItems) {
                        ts.lineItems.forEach(line => {
                            let dur = line.Duration__c || line.dbt__Duration__c || 0;
                            let type = line.Type__c || line.dbt__Type__c;
                            let isBill = line.Billable__c || line.dbt__Billable__c;
                            
                            if (type === 'Absence') {
                                absence += dur;
                            } else if (isBill === 'Yes') {
                                billable += dur;
                            } else {
                                nonBillable += dur;
                            }
                        });
                    }
                }
            });
            
            this.popupColumns = [
                { label: 'Category', fieldName: 'label' },
                { label: 'Value', fieldName: 'value' }
            ];
            
            this.popupData = [
                { id: '1', label: 'Total Billable project', value: billable },
                { id: '2', label: 'Total non-billable project', value: nonBillable },
                { id: '3', label: 'Total absence hours', value: absence },
                { id: '4', label: 'Total Number of employee', value: employees.size }
            ];
            this.popupTitle = 'Timesheet Details - ' + row.timesheetName;
            this.isModalOpen = true;
            
        } else if (actionName === 'project_action') {
            this.isEmployeePopup = false;
            let employeeDurations = {};
            this.timesheets.forEach(ts => {
                if (ts.projectName === row.projectName) {
                    if (!employeeDurations[ts.employeeName]) {
                        employeeDurations[ts.employeeName] = 0;
                    }
                    employeeDurations[ts.employeeName] += ts.duration;
                }
            });
            
            this.popupColumns = [
                { label: 'Employee Name', fieldName: 'empName' },
                { label: 'Total Duration', fieldName: 'totalDuration', type: 'number' }
            ];
            
            this.popupData = Object.keys(employeeDurations).map((emp, index) => {
                return { id: String(index), empName: emp, totalDuration: employeeDurations[emp] };
            });
            this.popupTitle = 'Project Details - ' + row.projectName;
            this.isModalOpen = true;
            
        } else if (actionName === 'employee_action') {
            this.isEmployeePopup = true;
            this.rejectionNoteInput = '';
            this.selectedPopupRowIds = [];
            this.popupColumns = [
                { label: 'Date', fieldName: 'Date__c', type: 'date' },
                { label: 'Type', fieldName: 'Type__c' },
                { label: 'Duration', fieldName: 'Duration__c', type: 'number' },
                { label: 'Description', fieldName: 'Description__c' },
                { label: 'Status', fieldName: 'Line_Item_Status__c' },
                { label: 'Rejection Notes', fieldName: 'Rejection_Notes__c' }
            ];
            
            this.popupData = row.lineItems ? row.lineItems.map((item, index) => {
                return {
                    id: item.Id || String(index),
                    Date__c: item.Date__c || item.dbt__Date__c,
                    Type__c: item.Type__c || item.dbt__Type__c,
                    Duration__c: item.Duration__c || item.dbt__Duration__c,
                    Description__c: item.Description__c || item.dbt__Description__c,
                    Line_Item_Status__c: item.Line_Item_Status__c || item.dbt__Line_Item_Status__c || 'New',
                    Rejection_Notes__c: item.Rejection_Notes__c || item.dbt__Rejection_Notes__c || ''
                };
            }) : [];
            this.popupTitle = 'Employee Details - ' + row.employeeName;
            this.isModalOpen = true;
        }
    }
    
    closeModal() {
        this.isModalOpen = false;
        this.popupData = [];
    }
    
    handlePopupRowSelection(event) {
        this.selectedPopupRowIds = event.detail.selectedRows.map(row => row.id).filter(id => id && id.length > 5);
    }

    handleRejectionNoteChange(event) {
        this.rejectionNoteInput = event.target.value;
    }

    handleApproveLineItems() {
        if (!this.selectedPopupRowIds || this.selectedPopupRowIds.length === 0) {
            this.showToast('Warning', 'Please select at least one line item to approve.', 'warning');
            return;
        }
        approveLineItems({ lineItemIds: this.selectedPopupRowIds })
            .then(() => {
                this.showToast('Success', 'Selected line items approved successfully.', 'success');
                this.closeModal();
                this.fetchData();
            })
            .catch(error => {
                this.showToast('Error', error.body ? error.body.message : error.message, 'error');
            });
    }

    handleRejectLineItems() {
        if (!this.selectedPopupRowIds || this.selectedPopupRowIds.length === 0) {
            this.showToast('Warning', 'Please select at least one line item to reject.', 'warning');
            return;
        }
        if (!this.rejectionNoteInput || !this.rejectionNoteInput.trim()) {
            this.showToast('Warning', 'Please provide a reason in Rejection Note before rejecting.', 'warning');
            return;
        }
        rejectLineItemsWithNotes({ lineItemIds: this.selectedPopupRowIds, rejectionNotes: this.rejectionNoteInput.trim() })
            .then(() => {
                this.showToast('Success', 'Selected line items rejected with notes.', 'success');
                this.closeModal();
                this.fetchData();
            })
            .catch(error => {
                this.showToast('Error', error.body ? error.body.message : error.message, 'error');
            });
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