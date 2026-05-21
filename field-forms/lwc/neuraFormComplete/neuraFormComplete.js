import { LightningElement, api } from 'lwc';

export default class NeuraFormComplete extends LightningElement {

    @api isDesktop = false;
    // PDF generation state, threaded down from the renderer so this
    // screen can show "Generating..." → "Download PDF" without owning
    // the generation logic itself.
    @api pdfGenerating = false;
    @api pdfReady = false;
    @api pdfDownloadUrl;

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