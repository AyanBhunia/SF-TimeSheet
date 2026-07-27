/**
 * @file demoDataSetup.js
 * @description LWC controller for creating, inspecting, and deleting demo data for the current user.
 */
import { LightningElement, track } from 'lwc';
import createDemoData from '@salesforce/apex/DemoDataController.createDemoData';
import deleteTestRecords from '@salesforce/apex/DemoDataController.deleteTestRecords';
import getDemoStatus from '@salesforce/apex/DemoDataController.getDemoStatus';
import getDemoRecords from '@salesforce/apex/DemoDataController.getDemoRecords';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { NavigationMixin } from 'lightning/navigation';

export default class DemoDataSetup extends NavigationMixin(LightningElement) {
    @track isLoading = true;
    @track hasEmployee = false;
    @track isTestEmployee = false;
    @track employeeName = '';
    @track demoRecords = [];
    @track accessTerminated = false;
    @track isCreating = false;
    @track isDeleting = false;

    connectedCallback() {
        this.loadStatus();
    }

    loadStatus() {
        this.isLoading = true;
        getDemoStatus()
            .then((result) => {
                this.hasEmployee = result.hasEmployee;
                this.isTestEmployee = result.isTestEmployee;
                this.employeeName = result.employeeName;
                if (this.hasEmployee && this.isTestEmployee && !this.accessTerminated) {
                    this.loadDemoRecords();
                } else {
                    this.isLoading = false;
                }
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', 'Failed to check demo data status: ' + (error.body ? error.body.message : error.message), 'error');
            });
    }

    loadDemoRecords() {
        getDemoRecords()
            .then((records) => {
                this.demoRecords = records || [];
                this.isLoading = false;
            })
            .catch((error) => {
                this.isLoading = false;
                this.showToast('Error', 'Failed to load created test records: ' + (error.body ? error.body.message : error.message), 'error');
            });
    }

    handleCreateDemoData() {
        if (this.isCreating) {
            return;
        }
        this.isCreating = true;
        this.isLoading = true;
        createDemoData()
            .then(() => {
                this.showToast('Success', 'Demo dataset created successfully with employee Test T. Refreshing page...', 'success');
                setTimeout(() => {
                    window.location.reload();
                }, 1000);
            })
            .catch((error) => {
                this.isCreating = false;
                this.isLoading = false;
                this.showToast('Error', 'Error creating demo data: ' + (error.body ? error.body.message : error.message), 'error');
            });
    }

    handleDeleteTestRecords() {
        this.isDeleting = true;
        this.isLoading = true;
        deleteTestRecords()
            .then(() => {
                this.showToast('Success', 'All test records have been deleted.', 'success');
                this.isDeleting = false;
                this.isLoading = false;
                // As required: tab only stays visible/accessible until user clicked delete button
                this.accessTerminated = true;
                this.demoRecords = [];
            })
            .catch((error) => {
                this.isDeleting = false;
                this.isLoading = false;
                this.showToast('Error', 'Error deleting test records: ' + (error.body ? error.body.message : error.message), 'error');
            });
    }

    handleOpenUrl(event) {
        const url = event.currentTarget.dataset.url;
        if (url) {
            window.open(url, '_blank');
        }
    }

    handleReturnToOverview() {
        this[NavigationMixin.Navigate]({
            type: 'standard__navItemPage',
            attributes: {
                apiName: 'Overview'
            }
        });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            message,
            variant
        }));
    }

    // Access control and state getters
    get showCreateButton() {
        return !this.isLoading && !this.hasEmployee && !this.accessTerminated;
    }

    get showCreatedRecordsView() {
        return !this.isLoading && this.hasEmployee && this.isTestEmployee && !this.accessTerminated;
    }

    get showDeleteButton() {
        return this.showCreatedRecordsView;
    }

    get showAccessTerminated() {
        return !this.isLoading && this.accessTerminated;
    }

    get showInaccessibleEmployee() {
        return !this.isLoading && this.hasEmployee && !this.isTestEmployee && !this.accessTerminated;
    }
}
