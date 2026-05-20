import { LightningElement, api, track } from 'lwc';

export default class NeuraFormAnswerInputSignature extends LightningElement {
    @api get filesData() {
        return this._filesData;
    } 
    set filesData(value) {
        this._filesData = [...value];
    }

    @track _filesData;

    showOption = false ;
    showSignature = false ;
    showTypeSignature = false;

    handleshowOption() {
        this.showOption = true ;
    }

    handleTypeSignature() {
        this.showSignature = true ;
        this.showTypeSignature = true;
    }

    handleDrawSignature() {
       this.showSignature = true;
       this.showTypeSignature = false;
    }

    handleDoneSignature({ detail }) {
        this._filesData = [...detail.value];
    }

    handleCancel() {
        this.showSignature = false;
        this.showOption = false;
    }

    handleChangeType() {
        this.showSignature = false;
    }

    get existingSignature() {
        if(this._filesData && this._filesData.length) {
            return this._filesData[0].data;
        }
        return false;
    }
}