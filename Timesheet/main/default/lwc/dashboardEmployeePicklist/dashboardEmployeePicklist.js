/**
 * @file dashboardEmployeePicklist.js
 * @description LWC for employee selection dropdown with LMS integration
 */

import { LightningElement, api, track, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import SELECTED_USER_CHANNEL from '@salesforce/messageChannel/UserChannel__c';
import getManagerEmployeeDetails from '@salesforce/apex/GetDashboardManagerEmployeeDetails.getManagerEmployeeDetails';
import USER_ID from '@salesforce/user/Id';

export default class dashboardEmployeePicklist extends LightningElement {
    // Track employee picklist options
    @track employees = []; 
    
    // Default selection to current user
    selectedUserId = USER_ID;
    
    // Error state tracking
    error;

    // LMS context for publishing messages
    @wire(MessageContext)
    messageContext;

    /**
     * @description Lifecycle hook when component is inserted into the DOM
     */
    connectedCallback() {
        this.loadEmployees();
    }

    /**
     * @description Fetches and loads employee data for the picklist
     */
    loadEmployees() {
        getManagerEmployeeDetails({ managerId: USER_ID })
            .then((result) => {
                // Initialize picklist with current user option
                this.employees = [
                    {
                        label: 'Current Employee',
                        value: USER_ID
                    }
                ];

                // Transform employee data into picklist options
                const employeeOptions = result.map((emp) => ({
                    label: emp.Name,
                    value: emp.User__c
                }));

                // Combine current user and employee options
                this.employees = this.employees.concat(employeeOptions);
                this.error = undefined;
            })
            .catch((error) => {
                this.error = error;
                this.employees = [];
                console.log('Error loading employee data');
            });
    }

    /**
     * @description Handles employee selection change and publishes to LMS
     * @param {Event} event - Change event from combobox
     */
    handleChange(event) {
        this.selectedUserId = event.detail.value;
        
        // Publish selected user ID through LMS
        const payload = { selectedUserId: this.selectedUserId };
        publish(this.messageContext, SELECTED_USER_CHANNEL, payload);
    }
}