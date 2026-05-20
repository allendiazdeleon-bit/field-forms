import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class NeuraFormBuilderHeaderModal extends LightningModal {

    @api content;
    newName = '';
    newDescription = '';

    handleNameChange(event) {
        this.newName = event.target.value;
    }

    handleDescriptionChange(event) {
        this.newDescription = event.target.value;
    }

    handleSave(){
        // validate that the name is not empty
        this.checkValidity();
    }

    checkValidity(){
   
        const allValid = [
            ...this.template.querySelectorAll('lightning-input'),
        ].reduce((validSoFar, inputCmp) => {
            inputCmp.reportValidity();
            return validSoFar && inputCmp.checkValidity();
        }, true);
        if (allValid) {
            this.close({
                action : 'save',
                name: this.newName,
                description: this.newDescription
            });
        } 
    }

    handleCancel(){
        this.close(
            { action : 'cancel' }
        );
    }
}