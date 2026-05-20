import { LightningElement, wire, api } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { FIELDS } from 'c/neuraFormSchemaUtils';

export default class NeuraForm extends LightningElement {
     // Header Info
     indicatorType = 'ring';
     stepList = []; // array of page names
     currentStep; // value from stepList that is active
     currentStepPercentage; // percentage of current step in stepList
     currentStepIndex; // index of current step in stepList
     totalSteps; // total number of pages
    
     @api formObject; // Added
    
    @api recordId;
    formPages = [];
    formSections = [];
    formQuestions = [];
    formObject;

    pageSteps = [];
    firstStepValue;

    @wire(getRecord, { 
        recordId: '$recordId', 
        fields: [FIELDS.Form_Template__c.Name.fieldApiName] 
    })
    formTemplate;

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Form_Pages__r',
        fields: [
            FIELDS.Form_Page__c.Id.fieldApiName, 
            FIELDS.Form_Page__c.Name.fieldApiName, 
            FIELDS.Form_Page__c.Form_Template__c.fieldApiName, 
            FIELDS.Form_Page__c.Order__c.fieldApiName],
        sortBy: [FIELDS.Form_Page__c.Order__c.fieldApiName]
    })
    wiredFormPages({ error, data }) {
        if (data) {
            console.log('wiredFormPages');
            console.dir(data);
            this.formPages = data.records;
            this.checkDataAndCreateFormObject();
        } else if (error) {
            console.error(error);
        }
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Form_Sections__r',
        fields: [
            FIELDS.Form_Section__c.Id.fieldApiName, 
            FIELDS.Form_Section__c.Name.fieldApiName, 
            FIELDS.Form_Section__c.Form_Page__c.fieldApiName, 
            FIELDS.Form_Section__c.Order__c.fieldApiName, 
            FIELDS.Form_Section__c.Background_Color__c.fieldApiName, 
            FIELDS.Form_Section__c.Padding__c.fieldApiName, 
            FIELDS.Form_Section__c.Column_Size__c.fieldApiName],
        sortBy: [FIELDS.Form_Section__c.Order__c.fieldApiName]
    }) 
    wiredFormSections({ error, data }) {
        if (data) {
            console.log('wiredFormSections');
            console.dir(data);
            this.formSections = data.records;
            this.checkDataAndCreateFormObject();
        } else if (error) {
            console.error(error);
        }
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$recordId',
        relatedListId: 'Form_Questions__r',
        fields: [
            FIELDS.Form_Question__c.Id.fieldApiName, 
            FIELDS.Form_Question__c.Name.fieldApiName, 
            FIELDS.Form_Question__c.Type__c.fieldApiName, 
            FIELDS.Form_Question__c.Form_Section__c.fieldApiName, 
            FIELDS.Form_Question__c.Order__c.fieldApiName, 
            FIELDS.Form_Question__c.Question__c.fieldApiName, 
            FIELDS.Form_Question__c.Label_Visible__.fieldApiName, 
            FIELDS.Form_Question__c.Text_Alignment__c.fieldApiName, 
            FIELDS.Form_Question__c.Font_Size__c.fieldApiName, 
            FIELDS.Form_Question__c.Font_Color__c.fieldApiName, 
            FIELDS.Form_Question__c.Value_Set__c.fieldApiName,
            FIELDS.Form_Question__c.Include_Comment__c.fieldApiName, 
            FIELDS.Form_Question__c.Include_Photo__c.fieldApiName],
        sortBy: [FIELDS.Form_Question__c.Order__c.fieldApiName]
    })
    wiredFormQuestions({ error, data }) {
        if (data) {
            console.log('wiredFormQuestions');
            console.dir(data);
            this.formQuestions = data.records;
            this.checkDataAndCreateFormObject();
        } else if (error) {
            console.error(error);
        }
    }
    
    checkDataAndCreateFormObject() {
        console.log('check');
        if (this.formTemplate && this.formPages.length > 0 && this.formSections.length > 0 && this.formQuestions.length > 0 && !this.formObject) {
            console.log('renderedCallback - createFormObject');
            this.formObject = this.createFormObject(this.formTemplate.data, this.formPages, this.formSections, this.formQuestions);
            this.pageSteps = this.createPageSteps();
            this.firstStepValue = this.pageSteps[0].value;
            console.dir(JSON.stringify(this.formObject));
        }
    }
    

    get name() {
        return this.getFieldFromRecord(FIELDS.Form_Template__c.Name.fieldApiName);
    }

    getFieldFromRecord(fieldName) {
        return getFieldValue(this.formTemplate.data, fieldName);
    }

    createFormObject(formTemplate, formPages, formSections, formQuestions) {
        if (formTemplate && formPages && formSections && formQuestions) {
            return {
                name: formTemplate.name,
                pages: formPages.map(page => ({
                    id : page.id,
                    fields: page.fields,
                    sections: formSections
                        .filter(section => section.fields.Form_Page__c.value === page.id)
                        .map(section => ({
                            id: section.id,
                            fields: section.fields,
                            questions: formQuestions
                                .filter(question => question.fields.Form_Section__c.value === section.id)
                                .map(question => ({
                                    id: question.id,
                                    fields: question.fields
                                }))
                        }))
                }))
            };
        }
    }

    createPageSteps() {
        return this.formObject.pages.map((page, index) => ({
            label: page.name,
            value: index
        }));
    }

    // TODO
    handleFooterButtonClick(event) {
    }

    connectedCallback(){
        console.log('connectedCallback');
        console.log(JSON.stringify(this.formObject));   
    }
}