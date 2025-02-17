import { LightningElement, api, track, wire } from 'lwc';
import { publish, MessageContext } from 'lightning/messageService';
import SELECTED_USER_CHANNEL from '@salesforce/messageChannel/SelectedUserChannel__c';
import getManagerEmployeeDetails from '@salesforce/apex/GetDashboardManagerEmployeeDetails.getManagerEmployeeDetails';
import USER_ID from '@salesforce/user/Id';

export default class DashboardEmployeePicklist extends LightningElement {
    @track employees = []; // Picklist options
    selectedUserId = USER_ID; // Stores selected dbt__User__c, defaults to USER_ID
    error; // Error handling

    // Import the MessageContext for publishing messages
    @wire(MessageContext)
    messageContext;

    connectedCallback() {
        this.loadEmployees();
    }

    loadEmployees() {
        getManagerEmployeeDetails({ managerId: USER_ID })
            .then((result) => {
                console.log("manager", result);

                // Start with the 'Current User' option
                this.employees = [
                    {
                        label: 'Current Employee',
                        value: USER_ID
                    }
                ];

                // Map the rest of the employees and append
                const employeeOptions = result.map((emp) => {
                    return {
                        label: emp.Name,
                        value: emp.dbt__User__c
                    };
                });

                // Append the employee options to the picklist options
                this.employees = this.employees.concat(employeeOptions);
                this.error = undefined;
            })
            .catch((error) => {
                this.error = error;
                this.employees = [];
                console.error('Error retrieving employees:', error);
            });
    }

    handleChange(event) {
        this.selectedUserId = event.detail.value;
        // Publish the message with the selected user ID
        const payload = { selectedUserId: this.selectedUserId };
        publish(this.messageContext, SELECTED_USER_CHANNEL, payload);
    }
}