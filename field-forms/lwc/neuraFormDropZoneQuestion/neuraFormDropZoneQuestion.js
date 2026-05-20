import { LightningElement, api } from 'lwc';

export default class NeuraFormDropZoneQuestion extends LightningElement {
    @api component;
    @api currentSelectionId

    isHovered = false;
    isClicked = false;

    get questionFormatObject(){
        let questionFormatObject = {};
        console.log('Question Format Object');
        console.log(JSON.stringify(this.component));
        if (this.component.attributes && typeof this.component.attributes === 'object') {

            questionFormatObject = {... this.component.attributes};

            /** Moving away from .fields
            Object.keys(this.component.attributes).forEach(key => {
                questionFormatObject.fields[key] = { value: this.component.attributes[key] };
            });
            */
        }
        return questionFormatObject;
    }
    
    handleMouseEnter(event) {
        // Set the hoveredSectionId to the ID of the section that triggered the event
        console.log('Mouse Enter');
        this.isHovered = true;
        this.dispatchEvent(new CustomEvent(
            'nfmouseenter', { 
                bubbles: true,
                composed: true,
                detail: this.component.id }));
    }

    handleMouseLeave() {
        // Clear the hoveredSectionId when the mouse leaves a section
        console.log('Mouse Leave');
        this.isHovered = false;
        this.dispatchEvent(new CustomEvent(
            'nfmouseexit', { 
                bubbles: true,
                composed: true,
                detail: this.component.id }));
    }

    handleClick(event){
        // prevent the event from bubbling up to the parent
        event.stopPropagation();

        this.dispatchEvent(new CustomEvent(
            'selection', { 
                bubbles: true,
                composed: true,
                detail: {id : this.component.id, type : 'Component'} }));
    }

    handleDragStart(event) {
        // Dispatch a custom event to signal the drag has started
        event.stopPropagation();
        const dragStartEvent = new CustomEvent('nfdragstart', {
            detail: {
                id: this.component.id,
                structure: "Component",
            },
            composed: true,
            bubbles: true
        });

        // debug event
        console.log('drag start');
        this.dispatchEvent(dragStartEvent);
    }

    handleDragEnd(event) {
        event.stopPropagation();
        // Dispatch a custom event to signal the drag has ended
        const dragEndEvent = new CustomEvent('nfdragend', {
            detail: {
                id: this.component.id,
                structure: "Component",
            },
            composed: true,
            bubbles: true
        });

        console.log('drag end');
        console.dir(dragEndEvent);
        this.dispatchEvent(dragEndEvent);
    }
    
    get isActiveSelection(){
        return this.currentSelectionId === this.component.id;
    }

    get questionClass() {
        // Return the appropriate class based on whether this section is the one being hovered
        return `slds-drop-zone__container ${this.isHovered || this.isActiveSelection ? 'slds-is-hovered' : ''}`;    
    }

    get questionActions() {
        return this.isHovered || this.isActiveSelection;
    }

    handleDeleteQuestion() {
        // dispatch the delete event with the section Id
        console.log('Delete Section');
        this.dispatchEvent(new CustomEvent('delete', {  
            bubbles: true,
            composed: true,
            detail: {id: this.component.id, type: 'Component'} }));
    }
}