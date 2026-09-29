import LightningModal from 'lightning/modal';

export default class DemoDataSetupModal extends LightningModal {
    handleClose() {
        this.close('closed');
    }
}
