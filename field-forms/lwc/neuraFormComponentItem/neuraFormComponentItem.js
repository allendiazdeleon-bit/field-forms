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
                iconName: this.id,
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
                iconName: this.id,
                structure: this.structure
            },
            bubbles: true
        });

        this.dispatchEvent(dragEndEvent);
    }

    connectedCallback(){
        // set variables from the item 
        // debug the item

        // check fields

        this.title = this.item[FIELDS.Form_Setting__mdt.DisplayLabel.fieldApiName];
        this.iconName = this.item[FIELDS.Form_Setting__mdt.Icon.fieldApiName];
        this.structure = this.item[FIELDS.Form_Setting__mdt.Structure.fieldApiName];
        
    }
}