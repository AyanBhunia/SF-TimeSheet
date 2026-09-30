/**
 * @file dashboardProfile.js
 * @description LWC for displaying employee dashboard profile with configurable columns
 */

import { LightningElement, api, track, wire } from 'lwc';
import getEmployeeDetails from '@salesforce/apex/GetDashboardProfileDetails.getEmployeeDetails';
import getProfileConfig from '@salesforce/apex/GetDashboardProfileDetails.getProfileConfig';
import updateDashboardProfileConfigAsync from '@salesforce/apex/GetDashboardProfileDetails.updateDashboardProfileConfigAsync';
import hasHrAdminPermission from '@salesforce/apex/GetDashboardProfileDetails.hasHrAdminPermission';
import USER_ID from '@salesforce/user/Id';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

// LMS imports for handling user selection across components
import { subscribe, MessageContext } from 'lightning/messageService';
import SELECTED_USER_CHANNEL from '@salesforce/messageChannel/UserChannel__c';

export default class dashboardProfile extends LightningElement {
    // Property for App Builder help text
    @api configHelp;

    // Legacy properties required for package compatibility (Not used in logic)
    @api showNullFields;
    @api column1Fields;
    @api column2Fields;
    @api column3Fields;

    // Internal Configuration properties from Custom Metadata
    _showNullFields;     // Controls visibility of null field values
    _column1Fields;      // Comma-separated list of fields for first column
    _column2Fields;      // Comma-separated list of fields for second column
    _column3Fields;      // Comma-separated list of fields for third column
    
    // Private properties for data storage
    column1Data = [];        // Processed data for first column
    column2Data = [];        // Processed data for second column
    column3Data = [];        // Processed data for third column
    employeeData;            // Raw employee data
    isMismatch = false;      // Controls visibility of the update labels button

    // Lightning Message Service configuration
    @wire(MessageContext)
    messageContext;

    subscription = null;
    selectedUserId = USER_ID; // Initialize with current user's ID
    hasAdminPermission = false;

    @wire(hasHrAdminPermission)
    wiredAdminPermission({ error, data }) {
        if (data) {
            this.hasAdminPermission = data;
        } else if (error) {
            console.error('Error checking admin permission', error);
        }
    }

    get showResetButton() {
        return this.isMismatch && this.hasAdminPermission;
    }

    // Map for field help texts
    fieldHelpTexts = {
        'TotalEmpAccruedHours': 'Approved accrued hours from Employee record',
        'TotalEmpAbsenceHours': 'Approved absence hours from Employee record',
        'TotalAbsenceHoursAvailable': 'Available absence hours from Employee record',
        'AllBillableHours': 'Billable hours from every timesheets for the current year',
        'AllNonBillableHours': 'Non-billable hours from every timesheets for the current year',
        'AllAbsenceHours': 'Absence hours from every timesheets for the current year',
        'AllHours': 'Total Hours from every timesheets for the current year',
        'VacationsTaken': 'Number of vacations taken for the current year excluding Holidays'
    };

    // Fetch configuration from Custom Metadata
    @wire(getProfileConfig)
    wiredConfig({ error, data }) {
        if (data) {
            this._column1Fields = data.dbt__Column_1_Fields__c;
            this._column2Fields = data.dbt__Column_2_Fields__c;
            this._column3Fields = data.dbt__Column_3_Fields__c;
            this._showNullFields = data.dbt__Show_Null_Fields__c;
            this.checkMismatch();
            this.processFieldOrder();
        } else if (error) {
            console.error('Error loading profile config', error);
        }
    }

    checkMismatch() {
        const validWords = [
            'Name', 'PhoneNumber', 'Email', 'HireDate', 'LastWorkingDate',
            'ClientManager', 'ClientManagerEmail', 'Projects',
            'TotalEmpAccruedHours', 'TotalEmpAbsenceHours', 'TotalAbsenceHoursAvailable',
            'AllBillableHours', 'AllNonBillableHours', 'AllAbsenceHours', 'AllHours', 'VacationsTaken'
        ];

        let currentWords = [];
        if (this._column1Fields) {
            currentWords = currentWords.concat(this._column1Fields.split(',').map(w => w.trim()).filter(w => w));
        }
        if (this._column2Fields) {
            currentWords = currentWords.concat(this._column2Fields.split(',').map(w => w.trim()).filter(w => w));
        }
        if (this._column3Fields) {
            currentWords = currentWords.concat(this._column3Fields.split(',').map(w => w.trim()).filter(w => w));
        }

        this.isMismatch = currentWords.some(word => !validWords.includes(word));
    }

    /**
     * @description Lifecycle hook when component is inserted into the DOM
     */
    connectedCallback() {
        this.subscribeToMessageChannel();
        this.fetchEmployeeDetails();
    }

    showToast(title, message, variant) {
        const evt = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant,
        });
        this.dispatchEvent(evt);
    }

    /**
     * @description Subscribes to LMS channel for user selection updates
     */
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

    /**
     * @description Handles incoming LMS messages
     * @param {Object} message - Message containing selected user ID
     */
    handleMessage(message) {
        this.selectedUserId = message.selectedUserId;
        this.fetchEmployeeDetails();
    }

    /**
     * @description Fetches employee details from the server
     */
    fetchEmployeeDetails() {
        getEmployeeDetails({ userID: this.selectedUserId })
            .then((data) => {
                this.employeeData = data;
                this.processFieldOrder();
            })
            .catch((error) => {
                this.showToast('Error', "Error fetching employee details", 'error');
                console.log('Error fetching employee details',error);
            });
    }

    /**
     * @description Processes field ordering for all columns
     */
    processFieldOrder() {
        if (this.employeeData) {
            if (this._column1Fields) {
                this.column1Data = this.processColumnFields(this._column1Fields);
            }
            if (this._column2Fields) {
                this.column2Data = this.processColumnFields(this._column2Fields);
            }
            if (this._column3Fields) {
                this.column3Data = this.processColumnFields(this._column3Fields);
            }
        }
    }

    /**
     * @description Processes fields for a single column
     * @param {String} fieldString - Comma-separated list of field names
     * @returns {Array} Processed field data with labels and values
     */
    processColumnFields(fieldString) {
        let fields = fieldString.split(',').map(field => field.trim());
        
        // Filter out null fields if showNullFields is false
        if (!this._showNullFields) {
            fields = fields.filter(field => this.employeeData[field] != null);
        }
        
        // Transform field names into label-value pairs
        return fields.map(field => ({
            label: field.replace(/([A-Z])/g, ' $1').trim(), // Add spaces before capital letters
            value: this.employeeData[field] ?? 'N/A',
            helpText: this.fieldHelpTexts[field]
        }));
    }

    handleUpdateLabels() {
        updateDashboardProfileConfigAsync()
            .then(() => {
                this.showToast('Success', 'Labels update initiated successfully', 'success');
                this.isMismatch = false;
            })
            .catch(error => {
                this.showToast('Error', 'Error updating labels', 'error');
                console.error('Error updating labels', error);
            });
    }
}

/**
 * Field configuration examples:
 * Name,PhoneNumber,Email,HireDate,LastWorkingDate
 * ClientManager,ClientManagerEmail,Projects
 * AllBillableHours,AllNonBillableHours,AllAbsenceHours,AllHours,VacationsTaken
 */