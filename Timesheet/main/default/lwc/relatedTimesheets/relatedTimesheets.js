import { LightningElement, api, wire, track } from 'lwc';
import getRelatedTimesheets from '@salesforce/apex/TimesheetLineItemController.getTimesheetLineItems';

const columns = [
    {
        label: 'Name', fieldName: 'nameUrl', type: 'url', typeAttributes: {
            label: { fieldName: 'Name' },
            target: '_blank'
        }
    },
    { label: 'Type', fieldName: 'Type__c', type: 'text' },
    { label: 'Date', fieldName: 'Date__c', type: 'date' },
    { label: 'Duration', fieldName: 'Duration__c', type: 'number' },
    {
        label: 'Project', fieldName: 'projectUrl', type: 'url', typeAttributes: {
            label: { fieldName: 'projectName' },
            target: '_blank'
        }
    },
    { label: 'Absence Category', fieldName: 'Absence_Category__c', type: 'text' }
];

export default class RelatedTimesheets extends LightningElement {
    @api recordId;
    @track timesheets;
    columns = columns;

    @wire(getRelatedTimesheets, { ProcessInstanceWorkItemId: '$recordId' })
    WireTimesheetRecords({ error, data }) {
        if (data) {
            let nameUrl;
            let projectUrl;
            let projectName;
            this.timesheets = data.map(row => {

                nameUrl = `/${row.Id}`;
                if (row.Project__c != null) {
                    projectUrl = `/${row.Project__c}`;
                    projectName = row.Project__r.Name;
                } else {
                    projectUrl = null;
                    projectName = null;
                }
                return { ...row, nameUrl, projectUrl, projectName }
            })
            this.error = null;
        } else {
            this.error = error;
            this.timesheets = undefined;
        }
    }
}