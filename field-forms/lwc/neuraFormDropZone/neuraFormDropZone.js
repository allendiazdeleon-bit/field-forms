import { LightningElement, api, track } from 'lwc';
import { generateUUID } from 'c/utilityService';

export default class NeuraFormDropZone extends LightningElement {
    isDragOver = false;
    @api currentSelectionId;
    @api draggedItemInfo = {};

    get dropZoneClass() {
        return `slds-drop-zone slds-p-around_small ${this.isDragOver ? 'slds-drop-zone_drag is-in-droppable-state' : ''}`;
    }

    @api layout; // JSON object from the parent component

    handleDragOver(event) {
        //console.log('Drop Zone - Drag Over');
        if (this.draggedItemInfo && this.draggedItemInfo.structure === 'Layout') {
            event.preventDefault();
            this.isDragOver = true;
            this.positionDragSlot(event);
        }
    }

    handleDragLeave(event) {
        if (this.draggedItemInfo && this.draggedItemInfo.structure === 'Layout') {
            if (event.currentTarget === event.target) {
                this.isDragOver = false;
                this.hideAllDragSlots();
            }
        }
    }

    handleDrop(event) {
        event.preventDefault();
    
        const droppedItemId = this.draggedItemInfo.id;
        if (this.draggedItemInfo && this.draggedItemInfo.structure === 'Layout') {
            // Find the index of the drag slot in the drop zone
            const dragSlotIndex = this.findDragSlotIndex();
            if (dragSlotIndex >= 0) {
                this.updateLayout(droppedItemId, dragSlotIndex);
            }
        }

        this.isDragOver = false;
        this.hideAllDragSlots();
    
    }
    
    findDragSlotIndex() {
    // Get all drag slots in their current order
    const dragSlots = Array.from(this.template.querySelectorAll('.slds-drop-zone_drag__slot'));

    // Find the index of the drag slot that is currently shown
    const shownIndex = dragSlots.findIndex(slot => slot.classList.contains('slds-show'));

    return shownIndex;
}
    
    
    updateLayout(droppedItemId, dragSlotIndex) {
        // send the event to the parent component
        this.dispatchEvent(new CustomEvent('updatesection', { detail: { droppedItemId : droppedItemId, dragSlotIndex : dragSlotIndex} }));
    }
    

    positionDragSlot(event) {
        const mouseY = event.clientY;
        const dropZone = this.template.querySelector('.slds-drop-zone');
        const dragSlots = dropZone.querySelectorAll('[data-drag-slot]');
        
        let closestSlot = null;
        let closestDistance = Number.MAX_VALUE;
    
        dragSlots.forEach(slot => {
            const rect = slot.getBoundingClientRect();
            const midY = rect.top + rect.height / 2;
            const distance = Math.abs(mouseY - midY);
    
            if (distance < closestDistance) {
                closestSlot = slot;
                closestDistance = distance;
            }
        });
    
        if (closestSlot) {
            this.showDragSlot(closestSlot.dataset.dragSlot);
        } else {
            this.showDragSlot('start');
        }
    }

    getClosestChild(dropZone, mouseY) {
        let closestChild = null;
        let closestDistance = Number.MAX_VALUE;

        dropZone.childNodes.forEach(child => {
            if (child.nodeType === Node.ELEMENT_NODE) {
                const box = child.getBoundingClientRect();
                const childMidY = box.top + box.height / 2;
                const distance = Math.abs(mouseY - childMidY);
                if (distance < closestDistance) {
                    closestDistance = distance;
                    closestChild = mouseY < childMidY ? child : child.nextSibling;
                }
            }
        });

        return closestChild;
    }

    calculateDropTarget(event) {
        const dropZone = this.template.querySelector('.slds-drop-zone');
        const mouseY = event.clientY;
    
        // Find all drag slots inside the drop zone
        const dragSlots = Array.from(dropZone.querySelectorAll('[data-drag-slot]'));
    
        let closestSlot = null;
        let closestDistance = Number.MAX_VALUE;
    
        dragSlots.forEach(slot => {
            const slotRect = slot.getBoundingClientRect();
            const slotMidY = slotRect.top + slotRect.height / 2;
            const distance = Math.abs(mouseY - slotMidY);
    
            if (distance < closestDistance) {
                closestSlot = slot;
                closestDistance = distance;
            }
        });
    
        if (closestSlot) {
        } else {
        }
    
        return closestSlot ? closestSlot.dataset.dragSlot : null;
    }
    

    showDragSlot(slotId) {
        this.hideAllDragSlots();
        const slot = this.template.querySelector(`[data-drag-slot="${slotId}"]`);
        if (slot) {
            slot.classList.remove('slds-hidden');
            slot.classList.add('slds-show');
        }
    }
    

    hideAllDragSlots() {
        this.template.querySelectorAll('[data-drag-slot]').forEach(slot => {
            slot.classList.remove('slds-show');
            slot.classList.add('slds-hidden');
        });
    }
    

}