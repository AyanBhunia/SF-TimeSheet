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
        console.log('DemoDataSetup connected');
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
                this.showToast('Error', 'Failed to check demo data status: ' + this.getErrorMessage(error), 'error');
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
                this.showToast('Error', 'Failed to load created test records: ' + this.getErrorMessage(error), 'error');
            });
    }

    handleCreateDemoData() {
        if (this.isCreating) {
            return;
        }
        console.log('DemoDataSetup handleCreateDemoData');
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
                console.error('DemoDataSetup.createDemoData failed', error);
                this.showToast('Error', 'Error creating demo data: ' + this.getErrorMessage(error), 'error');
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
                this.showToast('Error', 'Error deleting test records: ' + this.getErrorMessage(error), 'error');
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

    getErrorMessage(error) {
        if (!error) {
            return 'Unknown error';
        }

        if (typeof error.body === 'string') {
            return error.body;
        }

        if (Array.isArray(error.body) && error.body.length > 0) {
            return error.body.map((item) => item.message || item.detail || JSON.stringify(item)).join(', ');
        }

        if (error.body) {
            if (error.body.message) {
                return error.body.message;
            }
            if (Array.isArray(error.body.pageErrors) && error.body.pageErrors.length > 0) {
                return error.body.pageErrors.map((item) => item.message).join(', ');
            }
            if (error.body.output && Array.isArray(error.body.output.errors) && error.body.output.errors.length > 0) {
                return error.body.output.errors.map((item) => item.message).join(', ');
            }
            if (error.body.output && error.body.output.errors) {
                return String(error.body.output.errors);
            }
            if (error.body.fieldErrors) {
                const fieldMessages = Object.values(error.body.fieldErrors)
                    .flat()
                    .map((fieldError) => fieldError.message)
                    .filter(Boolean);
                if (fieldMessages.length) {
                    return fieldMessages.join(', ');
                }
            }
            if (typeof error.body === 'object') {
                return JSON.stringify(error.body);
            }
        }

        if (error.message) {
            return error.message;
        }

        return JSON.stringify(error);
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
