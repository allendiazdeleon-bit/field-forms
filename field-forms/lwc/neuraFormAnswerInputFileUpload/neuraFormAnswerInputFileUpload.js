import { LightningElement, api } from 'lwc';
export default class NeuraFormAnswerInputFileUpload extends LightningElement {
showPhotoFocus = false ;

    @api recordId;
    @api layoutStyle = 'large';
    @api filesData;

 handlePhotoOpen(event) {
        try {
            this.showPhotoFocus = true;
          
        } catch (e) {
            console.log(e);
        }
    }
}