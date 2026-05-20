import { LightningElement, api } from 'lwc';
import saveAsModal from 'c/neuraFormBuilderHeaderModal';

export default class NeuraFormBuilderHeader extends LightningElement {

    @api builderName;
    @api dropdownTitle;
    @api title;
    @api disableUndo;
    @api disableRedo;
    @api enablePaste;
    @api selectionStructure;

    screenSizeDefault = 'desktop-view';
    screenSizeOptions = [
        { label: 'Mobile', value: 'mobile-view' },
        { label: 'Tablet', value: 'tablet-view' },
        { label: 'Tablet Flipped', value: 'tablet-flipped-view' },
        { label: 'Desktop', value: 'desktop-view' }
    ];

    get disablePaste(){
        return !this.enablePaste;
    }

    get disableCopy(){
        return !(this.selectionStructure == 'Component' || this.selectionStructure == 'Section' || this.selectionStructure == 'Page');
    }

    handleClick(event){
        const clickedButton = event.currentTarget.dataset.action;
        const value = event.detail?.value;
        if (clickedButton === 'saveas') {
            this.handleSaveAs();
        } else {
            const customEvent = new CustomEvent('headerclick', { detail: {actionType: clickedButton, value: value }});
            this.dispatchEvent(customEvent);
        }
    }

    async handleSaveAs() {
        const result = await saveAsModal.open({
            // `label` is not included here in this example.
            // it is set on lightning-modal-header instead
            size: 'small',
            description: 'A new form will be created with the same structure as the current form. Please enter a name for the new form.',
            content: 'content',
        });

        console.log('Result: ', result);

        if (result.action === 'save') {
            this.handleModalSave(result);
        } else {
            // Do Nothing 
        }
    }

    handleModalSave(result) {
        // {actionType: clickedButton, value: this.newFormName }
        const clickedButton = 'saveas';
        const newFormName = result.name;
        const customEvent = new CustomEvent('headerclick', { detail: {actionType: clickedButton, value: newFormName } });
        this.dispatchEvent(customEvent);
        console.log('Save As Event Sent');
        this.newFormName = ''; // Reset the name
    }


}