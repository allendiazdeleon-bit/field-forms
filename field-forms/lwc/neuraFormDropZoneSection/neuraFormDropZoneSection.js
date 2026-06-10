import { LightningElement, api, track } from 'lwc';
import { FIELDS } from 'c/neuraFormSchemaUtils';
import { countConditionRules } from 'c/neuraFormUtils';

export default class NeuraFormDropZoneSection extends LightningElement {
    @api section;
    @api currentSelectionId;
    @track isHovered = false;
    @track isClicked = false;
    @api draggedItemInfo;

    get sectionSize(){
        if(this.section === undefined || this.section.attributes === undefined || this.section.attributes[FIELDS.Form_Section__c.Columns.fieldApiName] === undefined){
            return "1"
        } else {
            let sectionSize = 12 / Number(this.section.attributes[FIELDS.Form_Section__c.Columns.fieldApiName]);
            return sectionSize.toString();
        }
    }

    get showTitle(){
        return this.section?.attributes[FIELDS.Form_Section__c.ShowTitle.fieldApiName];
    }

    get titleText(){
        return this.section?.attributes[FIELDS.Form_Section__c.Title.fieldApiName];
    }
    handleDragStart(event) {
        // Dispatch a custom event to signal the drag has started
        const dragStartEvent = new CustomEvent('nfdragstart', {
            detail: {
                id: this.section.id,
                structure: "Layout",
            },
            composed: true,
            bubbles: true
        });

        // debug event
        //console.log('drag start');
        this.dispatchEvent(dragStartEvent);
    }

    handleDragEnd(event) {
        // Dispatch a custom event to signal the drag has ended
        const dragEndEvent = new CustomEvent('nfdragend', {
            detail: {
                id: this.section.id,
                structure: "Layout",
            },
            composed: true,
            bubbles: true
        });

        //console.log('drag end');
        this.dispatchEvent(dragEndEvent);
    }

    handleClick(event){
        this.dispatchEvent(new CustomEvent(
            'selection', {
                bubbles: true,
                composed: true,
                detail: {id : this.section.id, type : 'Section'} }));
    }

    // Keyboard alternative for selecting a section. Enter/Space activate the
    // same selection event the click handler dispatches.
    handleKeyDown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleClick(event);
        }
    }

    // Conditional-visibility badge — see neuraFormDropZoneQuestion.
    get conditionRuleCount() {
        return countConditionRules(
            this.section?.attributes?.[FIELDS.Form_Section__c.Conditions.fieldApiName]
        );
    }

    get isConditional() {
        return this.conditionRuleCount > 0;
    }

    get conditionalBadgeLabel() {
        const n = this.conditionRuleCount;
        return `Conditional · ${n} rule${n === 1 ? '' : 's'}`;
    }

    get sectionAriaLabel() {
        return this.titleText
            ? `Section: ${this.titleText}`
            : 'Section';
    }

    handleChildMouseEnter(event){
        this.isHovered = false;
    }

    handleChildMouseExit(event){
        this.isHovered = true;
    }

    handleMouseEnter(event) {
        // Set the hoveredSectionId to the ID of the section that triggered the event
        //console.log('Mouse Enter');
        this.isHovered = true;
    }

    handleMouseLeave() {
        // Clear the hoveredSectionId when the mouse leaves a section
        //console.log('Mouse Leave');
        this.isHovered = false;
    }

    get isActiveSelection(){
        return this.currentSelectionId === this.section.id;
    }

    get sectionClass() {
        // Return the appropriate class based on whether this section is the one being hovered
        return `slds-drop-zone__container ${this.isHovered || this.isActiveSelection ? 'slds-is-hovered' : ''}`;    
    }

    get sectionActions() {
        return this.isHovered || this.isActiveSelection;
    }

    handleDeleteSection() {
        // dispatch the delete event with the section Id
        this.dispatchEvent(new CustomEvent('delete', { 
            bubbles: true,
            composed: true,
            detail: {id: this.section.id, type: 'Section'} 
        }));
    }
}