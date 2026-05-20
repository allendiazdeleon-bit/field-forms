import { LightningElement, api } from 'lwc';

export default class NeuraFormDropZoneColumn extends LightningElement {
    @api components;
    @api columnId;
    @api sectionId;
    @api currentSelectionId;

    get isComponentsEmpty() {
        return this.components.length === 0;
    }

    isDragOver = false;
    @api draggedItemInfo; 
    

    get dropZoneClass() {
        // Return the appropriate class based on whether this section is the one being hovered
        return `slds-drop-zone ${this.isDragOver ? 'is-in-droppable-state slds-drop-zone_drag' : ''}`;    
    }

    handleDragOver(event) {
        //console.log('Column - Drag Over');
        if (this.draggedItemInfo && this.draggedItemInfo.structure === 'Component') {
            event.preventDefault();
            this.isDragOver = true;
            this.positionDragSlot(event);
        }
    }

    handleDragLeave(event) {
        if (this.draggedItemInfo && this.draggedItemInfo.structure === 'Component') {
            if (event.currentTarget === event.target) {
                this.isDragOver = false;
                this.hideAllDragSlots();
            }
        }
    }

    handleDrop(event) {
        event.preventDefault();

        // Note: the drag-start handlers in the section/question/palette
        // components don't call event.dataTransfer.setData('text', ...), so
        // reading getData('text') only ever returned ''. The actual identity
        // of the dragged item travels through draggedItemInfo (the nfdragstart
        // detail) instead - use that.
        if (this.draggedItemInfo && this.draggedItemInfo.structure === 'Component') {
            let dragSlotIndex = this.findDragSlotIndex();
            if (dragSlotIndex < 0 && this.isComponentsEmpty) {
                dragSlotIndex = 0;
            }
            if (dragSlotIndex >= 0) {
                this.updateLayout(this.draggedItemInfo.id || '', dragSlotIndex);
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

        this.dispatchEvent(new CustomEvent('updatecomponent', 
            {   
                bubbles: true,
                composed: true,
                detail: { component : this.draggedItemInfo, targetColumnId : this.columnId, targetSectionId: this.sectionId, droppedItemId : droppedItemId, dragSlotIndex : dragSlotIndex} 
            }
        ));
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