import { LightningElement, api } from 'lwc';

export default class NeuraFormComplete extends LightningElement {

    @api
    isDesktop = false; 

    get wrapperClasses(){
        return `slds-theme_default ${this.isDesktop ? 'wrapper-desktop' : 'wrapper-mobile'}`;
    }

    handleBack(){
        console.log('Back button clicked');

        this.dispatchEvent(new CustomEvent('returnhome', 
            {
                bubbles: true, 
                composed: true
            }
        ));

        console.log('Back button event dispatched');
    }
}