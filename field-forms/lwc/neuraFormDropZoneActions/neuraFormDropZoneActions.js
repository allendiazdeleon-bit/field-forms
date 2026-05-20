import { LightningElement, api } from 'lwc';

export default class NeuraFormDropZoneActions extends LightningElement {
    @api type;
    @api itemId; 
    

    handleDelete() {
        // dispatch the delete event with the section Id
        console.log('Delete Item');
        this.dispatchEvent(new CustomEvent('delete', { 
            bubbles: true,
            composed: true,
            detail: {id: this.itemId, type: this.type} 
        }));
    }

    handleMove(){
        // TBD
    }
}