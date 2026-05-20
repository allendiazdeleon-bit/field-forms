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
            size: 'small',
            description: 'A new form will be created with the same structure as the current form. Please enter a name for the new form.',
            content: 'content',
        });

        // LightningModal returns undefined when dismissed (Escape, X, click-out).
        // Guard before reading .action.
        if (!result || result.action !== 'save') {
            return;
        }
        this.handleModalSave(result);
    }

    handleModalSave(result) {
        const newFormName = (result?.name || '').trim();
        if (!newFormName) {
            // Defence-in-depth — the modal's checkValidity should already block
            // this, but if a future change relaxes the input we don't want to
            // create an unnamed template.
            return;
        }
        const customEvent = new CustomEvent('headerclick', { detail: { actionType: 'saveas', value: newFormName } });
        this.dispatchEvent(customEvent);
    }


}