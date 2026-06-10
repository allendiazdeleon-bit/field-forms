import { LightningElement, api } from 'lwc';
import { FIELDS } from 'c/neuraFormSchemaUtils';
import { countConditionRules } from 'c/neuraFormUtils';

export default class NeuraFormDropZoneQuestion extends LightningElement {
    @api component;
    @api currentSelectionId

    isHovered = false;
    isClicked = false;

    // Conditional-visibility badge: authored rules were invisible on the
    // canvas — the only way to know an element was conditional was to
    // click it and scroll the attributes panel.
    get conditionRuleCount() {
        return countConditionRules(
            this.component?.attributes?.[FIELDS.Form_Question__c.Conditions.fieldApiName]
        );
    }

    get isConditional() {
        return this.conditionRuleCount > 0;
    }

    get conditionalBadgeLabel() {
        const n = this.conditionRuleCount;
        return `Conditional · ${n} rule${n === 1 ? '' : 's'}`;
    }

    get questionFormatObject(){
        let questionFormatObject = {};
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
        this.isHovered = true;
        this.dispatchEvent(new CustomEvent(
            'nfmouseenter', { 
                bubbles: true,
                composed: true,
                detail: this.component.id }));
    }

    handleMouseLeave() {
        // Clear the hoveredSectionId when the mouse leaves a section
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

    // Keyboard equivalent of the click selection.
    handleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleClick(event);
        }
    }

    get questionAriaLabel() {
        const q = this.component?.attributes?.Question__c
            || this.component?.attributes?.Question
            || this.component?.type
            || 'Question';
        return `Question: ${q}`;
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
        this.dispatchEvent(new CustomEvent('delete', {  
            bubbles: true,
            composed: true,
            detail: {id: this.component.id, type: 'Component'} }));
    }
}