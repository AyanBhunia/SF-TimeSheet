import { LightningElement } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import hasHrAdminPermission from '@salesforce/apex/GetDashboardProfileDetails.hasHrAdminPermission';
import getEmployeeDetails from '@salesforce/apex/GetDashboardProfileDetails.getEmployeeDetails';
import isProductionOrg from '@salesforce/apex/DemoDataController.isProductionOrg';
import DemoDataSetupModal from 'c/demoDataSetupModal';

/**
 * Employee Overview card that opens the demo data setup popup, for HR admins without an employee record of
 * their own (or whose employee record is the Demo Employee). hasHrAdminPermission and getEmployeeDetails are
 * cacheable and called with the same parameters as dashboardProfile, so they are served from the client cache
 * instead of running their queries again.
 */
export default class DemoDataPrompt extends LightningElement {
    showCard = false;
    hasDemoData = false;
    productionOrg = false;
    // Set once the popup created or deleted records: the profile and charts still show their cached data.
    dataChanged = false;

    connectedCallback() {
        this.loadStatus();
    }

    async loadStatus() {
        try {
            if (!(await hasHrAdminPermission())) {
                return;
            }
            const employee = await this.getLinkedEmployee();
            // A real employee record means the user uses the app for real: no demo data.
            if (employee && employee.IsDemo !== true) {
                return;
            }
            this.hasDemoData = Boolean(employee);
            this.productionOrg = await isProductionOrg();
            this.showCard = true;
        } catch (error) {
            this.showCard = false;
            console.error('Error loading demo data status', error);
        }
    }

    /**
     * The employee linked to the user, or undefined when there is none: getEmployeeDetails then fails with
     * "List has no rows". Any other error is rethrown, so the card stays hidden rather than offering demo
     * data to a user who may have a real employee record.
     */
    async getLinkedEmployee() {
        try {
            return await getEmployeeDetails({ userID: USER_ID });
        } catch (error) {
            const message = (error && error.body && error.body.message) || '';
            if (message.includes('List has no rows')) {
                return undefined;
            }
            throw error;
        }
    }

    handleOpen() {
        DemoDataSetupModal.open({
            size: 'full',
            label: 'Timesheet Demo Data Setup',
            description: 'Create, review and delete demo data',
            isProductionOrg: this.productionOrg,
            // The popup reports the result, so the card updates without another server call.
            ondatachange: (event) => {
                this.hasDemoData = event.detail.hasDemoData;
                this.dataChanged = true;
            }
        });
    }

    get title() {
        return this.hasDemoData ? 'Your demo data' : 'Explore the app with demo data';
    }

    get description() {
        return this.hasDemoData
            ? 'Continue setting up your demo data, review it, or delete it when you are done.'
            : 'You have no employee record. Create sample employees, projects and timesheets step by step, and delete them when you are done.';
    }

    get buttonLabel() {
        return this.hasDemoData ? 'Manage Demo Data' : 'Open Demo Data Setup';
    }
}
