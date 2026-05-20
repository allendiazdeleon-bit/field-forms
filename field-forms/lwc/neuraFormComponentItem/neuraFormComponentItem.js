import { LightningElement, api } from 'lwc';

import { FIELDS } from 'c/neuraFormSchemaUtils';

export default class NeuraFormComponentItem extends LightningElement {
    title;
    iconName;
    structure;
    @api type;

    @api item;

    handleDragStart(event) {
        // Dispatch a custom event to signal the drag has started
        const dragStartEvent = new CustomEvent('nfdragstart', {
            detail: {
                title: this.type,
                iconName: this.iconName,
                structure: this.structure,
                type : this.type
            },
            bubbles: true
        });

        // debug event

        this.dispatchEvent(dragStartEvent);
    }

    handleDragEnd(event) {
        // Dispatch a custom event to signal the drag has ended
        const dragEndEvent = new CustomEvent('nfdragend', {
            detail: {
                title: this.type,
                iconName: this.iconName,
                structure: this.structure
            },
            bubbles: true
        });

        this.dispatchEvent(dragEndEvent);
    }

    // Keyboard-equivalent of dragging: Enter/Space requests the parent
    // append this component type to the current selection. Required for
    // mouse-free authoring; drag events alone can't be triggered by keyboard.
    handleKeyDown(event) {
        if (event.key !== 'Enter' && event.key !== ' ') return;
        event.preventDefault();
        this.dispatchEvent(new CustomEvent('paletteactivate', {
            detail: {
                title: this.title,
                iconName: this.iconName,
                structure: this.structure,
                type: this.type
            },
            bubbles: true,
            composed: true
        }));
    }

    connectedCallback(){
        this.title = this.item[FIELDS.Form_Setting__mdt.DisplayLabel.fieldApiName];
        this.iconName = this.item[FIELDS.Form_Setting__mdt.Icon.fieldApiName];
        this.structure = this.item[FIELDS.Form_Setting__mdt.Structure.fieldApiName];
    }

    get paletteTitle() {
        return `${this.title} (drag onto canvas or press Enter to add)`;
    }
}