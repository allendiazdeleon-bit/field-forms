import { LightningElement, api } from 'lwc';

export default class NeuraFormFooter extends LightningElement {
    @api currentPageIndex; // The current page index
    @api totalPages; // The total number of pages

    get isFirstStep() {
        return this.currentPageIndex === 0;
    }

    get hasPrevious(){
        return this.currentPageIndex > 0;
    }

    get isLastStep(){
        return this.currentPageIndex === this.totalPages - 1;
    }

    handleButtonClick(event) {
        // Retrieve the action type from the data attribute
        const actionType = event.target.dataset.action;

        // Dispatch a custom event with the action type
        this.dispatchEvent(new CustomEvent('buttonclick', {
            detail: { actionType },
            bubbles: true
        }));
    }
}