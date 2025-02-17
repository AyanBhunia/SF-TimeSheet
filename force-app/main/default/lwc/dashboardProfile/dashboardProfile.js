import { LightningElement, api, track, wire } from 'lwc';
import getEmployeeDetails from '@salesforce/apex/GetDashboardProfileDetails.getEmployeeDetails';
import USER_ID from '@salesforce/user/Id';

// LMS imports
import { subscribe, MessageContext } from 'lightning/messageService';
import SELECTED_USER_CHANNEL from '@salesforce/messageChannel/SelectedUserChannel__c';

export default class DashboardProfile extends LightningElement {
    @api showNullFields;
    @api column1Fields;
    @api column2Fields;
    @api column3Fields;
    
    column1Data = [];
    column2Data = [];
    column3Data = [];
    employeeData;

    // LMS
    @wire(MessageContext)
    messageContext;

    subscription = null;
    selectedUserId = USER_ID; // Set to current user by default

    connectedCallback() {
        // Subscribe to the message channel
        this.subscribeToMessageChannel();
        // Fetch employee details when the component is initialized
        this.fetchEmployeeDetails();
    }

    subscribeToMessageChannel() {
        if (this.subscription) {
            return;
        }
        this.subscription = subscribe(
            this.messageContext,
            SELECTED_USER_CHANNEL,
            (message) => this.handleMessage(message)
        );
    }

    handleMessage(message) {
        this.selectedUserId = message.selectedUserId;
        console.log('Received selected user ID:', this.selectedUserId);
        // Fetch employee details for the selected user
        this.fetchEmployeeDetails();
    }

    fetchEmployeeDetails() {
        getEmployeeDetails({ userID: this.selectedUserId })
            .then((data) => {
                console.log('Employee Data:', data);
                this.employeeData = data;
                this.processFieldOrder();
            })
            .catch((error) => {
                console.error('Error fetching employee data:', error);
            });
    }

    processFieldOrder() {
        if (this.employeeData) {
            if (this.column1Fields) {
                this.column1Data = this.processColumnFields(this.column1Fields);
            }
            if (this.column2Fields) {
                this.column2Data = this.processColumnFields(this.column2Fields);
            }
            if (this.column3Fields) {
                this.column3Data = this.processColumnFields(this.column3Fields);
            }
        }
    }

    processColumnFields(fieldString) {
        let fields = fieldString.split(',').map(field => field.trim());
        
        if (!this.showNullFields) {
            fields = fields.filter(field => this.employeeData[field] != null);
        }
        
        return fields.map(field => ({
            label: field.replace(/([A-Z])/g, ' $1').trim(),
            value: this.employeeData[field] ?? 'N/A'
        }));
    }
}

// Name, ClientManager, ClientManagerEmail, Projects, TotalBillableHours, TotalNonBillableHours, TotalAbsenceHours, TotalHours
// Name, ClientManager, Projects, TotalBillableHours, TotalNonBillableHours, TotalHours, TotalAbsenceHours