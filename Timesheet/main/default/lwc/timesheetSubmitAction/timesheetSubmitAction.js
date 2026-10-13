import { LightningElement, api } from 'lwc';
import submitTimesheet from '@salesforce/apex/WeeklyTimesheetController.submitTimesheet';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';

export default class TimesheetSubmitAction extends LightningElement {
    @api recordId;

    isExecuting = false;

    @api
    async invoke() {
        if (this.isExecuting) {
            return;
        }

        this.isExecuting = true;

        try {
            const result = await submitTimesheet({
                timesheetId: this.recordId
            });

            if (result === 'Success') {
                this.showToast(
                    'Success',
                    'Timesheet submitted successfully.',
                    'success'
                );

                await notifyRecordUpdateAvailable([
                    { recordId: this.recordId }
                ]);
            } else {
                this.showToast('Error', result, 'error');
            }
        } catch (error) {
            console.error('Timesheet submission error:', error);

            this.showToast(
                'Error',
                error.body?.message || error.message || 'An unexpected error occurred.',
                'error'
            );
        } finally {
            this.isExecuting = false;
        }
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}