import LightningModal from 'lightning/modal';

export default class NeuraFormFileBulkNameUpdateModal extends LightningModal {
    batchNamePrefix;
    batchNameSuffix;

    handleCancel() {
        this.close();
    }

    handlePrefixChange(event) {
        this.batchNamePrefix = event.target.value;
    }

    handleSuffixChange(event) {
        this.batchNameSuffix = event.target.value;
    }

    handleUpdate() {
        const updatebulkfilenameEvent = new CustomEvent('updatebulkfilename', {
            detail: {
                batchNamePrefix: this.batchNamePrefix,
                batchNameSuffix: this.batchNameSuffix
            }
        });
        this.dispatchEvent(updatebulkfilenameEvent);

        this.handleCancel();
    }
}