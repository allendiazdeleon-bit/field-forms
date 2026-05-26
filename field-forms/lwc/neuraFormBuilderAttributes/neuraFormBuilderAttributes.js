import { LightningElement, api, wire } from 'lwc';
import getAllAttributes from '@salesforce/apex/neuraFormBuilderController.getAllAttributes';

import { FIELDS, OBJECTS } from 'c/neuraFormSchemaUtils';

export default class NeuraFormBuilderAttributes extends LightningElement {
    
    @api selection;
    //objectApiName = OBJECTS.Form_Section__c.objectApiName;
    groupedAttributes = {};
    
    get formTemplateApiName(){
        return OBJECTS.Form_Template__c.objectApiName;
    }

    get formSectionApiName(){
        return OBJECTS.Form_Section__c.objectApiName;
    }

    get formQuestionApiName(){
        return OBJECTS.Form_Question__c.objectApiName;
    }

    get formPageApiName(){
        return OBJECTS.Form_Page__c.objectApiName;
    }
    

    @wire(getAllAttributes)
    wiredAttributes({ error, data }) {
        if (data) {
            //console.log('Data');
            //console.log(JSON.stringify(data));
            this.processData(data);
        } else if (error) {
            console.error(error);

            // Handle the error
        }
    }

    processData(data) {
        // Clear previous data
        let updatedGroupedAttributes = {};

        data.forEach(item => {
            //console.log('Attribute Item');
            //console.log(JSON.parse(JSON.stringify(item)));

            let settingRefAPI = FIELDS.Form_Setting_to_Field__mdt.FormSettingRef.fieldApiName;
            let settingLabelAPI = FIELDS.Form_Setting_to_Field__mdt.FormSettingLabel.fieldApiName;
            //console.log('Setting Ref API: ' + settingRefAPI);
            //console.log('Setting Label API: ' + settingLabelAPI);
            let fsfRefAPI = FIELDS.Form_Setting_to_Field__mdt.FormSettingFieldRef.fieldApiName;
            let fsfLabelAPI = FIELDS.Form_Setting_to_Field__mdt.FormSettingFieldLabel.fieldApiName;

            // test if the settingRefAPI is available
            //console.log('Item Setting Ref API');
            //console.dir(item?.[settingRefAPI]);

            const groupName = item?.[settingRefAPI]?.[settingLabelAPI];

            if (!updatedGroupedAttributes[groupName]) {
                updatedGroupedAttributes[groupName] = [];
            }

            // Test Label retrieval

            updatedGroupedAttributes[groupName].push({
                label: item?.[fsfRefAPI]?.[fsfLabelAPI]
            });
        });

        this.groupedAttributes = updatedGroupedAttributes
    }

    get activeSelection() {

        const activeSelection = [];
       
        const group = this.groupedAttributes[this.selection.type];
        if (group && this.selection && this.selection?.attributes) {
            group.forEach(attr => {
                // if the label contains color, flag isColor to true

                const label = attr.label; // Assuming attr.label corresponds to Form_Setting__r.Label
                const isColor = label.toLowerCase().includes('color');
                const isValueSet = label.toLowerCase() === FIELDS.Form_Question__c.ValueSet.fieldApiName.toLowerCase();
                const isQuestionConditions = label.toLowerCase() === FIELDS.Form_Question__c.Conditions.fieldApiName.toLowerCase();
                const isSectionConditions = label.toLowerCase() === FIELDS.Form_Section__c.Conditions.fieldApiName.toLowerCase();
                const isPageConditions = label.toLowerCase() === FIELDS.Form_Page__c.Conditions.fieldApiName.toLowerCase();
                const isStandard = !isColor && !isValueSet && !isQuestionConditions && !isSectionConditions && !isPageConditions;
                // set the displaylabel to the developer name of the attribute and replace _ with space
                const displayLabel = label.replace(/__c/g,'').replace(/_/g, ' ');
                let value = this.selection.attributes[label];
                if (value === undefined) {
                    value = null;
                } 
                activeSelection.push({ label, value, isColor, isStandard, isValueSet, displayLabel});
            });
        }
        return activeSelection;
    }

    get isForm(){
        return this.selection.type === 'Form';
    }

    get isNotForm(){
        return !this.isForm;
    }

    get isPage(){
        return this.selection.type === 'Page';
    }

    get isSection(){
        return this.selection.type === 'Section';
    }
    

    get isQuestion(){
        return !this.isPage && !this.isSection && !this.isForm;
    }

    get isNotDisplayText(){
        return this.selection.type != 'Display Text';
    }

    get conditionsField(){
        return this.isQuestion ? FIELDS.Form_Question__c.Conditions.fieldApiName : this.isSection ? FIELDS.Form_Section__c.Conditions.fieldApiName : this.isPage ? FIELDS.Form_Page__c.Conditions.fieldApiName : null;
    }

    get conditionFieldValue(){
        let conditions = this.selection.attributes[this.conditionsField];
        return conditions ? JSON.parse(conditions) : {};

    }

    

    get questionFieldApiName(){
        return FIELDS.Form_Question__c.Question.fieldApiName;
    }

    get isNotLayoutComponent(){
        return !this.selection?.attributes[FIELDS.Form_Question__c.LayoutItemCheckbox.fieldApiName];
    }

    get questionFieldValue(){
        return this.selection?.attributes[FIELDS.Form_Question__c.Question.fieldApiName];
    }

    // ----- Pillar 2 catalog-aware question input wiring -------------------
    // The Question__c input has three render modes depending on the
    // binding's catalog state:
    //   1. Editable Question__c     — no catalog link OR catalog feature off
    //   2. Read-only resolved value — linked to catalog, no override
    //   3. Editable Override_Question__c — linked to catalog, override set
    // Without the read-only-when-inherited mode, edits made under catalog
    // resolution would silently disappear on the next snapshot rebuild —
    // the shim re-resolves catalog content over whatever was saved.

    get hasCatalogLink() {
        return Boolean(this.selection?.attributes?.Form_Question_Catalog__c);
    }

    get hasQuestionOverride() {
        return Boolean(this.selection?.attributes?.Override_Question__c);
    }

    // Wave 35.8a: exclusive when the catalog entry has only this binding
    // pointing at it (count == 1). The flag is computed server-side and
    // stamped onto the binding's attributes by neuraFormBuilder's
    // organizeQuestions. Exclusive bindings treat the input as editable
    // Question__c — edits flow back to the catalog via the controller's
    // sync on update. Shared bindings (count > 1) keep the read-only
    // inherited treatment that requires an explicit Override click.
    get isExclusiveCatalogEntry() {
        return Boolean(this.selection?.attributes?._exclusiveCatalogEntry);
    }

    // Mode 1: legacy editable input. Used when catalog isn't in play at all.
    get showLegacyQuestionInput() {
        return !this.hasCatalogLink;
    }

    // Mode 2: read-only resolved value. Shared catalog, no override.
    // Admin must click "Override in this template" to edit.
    get showInheritedQuestionReadOnly() {
        return this.hasCatalogLink && !this.hasQuestionOverride && !this.isExclusiveCatalogEntry;
    }

    // Mode 3: editable Question__c on an exclusive catalog entry. Edits
    // sync back to the catalog via the controller's
    // syncExclusiveCatalogContentOnUpdate path. No Override click needed.
    get showExclusiveEditableInput() {
        return this.hasCatalogLink && !this.hasQuestionOverride && this.isExclusiveCatalogEntry;
    }

    // Mode 4: editable Override_Question__c — admin explicitly overrode.
    // Works for both exclusive and shared (admin chose to override).
    get showOverrideQuestionInput() {
        return this.hasCatalogLink && this.hasQuestionOverride;
    }

    get overrideQuestionFieldApiName() {
        return 'Override_Question__c';
    }

    get overrideQuestionFieldValue() {
        return this.selection?.attributes?.Override_Question__c;
    }

    /**
     * Provenance badge fires this when the admin clicks "Override in
     * this template". Seed Override_Question__c with the current
     * resolved value so the admin has something to edit from rather
     * than an empty box.
     */
    handleRequestOverride() {
        const seedValue = this.questionFieldValue || '';
        this.sendChangeUpdate(seedValue, 'Override_Question__c');
    }

    /**
     * Provenance badge fires this when the admin clicks "Revert to
     * catalog default". Clear the override; next render the binding
     * shows the read-only catalog value again.
     */
    handleRevert() {
        this.sendChangeUpdate(null, 'Override_Question__c');
    }

    handleAttributeChange(event) {
        // update the selection with the new value of the event detail 
        try {
            const value = event.currentTarget.value;
            const field = event.currentTarget.fieldName;
            this.sendChangeUpdate(value, field);
        } catch (error) {
            console.error(error);
        }

    }

    handleValueSetChange(event) {
        // update the selection with the new value of the event detail 
        try {
            const value = event.detail.value;
            const field = event.detail.fieldName;
            this.sendChangeUpdate(value, field);
        } catch (error) {
            console.error(error);
        }
    }

    handleConditionsUpdate(event){
        try {
            const value = event.detail.value;
            const field = this.conditionsField;
            this.sendChangeUpdate(value, field);
        } catch (error) {
            console.error('Error updating conditions:', error);
        }
    }

    sendChangeUpdate(value, field){
            let newSelection = JSON.parse(JSON.stringify(this.selection));
            const previousValue = newSelection.attributes[field];
            newSelection.attributes[field] = value;
            // send the updated selection to the parent component
            this.dispatchEvent(new CustomEvent('update', { detail: { newSelection: newSelection, editedField: {field: field, previousValue: previousValue, newValue: value}  }}));
    }
}