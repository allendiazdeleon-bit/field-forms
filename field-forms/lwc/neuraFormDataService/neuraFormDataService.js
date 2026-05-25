import { LightningElement, api, wire } from 'lwc';
import { gql, graphql } from 'lightning/uiGraphQLApi';
import { LOADING_TOKENS } from './constants';
import {
    applySnapshotV2,
    normalizeSnapshotChunksFromGraphQL
} from 'c/neuraFormSnapshotV2Utils';

const DEFAULT_STATUS = 'Not Started';
const DEFAULT_COLOR = 'blue';

export default class neuraFormDataService extends LightningElement {
    @api recordId; 
    selectedRecordId;
    formOptions;
    formData;

    runOnce = false;

    selectedForm;

    showSelector = false;
    showForm = false;

    loadingSet = new Set();
    isLoading = false;

    answerIds = [];
    loadAnswersFiles = false;
    
    @api 
    async fetchDataAndTransform(recordId) {
        this.recordId = recordId;
        this.runOnce = false;
        this.setLoading(LOADING_TOKENS.DATA_LOAD, true); // Assuming UI indication

        try {
            const graphQLResult = await graphql(this.query, this.variables);
            if (graphQLResult.data) {
                this.formData = this.transformData(graphQLResult.data.uiapi.query);
                this.formAdditionalStructures(this.formData);

                // Dispatch a custom event signaling that data is ready
                //this.dispatchEvent(new CustomEvent('formdatarready', { detail: this.formData }));

            } else {
                console.error('No data in GraphQL result'); 
            }
        } catch (error) {
            console.error(error); 
            // Dispatch an event to signal data retrieval error
            this.dispatchEvent(new CustomEvent('datafetcherror', { detail: error }));
        } finally {
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false); 
        }
    }

    @wire(graphql, {
    query:  "$query",
    variables: "$variables"})
    graphqlQueryResult({data, errors}){
        this.setLoading(LOADING_TOKENS.DATA_LOAD, true);
        if(data && !this.runOnce){
            console.log('graphqlQueryResult');
            console.dir(data);
            this.formData = this.transformData(data.uiapi.query)
            console.log(JSON.stringify(this.formData));
            this.formAdditionalStructures(this.formData);
            this.runOnce = true;
            this.loadAnswersFiles = true;
        } else if (errors) {
            console.error(errors);
            this.dispatchEvent(new CustomEvent('datafetcherror', { detail: error }));
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
            

        } else {
            console.log('graphqlQueryResult: no data and no errors');
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
        }
    }

    connectedCallback(){
       // this.selectedRecordId = this.recordId;
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

    // Mirrors neuraFormMobile.combineAndTransformJSON. Parses each non-empty
    // JSON-array string and concatenates the parsed items before sorting +
    // joining with the related child rows. Used for Questions_JSON__c when
    // the legacy snapshot overflows into Questions_JSON_1__c / _2__c.
    combineAndTransformJSON(JSONInputArrays, arrayToAdd, keyToAdd, lookupKey) {
        let combinedArray = [];
        JSONInputArrays.forEach(JSONInputs => {
            if (JSONInputs) {
                combinedArray = [...combinedArray, ...JSON.parse(JSONInputs)];
            }
        });
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
        newArray.sort((a, b) => (a.Order__c > b.Order__c) ? 1 : -1);
        return newArray;
    }

    standardTransform(input){
        const newInput = {... input.node};
        // within the node for each key that has a object with the key value. replace the object with the value
        Object.keys(newInput).forEach(key => {
            if (newInput[key]?.value !== undefined) {
                newInput[key] = newInput[key].value;
            }
        })

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
         let newTemplates = graphqlData.Linked_Form__c.edges.map(templateEdge => {
            const linkedTemplate = this.standardTransform(templateEdge);
            let formTemplate = this.relatedTransform(linkedTemplate, 'Form_Template__r');

            // v2 snapshot chunks: promote into the bare JSON keys so the
            // existing transformJSON calls below need no change. When no
            // chunks exist (legacy snapshot still in use), formTemplate is
            // returned unchanged. See docs/snapshot-v2.md.
            formTemplate = applySnapshotV2(formTemplate, normalizeSnapshotChunksFromGraphQL(formTemplate));

            let answers = this.transformEdges(linkedTemplate?.Form_Answers__r);

            this.setAnswerIds(answers);

            // Legacy chunked questions live across _JSON__c / _1 / _2. v2
            // assembly consolidates everything into _JSON__c and nulls the
            // overflow fields, so the same concat covers both modes.
            let questions = this.combineAndTransformJSON(
                [
                    formTemplate?.Questions_JSON__c,
                    formTemplate?.Questions_JSON_1__c,
                    formTemplate?.Questions_JSON_2__c
                ],
                answers,
                'answers',
                'Form_Question__c'
            );
            let sections = this.transformJSON(formTemplate?.Sections_JSON__c, questions, 'questions', 'Form_Section__c');
            let pages = this.transformJSON(formTemplate?.Pages_JSON__c, sections, 'sections', 'Form_Page__c');

            return this.constructFormObject(linkedTemplate, formTemplate, pages);
         });

         return newTemplates;
    }


    constructFormObject(linkedTemplate, formTemplate, pages){
        return {
            Id: formTemplate?.Id,
            Name: formTemplate?.Name,
            Selector_Color__c: formTemplate?.Selector_Color__c,
            linkedForm: {
                Id: linkedTemplate.Id,
                Status__c: linkedTemplate.Status__c,
                Current_Page__c: linkedTemplate.Current_Page__c
            },
            pages: pages
        };
    }

    setAnswerIds(answers) {
        const nextAnswerIds = answers.map((item) => {
            return item.Id
        });
        this.answerIds = [...this.answerIds, ...nextAnswerIds];
    }
    
    handleFilesDataLoad({ detail }) {
        this.loadAnswersFiles = false;

        this.formData.forEach((form) => {
            form.pages.forEach((page) => {
                page.sections.forEach((section) => {
                    section.questions.forEach((question) => {
                        if(question.answers && question.answers.length > 0) {
                            const linkedAnswers = detail.value.ContentDocumentLink.filter((cdl) => {
                                return cdl.LinkedEntityId === question.answers[0].Id;
                            });
                            if(linkedAnswers.length > 0) {
                                if(!question.answers[0].filesData) {
                                    question.answers[0].filesData = [];
                                }
                                let filesData = [];

                                linkedAnswers.forEach((data) => {
                                    const contentVersion = data.ContentDocument.LatestPublishedVersion;
                                    filesData = [
                                        ...filesData,
                                        {
                                            data: contentVersion.VersionDataUrl,
                                            metadata: {
                                                fileName: contentVersion.Title
                                            }
                                        }
                                    ]
                                });
                                
                                question.answers[0].filesData = filesData;
                            }
                        } 
                    });
                });
            });
        });

        this.showSelector = true;
        this.selectedForm = this.formData.find(form => form.linkedForm.Id === this.recordId);
        console.log('Selected Form');
        console.dir(this.selectedForm);
        this.dispatchEvent(new CustomEvent('formdatarready', { detail: this.selectedForm }));
        this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
    }

    get query(){
        console.log('in get query ' + this.recordId);
        if(!this.recordId) return undefined;
        return gql`
        query getFormTemplatesAndAnswers($recordId: ID!) {
            uiapi {
                query {
                    Linked_Form__c(
                        where: { Id: { eq: $recordId } }
                    ) {
                        edges {
                            node {
                                Id
                                Name { value }
                                Form_Template__c { value }
                                Current_Page__c { value }
                                Status__c { value }
                                Form_Template__r: Form_Template__r {
                                    Id
                                    Name { value }
                                    Selector_Color__c { value }
                                    Pages_JSON__c { value }
                                    Sections_JSON__c { value }
                                    Questions_JSON__c { value }
                                    Questions_JSON_1__c { value }
                                    Questions_JSON_2__c { value }
                                    Form_Template_Snapshots__r(first: 200) {
                                        edges {
                                            node {
                                                Id
                                                Payload_Type__c { value }
                                                Chunk_Index__c { value }
                                                Payload__c { value }
                                            }
                                        }
                                    }
                                }
                                Form_Answers__r: Form_Answers__r(first: 500) {
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

    

    formAdditionalStructures(formTemplates){
        let newForms = formTemplates.map(formTemplate => {
            return {
                id: formTemplate.Id,
                name: formTemplate.Name,
                status: formTemplate?.linkedForm?.Status__c ?? DEFAULT_STATUS,
                currentPage: formTemplate?.linkedForm?.Current_Page__c ?? 1,
                totalPages: formTemplate?.pages.length,
                color: formTemplate?.Selector_Color__c ?? DEFAULT_COLOR
            }
        });

        this.formOptions = newForms;
    }
    
    handleFormSelected(event){
        // set selected form to the one matching the id of the event
        try{
            let formId = event.detail;
            if(!formId) return;

            this.selectedForm = this.formData.find(form => form.Id === formId);
            
            this.showForm = true;
            this.showSelector = false;
            console.log('selectedForm: ' + JSON.stringify(this.selectedForm));
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

    get variables() {
        console.log('in get variables ' + this.recordId);
        return {
          recordId: this.recordId,
        };
      }
         
}