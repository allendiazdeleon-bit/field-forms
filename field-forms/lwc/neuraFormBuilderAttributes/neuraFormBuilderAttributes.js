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
            console.log('Error');
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

            console.log('Group Name: ' + groupName);
            if (!updatedGroupedAttributes[groupName]) {
                updatedGroupedAttributes[groupName] = [];
            }

            console.log('FSF Ref API: ' + fsfRefAPI);
            console.log('FSF Label API: ' + fsfLabelAPI);
            // Test Label retrieval
            console.log('Item Label: ' + item?.[fsfRefAPI]?.[fsfLabelAPI]);

            updatedGroupedAttributes[groupName].push({
                label: item?.[fsfRefAPI]?.[fsfLabelAPI]
            });
        });

        this.groupedAttributes = updatedGroupedAttributes
        console.log('Grouped Attributes');
        console.dir(this.groupedAttributes);
    }

    get activeSelection() {

        console.log('Active Selection');
        console.dir(JSON.parse(JSON.stringify(this.selection)));
        const activeSelection = [];
       
        const group = this.groupedAttributes[this.selection.type];
        console.log(group);
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
        console.log(JSON.stringify(activeSelection));
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
            console.log('Updated Selection: ' + JSON.stringify(newSelection.attributes));
            // send the updated selection to the parent component
            this.dispatchEvent(new CustomEvent('update', { detail: { newSelection: newSelection, editedField: {field: field, previousValue: previousValue, newValue: value}  }}));
    }
}