import { LightningElement, api } from 'lwc';
import getEmployeeDetails from '@salesforce/apex/GetDashboardProfileDetails.getEmployeeDetails';
import USER_ID from '@salesforce/user/Id';

export default class DashboardProfile extends LightningElement {
    @api fieldsOrder; // Allows dynamic reordering of fields in App Builder
    employeeData;
    orderedFields = [];

    connectedCallback() {
        // Fetch employee details when the component is initialized
        this.fetchEmployeeDetails();
    }

    fetchEmployeeDetails() {
        getEmployeeDetails({ employeeId: USER_ID })
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
        if (this.employeeData && this.fieldsOrder) {
            let fieldList = this.fieldsOrder.split(',').map(field => field.trim());
            this.orderedFields = fieldList
                .filter(field => this.employeeData.hasOwnProperty(field))
                .map(field => ({
                    label: field.replace(/([A-Z])/g, ' $1').trim(), // Convert "ClientManager" -> "Client Manager"
                    value: this.employeeData[field] ?? 'N/A'
                }));
        }
    }
}

// Name, ClientManager, ClientManagerEmail, Projects, TotalBillableHours, TotalNonBillableHours, TotalAbsenceHours, TotalHours
// Name, ClientManager, Projects, TotalBillableHours, TotalNonBillableHours, TotalHours, TotalAbsenceHours