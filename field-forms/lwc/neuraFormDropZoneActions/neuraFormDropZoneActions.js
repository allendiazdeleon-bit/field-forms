import { LightningElement, api } from 'lwc';

export default class NeuraFormDropZoneActions extends LightningElement {
    @api type;
    @api itemId;

    // Accessible alt text. Keeps the toolbar usable for screen readers and
    // gives keyboard users a clear hover/focus label.
    get moveUpAltText() {
        return `Move ${this.type} up`;
    }
    get moveDownAltText() {
        return `Move ${this.type} down`;
    }
    get deleteAltText() {
        return `Delete ${this.type}`;
    }
    get actionsAriaLabel() {
        return `${this.type} actions`;
    }

    handleDelete() {
        this.dispatchEvent(new CustomEvent('delete', {
            bubbles: true,
            composed: true,
            detail: { id: this.itemId, type: this.type }
        }));
    }

    handleMoveUp() {
        this.dispatchMove('up');
    }

    handleMoveDown() {
        this.dispatchMove('down');
    }

    dispatchMove(direction) {
        this.dispatchEvent(new CustomEvent('move', {
            bubbles: true,
            composed: true,
            detail: { id: this.itemId, type: this.type, direction }
        }));
    }
}
