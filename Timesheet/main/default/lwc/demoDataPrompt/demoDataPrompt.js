import { LightningElement } from 'lwc';
import getDemoStatus from '@salesforce/apex/DemoDataController.getDemoStatus';
import DemoDataSetupModal from 'c/demoDataSetupModal';

/**
 * Employee Overview card that opens the demo data setup popup.
 * The page places it only for users with the Timesheet_Demo_Data_Access custom permission;
 * the card itself renders only when DemoDataController grants access (no active employee, or demo records to clean up).
 */
export default class DemoDataPrompt extends LightningElement {
    hasAccess = false;
    canCreate = false;

    connectedCallback() {
        this.loadStatus();
    }

    async loadStatus() {
        try {
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
