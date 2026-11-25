import { LightningElement, api, wire, track } from 'lwc';
import getRelatedTimesheets from '@salesforce/apex/TimesheetLineItemController.getTimesheetLineItems';

const columns = [
    {
        label: 'Name', fieldName: 'nameUrl', type: 'url', typeAttributes: {
            label: { fieldName: 'Name' },
            target: '_blank'
        }
    },
    { label: 'Type', fieldName: 'dbt__Type__c', type: 'text' },
    { label: 'Date', fieldName: 'dbt__Date__c', type: 'date' },
    { label: 'Duration', fieldName: 'dbt__Duration__c', type: 'number' },
    {
        label: 'Project', fieldName: 'projectUrl', type: 'url', typeAttributes: {
            label: { fieldName: 'projectName' },
            target: '_blank'
        }
    },
    { label: 'Absence Category', fieldName: 'dbt__Absence_Category__c', type: 'text' }
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
                const projId = row.dbt__Project__c || row.Project__c;
                const projRel = row.dbt__Project__r || row.Project__r;
                if (projId != null) {
                    projectUrl = `/${projId}`;
                    projectName = projRel ? projRel.Name : null;
                } else {
                    projectUrl = null;
                    projectName = null;
                }
                const typeVal = row.dbt__Type__c || row.Type__c;
                const dateVal = row.dbt__Date__c || row.Date__c;
                const durVal = row.dbt__Duration__c != null ? row.dbt__Duration__c : row.Duration__c;
                const absVal = row.dbt__Absence_Category__c || row.Absence_Category__c;
                return {
                    ...row,
                    dbt__Type__c: typeVal,
                    Type__c: typeVal,
                    dbt__Date__c: dateVal,
                    Date__c: dateVal,
                    dbt__Duration__c: durVal,
                    Duration__c: durVal,
                    dbt__Absence_Category__c: absVal,
                    Absence_Category__c: absVal,
                    nameUrl,
                    projectUrl,
                    projectName
                };
            })
            this.error = null;
        } else {
            this.error = error;
            this.timesheets = undefined;
        }
    }
}