import { LightningElement, api } from 'lwc';

export default class Panel extends LightningElement {
    @api title = '';
    @api position = 'left';
    @api size = 'medium';
    _sizePixels;
    @api open = false;
    @api customHeader = false;
    @api hideHeader = false;
    @api fullHeight = false;
    @api applyBodyClass = false;
    @api backgroundType = 'default'; // default and secondary

    get bodyClass(){
        return this.applyBodyClass ? 'slds-panel__body' : '';
    }

    get panelStyle(){
        // return nothing if default otherwise set to background: var(--slds-g-color-neutral-base-90);
        return this.backgroundType === 'default' ? '' : 'background: var(--slds-g-color-neutral-base-90);';
    }
    
    get panelClass(){
        return `slds-panel overflow-override ${this.customSizeClass} slds-panel_docked ${this.position === 'left' ? ' slds-panel_docked-left ' : ' slds-panel_docked-right '} ${this.open ? ' slds-is-open ' : ''} ` ;
    }

    get customSizeClass(){
        return this.sizePixels ? 'custom-panel-width' : `slds-size_${this.size}`;
    }

    @api
    get sizePixels(){
        return this._sizePixels;
    }
    set sizePixels(value){
        // modify the width css variable to the value passed in
        this._sizePixels = value;
        this.updatePanelWidth(value);
    }
    get displayHeader(){
        return !this.hideHeader && !this.customHeader;
    }

    updatePanelWidth(newWidth) {
        // Update the --neura-panel-width CSS variable
        if(this.template?.host?.style){
            this.template.host.style.setProperty('--neura-panel-width', `${newWidth}px`);
        }
    }


    handleCloseClick(){
        this.dispatchEvent(new CustomEvent('close'));
    }

    connectedCallback() {
        // Ensure the CSS variable is set when the component is inserted into the DOM
        if (this._sizePixels) {
            this.updatePanelWidth(this._sizePixels);
        }
    }
}