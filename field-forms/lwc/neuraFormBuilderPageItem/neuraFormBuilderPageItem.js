import { LightningElement, api } from 'lwc';
import { FIELDS } from 'c/neuraFormSchemaUtils';
import { countConditionRules } from 'c/neuraFormUtils';

export default class NeuraFormBuilderPageItem extends LightningElement {
    @api currentPageId;
    @api page;
    @api newPage = false;


    get iconName(){
        // if newPage is true then return the 'add' icon
        // if newPage is false and currentPageId is equal to the page Id then return the 'selected' icon (the dot)
        // else no icon
        return this.newPage ? 'utility:add' : this.currentPageId === this.page?.id ? 'utility:record' : '';
    }

    get backgroundColor(){
        return this.isCurrentPage ? 'background-color: var(--lwc-brandLightActive)' : '';
    }

    get isCurrentPage(){
        // if matching page id and current page id then return true
        return !this.newPage && this.currentPageId === this.page?.id;
    }

    // Conditional-visibility marker on the page rail — a page that only
    // shows under certain answers should be recognizable at a glance.
    get isConditional() {
        return countConditionRules(
            this.page?.attributes?.[FIELDS.Form_Page__c.Conditions.fieldApiName]
        ) > 0;
    }

    get title(){
        // if page exists and has page.attributes.Title__c then return that as the title otherwise return New Page
        return this.page?.attributes[FIELDS.Form_Page__c.Title.fieldApiName] ?? 'New Page';
    }
    handlePageClick(event){
        // send an event to the parent component to create a new page

        const clickedElement = event.target;
        const isButtonIcon = clickedElement.closest('lightning-button-icon');

        if (isButtonIcon) {
            // Prevent the event from firing if the target is within a lightning-button-icon
            event.stopPropagation();
            return;
        }

        if(this.newPage){
            this.dispatchEvent(new CustomEvent('newpage', {
                bubbles: true
            }));
        } else {
            this.dispatchEvent(new CustomEvent('selection', {
                detail: { id: this.page.id, type: 'Page' },
                bubbles: true
            }));
        
        }
    }

    handlePageUp(){
        this.dispatchEvent(new CustomEvent('reorder', {
            detail: { id: this.page.id, direction: 'up' },
            bubbles: true
        }));
    }

    handlePageDown(){
        this.dispatchEvent(new CustomEvent('reorder', {
            detail: { id: this.page.id, direction: 'down' },
            bubbles: true
        }));
    }

    handlePageDelete(){
        this.dispatchEvent(new CustomEvent('delete', {
            detail: { id: this.page.id },
            bubbles: true
        }));
    }

    // --- Inline rename --------------------------------------------------
    // Double-click the page label to edit it in place. Enter commits,
    // Escape cancels, blur commits. Avoids routing routine renames through
    // the attributes panel.

    isEditingName = false;
    editingName = '';

    handleStartRename(event) {
        if (this.newPage) return;
        event.stopPropagation();
        this.editingName = this.title;
        this.isEditingName = true;
    }

    handleNameInputClick(event) {
        // Keep clicks on the input from re-triggering page selection.
        event.stopPropagation();
    }

    handleNameInput(event) {
        this.editingName = event.target.value;
    }

    handleNameKeyDown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.commitNameEdit();
        } else if (event.key === 'Escape') {
            event.preventDefault();
            this.isEditingName = false;
        }
    }

    commitNameEdit() {
        if (!this.isEditingName) return;
        const next = (this.editingName || '').trim();
        this.isEditingName = false;
        if (!next || next === this.title) return;
        this.dispatchEvent(new CustomEvent('rename', {
            detail: { id: this.page.id, title: next },
            bubbles: true,
            composed: true
        }));
    }
}