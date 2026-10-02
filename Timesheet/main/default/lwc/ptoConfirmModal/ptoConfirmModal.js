import { api, track } from 'lwc';
import LightningModal from 'lightning/modal';

export default class PtoConfirmModal extends LightningModal {
    @api mode;
    @api summary;

    @track reason = '';

    get isApprove() {
        return this.mode === 'approve';
    }

    get modalHeader() {
        return this.isApprove ? 'Approve leave' : 'Reject leave';
    }

    handleReasonChange(event) {
        this.reason = event.target.value;
        const textarea = this.template.querySelector('lightning-textarea');
        if (textarea) {
            textarea.setCustomValidity('');
            textarea.reportValidity();
        }
    }

    handleCancel() {
        this.close({ confirmed: false });
    }

    handleApprove() {
        this.close({ confirmed: true });
    }

    handleReject() {
        const trimmedReason = (this.reason || '').trim();
        if (!trimmedReason) {
            const textarea = this.template.querySelector('lightning-textarea');
            if (textarea) {
                textarea.setCustomValidity('Enter a reason before rejecting.');
                textarea.reportValidity();
            }
            return;
        }
        this.close({ confirmed: true, reason: trimmedReason });
    }
}
