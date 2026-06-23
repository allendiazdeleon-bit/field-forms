import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

export default class NeuraFormComplete extends NavigationMixin(LightningElement) {

    @api isDesktop = false;
    // PDF generation state, threaded down from the renderer so this
    // screen can show "Generating..." → "View PDF" without owning
    // the generation logic itself.
    @api pdfGenerating = false;
    @api pdfReady = false;
    // The report PDF's ContentDocumentId. We open it via NavigationMixin's
    // filePreview rather than a raw /sfc/servlet.shepherd download link with
    // target="_blank" — that link is broken in the Field Service mobile app
    // (it can't hand the URL off and prompts to "install the app"). filePreview
    // stays in-app and works on both desktop and mobile.
    @api pdfContentDocumentId;

    handleViewPdf() {
        if (!this.pdfContentDocumentId) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'filePreview' },
            state: {
                selectedRecordId: this.pdfContentDocumentId,
                recordIds: this.pdfContentDocumentId
            }
        });
    }

    // Branded-report distribution state, threaded down from the renderer.
    @api reportSending = false;
    @api reportSent = false;
    @api reportSendSkipped = false;
    @api reportRecipientsText;

    get reportSentMessage() {
        return this.reportRecipientsText
            ? `Report sent to ${this.reportRecipientsText}`
            : 'Report sent';
    }

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