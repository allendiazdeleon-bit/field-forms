import { LightningElement, api, wire, track } from 'lwc';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import { LOADING_TOKENS, MESSAGE_VARIANT } from './constants';
import LinkedFormIdField from '@salesforce/schema/Linked_Form__c.Id';
import LinkedFormStatusField from '@salesforce/schema/Linked_Form__c.Status__c';
import LinkedFormPageField from '@salesforce/schema/Linked_Form__c.Current_Page__c';
import { isChangeInDataForGraphQLResult } from 'c/neuraCommonUtility';
import { reduceError } from 'c/nfCommonUtility';

import { FIELDS, OBJECTS } from 'c/neuraFormSchemaUtils';

const DEFAULT_STATUS = 'Not Started';
const DEFAULT_COLOR = 'blue';

export default class NeuraFormMobile extends LightningElement {
    @api recordId; 
    @api objectApiName;

    @api isDesktop = false;

    selectedRecordId;
    formOptions;
    
    @track formData;

    runOnce = false;

    @track selectedForm;

    showSelector = false;
    showForm = false;

    loadingSet = new Set();
    isLoading = false;

    answersId = [];
    loadAnswerFiles = false;

    graphqlQueryResultCalledTimes = 0;

    formId;

    graphqlData;

    shouldDoRefreshGraphQl = true;

    messageObj = {
        message: null,
        variant: null,
        isClosable: false
    }
    
    @wire(graphql, {
    query:  "$query",
    variables: "$variables"})
    graphqlQueryResult(result){
        const {data, errors} = result;
        this.graphqlData = result;

        this.setLoading(LOADING_TOKENS.DATA_LOAD, true);
        if(data && !this.runOnce){
            this.setCriticalInlineMessage(null, null);
            if(this.graphqlQueryResultCalledTimes <= 1) {
                const tempRecordId = this.recordId;

                this.recordId = null;

                this.recordId = tempRecordId;

                this.graphqlQueryResultCalledTimes++;
            }

            if(this.graphqlQueryResultCalledTimes === 2) {
                this.graphqlData = result;
                refreshGraphQL(this.graphqlData);

                this.setLoading(LOADING_TOKENS.REFRESH_LOAD, true);

                this.graphqlQueryResultCalledTimes++;

                setTimeout(() => {
                    this.setLoading(LOADING_TOKENS.REFRESH_LOAD, false);
                }, 2000);
            }

            if(this.graphqlQueryResultCalledTimes === 3) {
                this.initializeForms(data.uiapi.query);
            }
        } else if(isChangeInDataForGraphQLResult(result, this.graphqlData) && this.shouldDoRefreshGraphQl) {
            this.setLoading(LOADING_TOKENS.DATA_LOAD, true);

            this.formData = [];
            this.loadAnswerFiles = false;
            this.formOptions = [];
            this.showSelector = false;

            setTimeout(() => {
                this.initializeForms(data.uiapi.query);
            }, 1);
        } else if (errors) {
            this.setCriticalInlineMessage(reduceError(errors), MESSAGE_VARIANT.ERROR);
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
        } else {
            console.log('graphqlQueryResult: no data and no errors');
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
        }
    }

    initializeForms(queryData) {
        try {
            this.runOnce = true;
            this.showSelector = true;

            this.formData = this.transformData(queryData)
            console.log(JSON.stringify(this.formData));
            this.formAdditionalStructures(this.formData);

            this.loadAnswerFiles = this.answersId.length ? true : false;
        } catch(error) {
            this.setCriticalInlineMessage(reduceError(error), MESSAGE_VARIANT.ERROR);
        } finally {
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
        }
    }

    connectedCallback(){
       //this.setStyleSettings();
    }

     /**
     * Sets the style settings for the neuraFormBuilder component.
     */
     setStyleSettings(){
        if(this.isDesktop){
            this.template.host.style.setProperty('--footer-position', 'relative');
        }
    }

    transformEdges(inputs, arrayToAdd, keyToAdd, lookupKey) {
        if(!inputs) return [];
        const newArray = inputs.edges.map(input => {
            const newInput = this.standardTransform(input);

            if(arrayToAdd) newInput[keyToAdd] = arrayToAdd.filter(arrayItem => arrayItem[lookupKey] === newInput.Id);
            return newInput;
        });

        console.log(newArray);
        return newArray;
    }


    // handles overflow of Questions_JSON__c -> TODO: make this more efficient. 
    combineAndTransformJSON(JSONnputArrays, arrayToAdd, keyToAdd, lookupKey) {
        let combinedArray = [];
        JSONnputArrays.forEach(JSONInputs => {
            if(JSONInputs != null && JSONInputs != undefined && JSONInputs != ""){
                combinedArray = [...combinedArray, ...JSON.parse(JSONInputs)];
            }
        });
        console.log(combinedArray);
        console.log(JSON.stringify(combinedArray));
        return this.transformJSON(JSON.stringify(combinedArray), arrayToAdd, keyToAdd, lookupKey);
    }

    transformJSON(JSONInputs, arrayToAdd, keyToAdd, lookupKey) {
        if(!JSONInputs) return [];
        console.log("JSONInputs: " + JSONInputs);
        const inputs = JSON.parse(JSONInputs);
        const newArray = inputs.map(input => {
            let newInput = {... input}
            if(arrayToAdd) newInput[keyToAdd] = arrayToAdd.filter(arrayItem => arrayItem[lookupKey] === newInput.Id);
            return newInput;
        });

        console.log(newArray);
        // sort by order
        // NOTE: We are assuming the field api names for page, section, and question are all the same, therefore we can use any of them.
        newArray.sort((a, b) => (a[FIELDS.Form_Question__c.Order.fieldApiName] > b[FIELDS.Form_Question__c.Order.fieldApiName]) ? 1 : -1);
        return newArray;
    }

    standardTransform(input){
        const newInput = {... input.node};
        // within the node for each key that has a object with the key value. replace the object with the value
        Object.keys(newInput).forEach(key => {
            if (newInput[key]?.value !== undefined) {
                newInput[key] = newInput[key].value;
            }
        });

        return newInput;
    }

    relatedTransform(input, relatedKey){
        const newInput = {... input[relatedKey]};
        // check for null
        if(!newInput) return undefined;
        // within the node for each key that has a object with the key value. replace the object with the value
        Object.keys(newInput).forEach(key => {
            if (newInput[key]?.value !== undefined) {
                newInput[key] = newInput[key].value;
            }
        })

        return newInput;
    }

    transformData(graphqlData) {
         let newTemplates = graphqlData[OBJECTS.Linked_Form__c.objectApiName].edges.map(templateEdge => {
            const linkedTemplate = this.standardTransform(templateEdge);

            // TO DO: REVIEW for __r relationships.
            let formTemplate = this.relatedTransform(linkedTemplate, 'Form_Template__r');

            let answers = this.transformEdges(linkedTemplate?.Form_Answers__r);

            this.updateAnswerIds(answers);
            let questionJSONArray = [formTemplate?.[FIELDS.Form_Template__c.QuestionsJSON.fieldApiName], formTemplate?.[FIELDS.Form_Template__c.QuestionsJSON1.fieldApiName], formTemplate?.[FIELDS.Form_Template__c.QuestionsJSON2.fieldApiName]];
            let questions = this.combineAndTransformJSON(questionJSONArray, answers, 'answers', OBJECTS.Form_Question__c.objectApiName);
            questions = this.updateRenderingConditions(questions, formTemplate[FIELDS.Form_Template__c.QuestionConditions.fieldApiName]);

            let sections = this.transformJSON(formTemplate?.[FIELDS.Form_Template__c.SectionsJSON.fieldApiName], questions, 'questions', OBJECTS.Form_Section__c.objectApiName);
            sections = this.updateRenderingConditions(sections, formTemplate[FIELDS.Form_Template__c.SectionConditions.fieldApiName]);
            
            let pages = this.transformJSON(formTemplate?.[FIELDS.Form_Template__c.PagesJSON.fieldApiName], sections, 'sections', OBJECTS.Form_Page__c.objectApiName);
            pages = this.updateRenderingConditions(pages, formTemplate[FIELDS.Form_Template__c.PageConditions.fieldApiName]);

            return this.constructFormObject(linkedTemplate, formTemplate, pages);
         });
 
         return newTemplates;
    }

    updateRenderingConditions(jsonObject, conditionJson) {
        let conditions = [];
        if(conditionJson) {
            conditions = JSON.parse(conditionJson);
        }

        return jsonObject.map((item) => {
            let renderCondition = conditions.find((condition) => {
                return item.Id === condition.id;
            });


            if(renderCondition) {
                if(!renderCondition.customLogic.length && !renderCondition.conditions.length) {
                    return {
                        ...item,
                        renderingCondition: null,
                        shouldRender: true
                    }
                }

                return {
                    ...item,
                    renderingCondition: renderCondition,
                    shouldRender: false
                }
            }

            return {
                ...item,
                renderingCondition: null,
                shouldRender: true
            }
        });
    }

    updateAnswerIds(answers) {
        const ids = answers.map((ans) => {
            return ans.Id;
        });
        this.answersId = [...this.answersId, ...ids];
    }

    constructFormObject(linkedTemplate, formTemplate, pages){
        const formObject = {
            Id: formTemplate?.Id,
            Name: formTemplate?.Name,
            pages: pages
        };

        formObject[FIELDS.Form_Template__c.SelectorColor.fieldApiName] = formTemplate?.[FIELDS.Form_Template__c.SelectorColor.fieldApiName] ?? DEFAULT_COLOR;

        const linkedForm = {
            Id: linkedTemplate.Id
        };
        linkedForm[FIELDS.Linked_Form__c.Status.fieldApiName] = linkedTemplate?.[FIELDS.Linked_Form__c.Status.fieldApiName] ?? DEFAULT_STATUS;
        linkedForm[FIELDS.Linked_Form__c.CurrentPage.fieldApiName] = linkedTemplate?.[FIELDS.Linked_Form__c.CurrentPage.fieldApiName];

        formObject['linkedForm'] = linkedForm;

        return formObject;
    }

    handleFilesLoad({ detail }) {
        const allContentDocumentLinks = detail.value.ContentDocumentLink;

        if(allContentDocumentLinks.length) {
            this.formData.forEach((form) => {
                form.pages.forEach((page) => {
                    page.sections.forEach((section) => {
                        section.questions.forEach((question) => {
                            if(question.answers.length) {
                                const answer = question.answers[0];
                                const contenDocumentLinks = allContentDocumentLinks.filter((cdl) => {
                                    return cdl.LinkedEntityId === answer.Id;
                                });

                                let filesData = [];

                                contenDocumentLinks.forEach((cdl) => {
                                    const publishedVersion = cdl.ContentDocument.LatestPublishedVersion;
                                    filesData.push({
                                        data: publishedVersion.VersionDataUrl, //+ '?thumb=THUMB240BY180'
                                        metadata: {
                                            fileName: publishedVersion.Title
                                        }
                                    });
                                });

                                question.answers[0].filesData = [...filesData];
                            }
                        });
                    });
                });
            });
        } else {
            this.formData.forEach((form) => {
                form.pages.forEach((page) => {
                    page.sections.forEach((section) => {
                        section.questions.forEach((question) => {
                            if(question.answers.length) {
                                question.answers[0].filesData = [];
                            }
                        });
                    });
                });
            });
        }

        this.runOnce = true;
        this.showSelector = true;
        this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
    }

    handleFileDataErrors({ detail }) {
        this.setCriticalInlineMessage(reduceError(detail), MESSAGE_VARIANT.ERROR);

        this.runOnce = true;
        this.showSelector = true;
        this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
    } 

    handleFormRendererError({detail}) {
        this.setCriticalInlineMessage(reduceError(detail), MESSAGE_VARIANT.ERROR);
    }

    get query(){
        if(!this.recordId) return undefined;

        if(this.objectApiName === 'WorkOrder') {
            return gql`query getFormTemplatesAndAnswers($recordId: ID!) {
                uiapi {
                    query {
                        Linked_Form__c(
                            where: { Work_Order__c : { eq: $recordId } }
                        ) {
                            edges {
                                node {
                                    Id
                                    Name { value }
                                    Form_Template__c { value }
                                    Current_Page__c { value }
                                    Status__c { value }
                                    Form_Template__r : Form_Template__r { 
                                        Id 
                                        Name { value }
                                        Selector_Color__c { value }
                                        Pages_JSON__c { value }
                                        Sections_JSON__c { value }
                                        Questions_JSON__c { value }
                                        Questions_JSON_1__c { value }
                                        Questions_JSON_2__c { value }
                                        Page_Conditions__c { value }
                                        Section_Conditions__c { value }
                                        Question_Conditions__c { value }
                                    }
                                    Form_Answers__r : Form_Answers__r(first: 500) {
                                        edges {
                                            node {
                                                Id
                                                Name { value }
                                                Form_Question__c { value }
                                                Answer__c { value }
                                                Related_Comment__c { value }
                                                Type__c { value }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }`;
        } else if(this.objectApiName === 'WorkOrderLineItem') {
            return gql`query getFormTemplatesAndAnswers($recordId: ID!) {
                uiapi {
                    query {
                        Linked_Form__c(
                            where: { Work_Order_Line_Item__c : { eq: $recordId } }
                        ) {
                            edges {
                                node {
                                    Id
                                    Name { value }
                                    Form_Template__c { value }
                                    Current_Page__c { value }
                                    Status__c { value }
                                    Form_Template__r : Form_Template__r { 
                                        Id 
                                        Name { value }
                                        Selector_Color__c { value }
                                        Pages_JSON__c { value }
                                        Sections_JSON__c { value }
                                        Questions_JSON__c { value }
                                        Questions_JSON_1__c { value }
                                        Questions_JSON_2__c { value }
                                        Page_Conditions__c { value }
                                        Section_Conditions__c { value }
                                        Question_Conditions__c { value }
                                    }
                                    Form_Answers__r : Form_Answers__r(first: 500) {
                                        edges {
                                            node {
                                                Id
                                                Name { value }
                                                Form_Question__c { value }
                                                Answer__c { value }
                                                Related_Comment__c { value }
                                                Type__c { value }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }`;
        } else if(this.objectApiName === 'ServiceAppointment') {
            return gql`query getFormTemplatesAndAnswers($recordId: ID!) {
                uiapi {
                    query {
                        Linked_Form__c(
                            where: { Service_Appointment__c : { eq: $recordId } }
                        ) {
                            edges {
                                node {
                                    Id
                                    Name { value }
                                    Form_Template__c { value }
                                    Current_Page__c { value }
                                    Status__c { value }
                                    Form_Template__r : Form_Template__r { 
                                        Id 
                                        Name { value }
                                        Selector_Color__c { value }
                                        Pages_JSON__c { value }
                                        Sections_JSON__c { value }
                                        Questions_JSON__c { value }
                                        Questions_JSON_1__c { value }
                                        Questions_JSON_2__c { value }
                                        Page_Conditions__c { value }
                                        Section_Conditions__c { value }
                                        Question_Conditions__c { value }
                                    }
                                    Form_Answers__r : Form_Answers__r(first: 500) {
                                        edges {
                                            node {
                                                Id
                                                Name { value }
                                                Form_Question__c { value }
                                                Answer__c { value }
                                                Related_Comment__c { value }
                                                Type__c { value }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }`;
        }

        return undefined
    }

    formAdditionalStructures(formTemplates){
        let newForms = formTemplates.map(formTemplate => {
            return {
                id: formTemplate.Id,
                name: formTemplate.Name,
                status: formTemplate?.linkedForm?.[FIELDS.Linked_Form__c.Status.fieldApiName] ?? DEFAULT_STATUS,
                currentPage: formTemplate?.linkedForm?.[FIELDS.Linked_Form__c.CurrentPage.fieldApiName] ?? 1,
                totalPages: formTemplate?.pages.length,
                color: formTemplate?.[FIELDS.Form_Template__c.SelectorColor.fieldApiName] ?? DEFAULT_COLOR,
                linkedFormId: formTemplate?.linkedForm?.Id
            }
        });

        this.formOptions = newForms;
    }
    
    handleFormSelected(event){
        // set selected form to the one matching the id of the event
        this.shouldDoRefreshGraphQl = false;

        try{
            this.formId = event.detail;
            if(!this.formId) return;

            this.selectedForm = this.formData.find(form => form.Id === this.formId);
            
            this.showForm = true;
            this.showSelector = false;
        } catch (err){
            console.error(err);
        }
    }

    handleRunQuery(){
        this.selectedRecordId = this.recordId;
    }

    handleReturnToHome(){
        this.showForm = false;
        this.showSelector = true;
        this.selectedForm = undefined;
    }

    handleFooterClick({ detail }) {
        this.setLoading(LOADING_TOKENS.FOOTER_CLICK_LOAD, detail);
    }

    handleCaptureGeolocation({ detail }) {
        this.setLoading(LOADING_TOKENS.GEOLOCATION_LOAD, detail);
    }

    setLoading(loadingToken, isLoading) {
        if(isLoading) {
            this.loadingSet.add(loadingToken);
        } else {
            this.loadingSet.delete(loadingToken);
        }  

        if(this.loadingSet.size) {
            this.isLoading = true;
        } else {
            this.isLoading = false;
        }
    }

    handleUpdateLinkedFormDetails({ detail }) {
        const updateLinkedForm = detail.value;

        const formIndex = this.formOptions.findIndex((item) => {
            return item.linkedFormId === updateLinkedForm[LinkedFormIdField.fieldApiName]
        });
        if(formIndex !== -1) {
            this.formOptions[formIndex] = {
                ...this.formOptions[formIndex],
                status: updateLinkedForm[LinkedFormStatusField.fieldApiName],
                currentPage: updateLinkedForm[LinkedFormPageField.fieldApiName]
            };
        }

        let tempFormData = [...this.formData];
        const formDataIndex = tempFormData.findIndex((item) => {
            return item[LinkedFormIdField.fieldApiName] === updateLinkedForm[LinkedFormIdField.fieldApiName];
        });

        if(formDataIndex !== -1) { 
            const updatedLinkedForm = {...tempFormData[formIndex].linkedForm};

            updateLinkedForm[LinkedFormPageField.fieldApiName] = updateLinkedForm[LinkedFormPageField.fieldApiName];
            updateLinkedForm[LinkedFormStatusField.fieldApiName] = updateLinkedForm[LinkedFormStatusField.fieldApiName];

            tempFormData[formIndex] = {
                ...tempFormData[formIndex],
                linkedForm: updatedLinkedForm
            };
        }

        this.formData = [...tempFormData];
    }

    handleUpdateFormData({ detail }) {
        let tempFormData = [...this.formData];

        const updatedForm = detail.value;

        const formIndex = tempFormData.findIndex((item) => {
            return item[LinkedFormIdField.fieldApiName] === updatedForm[LinkedFormIdField.fieldApiName];
        });

        if(formIndex !== -1) { 
            tempFormData[formIndex] = {
                ...updatedForm
            };
        }

        this.formData = [...tempFormData];

        this.selectedForm = this.formData.find(form => form.Id === this.formId);
    }

    setCriticalInlineMessage(message, variant) {
        this.messageObj = {
            ...this.messageObj,
            message: message,
            variant: variant,
            isClosable: false
        };
    }

    get variables() {
        return {
          recordId: this.recordId
        };
    }
         
    get showInlineMessage() {
        return this.messageObj.message;
    }

    /** Once INQ is a support graphql operator this can be utilized
    get queryFuture(){
        console.log('in get query ' + this.recordId);
        if(!this.recordId) return undefined;
        return gql`
        query getFormTemplatesAndAnswers($recordId: ID!) {
            uiapi {
                query {
                    Form_Template__c (where: {
                        Id: { inq: {
                            Linked_Form__c: {
                                Work_Order__c: { eq: $recordId } 
                            },
                            ApiName: "Form_Template__c"
                        }}
                    }) {
                        edges {
                            node {
                                Id
                                Name { value }
                                Selector_Color__c { value }
                                Form_Pages__r ( 
                                    orderBy: { Order__c: { order: ASC } }
                                )   {
                                    edges {
                                        node {
                                            Id
                                            Name { value }
                                            Form_Template__c { value }
                                            Order__c { value }
                                            Title__c { value }
                                        }
                                    }
                                }
                                Form_Sections__r( 
                                    orderBy: { Order__c: { order: ASC } }
                                ) {
                                    edges {
                                        node {
                                            Id
                                            Name { value }
                                            Form_Page__c { value }
                                            Order__c { value }
                                            Background_Color__c { value }
                                            Padding__c { value }
                                            Column_Size__c { value }
                                        }
                                    }
                                }
                                Form_Questions__r ( 
                                    orderBy: { Order__c: { order: ASC } }
                                ) {
                                    edges {
                                        node {
                                            Id
                                            Name { value }
                                            Form_Section__c { value }
                                            Order__c { value }
                                            Question__c { value }
                                            Label_Visible__c { value }
                                            Text_Alignment__c { value }
                                            Font_Size__c { value }
                                            Font_Color__c { value }
                                            Value_Set__c { value }
                                            Include_Comment__c { value }
                                            Include_Photo__c { value }
                                            Type__c { value }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Form_Answer__c (where: {
                        Linked_Form__c: { inq: {
                            Linked_Form__c: {
                                Work_Order__c: { eq: $recordId }
                            },
                            ApiName: "Id"
                        }}
                    }) {
                        edges {
                            node {
                                Id
                                Name { value }
                                Form_Question__c { value }
                            }
                        }
                    }
                    Linked_Form__c (where: { Work_Order__c: { eq: $recordId } }) {
                        edges {
                            node {
                                Id
                                Name { value }
                                Form_Template__c { value }
                                Current_Page__c { value }
                                Status__c { value }
                            }
                        }
                    }
                }
            }
        }`;
    }
    */

    /** Once INQ is a support graphql operator this can be utilized
    transformDataFuture(graphqlData) {
        // Build List of Form Templates with placeholder for Pages
        console.dir(graphqlData);
        let answers = this.transformEdges(graphqlData.Form_Answer__c);
        let linkedForms = this.transformEdges(graphqlData.Linked_Form__c);

        console.log('answers: ' + JSON.stringify(answers) );
        let newTemplates = graphqlData.Form_Template__c.edges.map(templateEdge => {
            const template = this.standardTransform(templateEdge);
            

            // figure out pages
            let questions = this.transformEdges(template?.Form_Questions__r, answers, 'answers', 'Form_Question__c');
            let sections = this.transformEdges(template?.Form_Sections__r, questions, 'questions', 'Form_Section__c');
            let pages = this.transformEdges(template?.Form_Pages__r, sections, 'sections', 'Form_Page__c');
            // figure out sections

            // figure out quuestions

            // remove all keys that end in __r
            Object.keys(template).forEach(key => {
                if(key.endsWith('__r')){
                    delete template[key];
                }
            });
            let matchingLinkedForm = linkedForms.find(linkedForm => linkedForm.Form_Template__c === template.Id);
            return { ...template, linkedForm: matchingLinkedForm, pages: pages };
        });

        return newTemplates;

        
    }
    */
}