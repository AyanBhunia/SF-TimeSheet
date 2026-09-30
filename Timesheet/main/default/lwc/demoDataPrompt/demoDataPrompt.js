import { LightningElement } from 'lwc';
import hasHrAdminPermission from '@salesforce/apex/GetDashboardProfileDetails.hasHrAdminPermission';
import getDemoStatus from '@salesforce/apex/DemoDataController.getDemoStatus';
import DemoDataSetupModal from 'c/demoDataSetupModal';

/**
 * Employee Overview card that opens the demo data setup popup.
 * Only HR admins (Timesheet_HR_Admin) can call DemoDataController, so other users stop after the HR admin check.
 * The card renders only when DemoDataController grants access (no active employee, or demo records to clean up).
 */
export default class DemoDataPrompt extends LightningElement {
    hasAccess = false;
    canCreate = false;

    connectedCallback() {
        this.loadStatus();
    }

    async loadStatus() {
        try {
            if (!(await hasHrAdminPermission())) {
                this.hasAccess = false;
                return;
            }
            const status = await getDemoStatus();
            this.hasAccess = status.hasAccess === true;
            this.canCreate = status.canCreate === true;
        } catch (error) {
            this.hasAccess = false;
            console.error('Error loading demo data status', error);
        }
    }

    async handleOpen() {
        await DemoDataSetupModal.open({
            size: 'full',
            label: 'Timesheet Demo Data Setup',
            description: 'Create, review and delete demo data'
        });
        this.loadStatus();
    }

    get title() {
        return this.canCreate ? 'Explore the app with demo data' : 'You still have demo records';
    }

    get description() {
        return this.canCreate
            ? 'You have no active employee record. Create sample employees, projects and timesheets step by step, and delete them when you are done.'
            : "You now have an active employee record, so new demo data can't be created. You can still review and delete your demo data.";
    }

    get buttonLabel() {
        return this.canCreate ? 'Open Demo Data Setup' : 'Manage Demo Data';
    }
}
