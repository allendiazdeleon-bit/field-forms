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
    // The structure of whatever the user last copied (Component / Section /
    // Page). Used to decide whether Paste is meaningful for the current
    // selection - the previous build enabled Paste whenever anything was
    // copied, even when the paste would be a no-op (e.g. copied a Component,
    // selected a Page).
    @api copyStructure;

    screenSizeDefault = 'desktop-view';
    screenSizeOptions = [
        { label: 'Mobile', value: 'mobile-view' },
        { label: 'Tablet', value: 'tablet-view' },
        { label: 'Tablet Flipped', value: 'tablet-flipped-view' },
        { label: 'Desktop', value: 'desktop-view' }
    ];

    get disablePaste(){
        if (!this.enablePaste || !this.copyStructure) return true;
        // Page paste is always allowed (creates a new page at the end).
        if (this.copyStructure === 'Page') return false;
        // Section paste requires a Page or Section selection (drops onto the
        // current page; if a Section is selected, appended to its page).
        if (this.copyStructure === 'Section') {
            return !(this.selectionStructure === 'Page' || this.selectionStructure === 'Section');
        }
        // Component paste requires a Section or Component selection.
        if (this.copyStructure === 'Component') {
            return !(this.selectionStructure === 'Section' || this.selectionStructure === 'Component');
        }
        return true;
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