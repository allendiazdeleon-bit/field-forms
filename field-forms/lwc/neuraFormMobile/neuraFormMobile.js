import { LightningElement, api, wire, track } from 'lwc';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import { getRecord } from 'lightning/uiRecordApi';
import formFactorPropertyName from '@salesforce/client/formFactor';
import { LOADING_TOKENS, MESSAGE_VARIANT, FORM_ANSWER_FETCH_LIMIT } from './constants';
import LinkedFormIdField from '@salesforce/schema/Linked_Form__c.Id';
import LinkedFormStatusField from '@salesforce/schema/Linked_Form__c.Status__c';
import LinkedFormPageField from '@salesforce/schema/Linked_Form__c.Current_Page__c';
import { isChangeInDataForGraphQLResult } from 'c/neuraCommonUtility';
import { reduceError } from 'c/nfCommonUtility';

import { FIELDS, OBJECTS } from 'c/neuraFormSchemaUtils';
import {
    createDraftLinkedForm,
    parentLookupFieldFor,
    buildFormObjectFromPrimedTemplate,
    templateFieldsForDraftLoad
} from './draftFormHelpers';

const DEFAULT_STATUS = 'Not Started';
const DEFAULT_COLOR = 'blue';

export default class NeuraFormMobile extends LightningElement {
    @api recordId;
    @api objectApiName;

    // Drive layout from the runtime form factor instead of a build-time admin toggle.
    // formFactorPropertyName returns "Large" on Lightning Experience desktop, "Medium"
    // on tablets, and "Small" on phones AND in LWC Offline (FSL Mobile) regardless of
    // device, which is the behavior we want here.
    get isDesktop() {
        return formFactorPropertyName === 'Large';
    }

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
    
    @track selectedLinkedFormId;

    @wire(graphql, {
        query: '$listQuery',
        variables: '$listVariables'
    })
    listQueryResult(result) {
        const { data, errors } = result;
        this.listGraphqlData = result;

        if (errors) {
            this.setCriticalInlineMessage(reduceError(errors), MESSAGE_VARIANT.ERROR);
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
            return;
        }
        if (!data) return;

        const next = data.uiapi.query;
        if (this.listInitialised && !isChangeInDataForGraphQLResult(result, this._lastListResult)) {
            return;
        }
        this._lastListResult = result;
        this.setCriticalInlineMessage(null, null);

        try {
            this.formData = this.transformListData(next);
            this.formAdditionalStructures(this.formData);
            this.showSelector = true;
            this.listInitialised = true;
        } catch (e) {
            this.setCriticalInlineMessage(reduceError(e), MESSAGE_VARIANT.ERROR);
        } finally {
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
        }
    }

    @wire(graphql, {
        query: '$detailsQuery',
        variables: '$detailsVariables'
    })
    detailsQueryResult(result) {
        const { data, errors } = result;
        this.detailsGraphqlData = result;

        if (errors) {
            this.setCriticalInlineMessage(reduceError(errors), MESSAGE_VARIANT.ERROR);
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
            return;
        }
        if (!data) return;

        try {
            const queryData = data.uiapi.query;
            const fullForm = this.transformDetailData(queryData);
            if (!fullForm) return;

            // Replace the lightweight entry in formData with the full structure.
            this.formData = this.formData.map(f =>
                f?.linkedForm?.Id === fullForm.linkedForm.Id ? fullForm : f
            );
            this.selectedForm = fullForm;
            this.showForm = true;
            this.showSelector = false;

            this.loadAnswerFiles = this.answersId.length > 0;
        } catch (e) {
            this.setCriticalInlineMessage(reduceError(e), MESSAGE_VARIANT.ERROR);
        } finally {
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
        }
    }

    // --- B4: draft-parent fallback -------------------------------------------
    //
    // When listQuery returns zero Linked_Form rows we ask: is the host record
    // itself a draft (or simply unprovisioned)? If a Default_Form exists for
    // its WorkType, surface it as a "Start offline form" action so the field
    // tech can begin filling it locally without waiting for sync.

    @track availableDefaultForms = [];
    @track parentWorkTypeId;

    // getRecord wire to read the host's WorkTypeId. Field paths differ per
    // parent SObject; the getter returns the right one and undefined when the
    // host type isn't supported (in which case the wire is skipped).
    get hostRecordFields() {
        switch (this.objectApiName) {
            case 'WorkOrder':
                return ['WorkOrder.WorkTypeId'];
            case 'ServiceAppointment':
                return ['ServiceAppointment.WorkTypeId'];
            case 'WorkOrderLineItem':
                return ['WorkOrderLineItem.WorkTypeId'];
            default:
                return undefined;
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: '$hostRecordFields' })
    hostRecordResult({ data, error }) {
        if (error) {
            // Non-fatal; the draft-parent fallback simply won't activate.
            return;
        }
        if (data) {
            const fieldKey = (this.hostRecordFields || [])[0]
                ?.split('.')?.[1];
            this.parentWorkTypeId = data.fields?.[fieldKey]?.value;
        }
    }

    // GraphQL query for Default_Form mappings tied to this host's WorkType.
    // Kept separate from listQuery so it can run independently and doesn't
    // bloat the primary list response.
    get defaultFormsQuery() {
        if (!this.parentWorkTypeId) return undefined;
        return gql`query getDefaultFormsForWorkType($workTypeId: ID!) {
            uiapi {
                query {
                    Default_Form__c(
                        where: { Work_Type__c : { eq: $workTypeId } }
                    ) {
                        edges {
                            node {
                                Id
                                Form_Template__c { value }
                                Form_Template__r : Form_Template__r {
                                    Id
                                    Name { value }
                                    Selector_Color__c { value }
                                }
                            }
                        }
                    }
                }
            }
        }`;
    }

    get defaultFormsVariables() {
        return this.parentWorkTypeId
            ? { workTypeId: this.parentWorkTypeId }
            : undefined;
    }

    @wire(graphql, {
        query: '$defaultFormsQuery',
        variables: '$defaultFormsVariables'
    })
    defaultFormsResult({ data }) {
        if (!data) return;
        const edges = data.uiapi?.query?.Default_Form__c?.edges || [];
        this.availableDefaultForms = edges.map(e => {
            const node = e.node || {};
            const tpl = node.Form_Template__r || {};
            return {
                defaultFormId: node.Id,
                formTemplateId: node.Form_Template__c?.value,
                formTemplateName: tpl.Name?.value || 'Form',
                color: tpl.Selector_Color__c?.value || DEFAULT_COLOR
            };
        });
    }

    get shouldOfferDraftFallback() {
        return (
            this.listInitialised &&
            (!this.formData || this.formData.length === 0) &&
            this.availableDefaultForms.length > 0 &&
            !!parentLookupFieldFor(this.objectApiName)
        );
    }

    async handleCreateDraftForm(event) {
        const formTemplateId = event.currentTarget?.dataset?.templateId;
        const def = this.availableDefaultForms.find(
            d => d.formTemplateId === formTemplateId
        );
        if (!def) return;

        const parentField = parentLookupFieldFor(this.objectApiName);
        if (!parentField) return;

        this.setLoading(LOADING_TOKENS.DATA_LOAD, true);
        try {
            const result = await createDraftLinkedForm({
                formTemplateId,
                parentField,
                parentRecordId: this.recordId
            });
            const draftLinkedFormId = result.id;

            // Inject a lightweight formData entry so the selector shows it.
            // Drafts won't reappear in listQuery until the parent syncs, so
            // we maintain them in memory.
            const linkedForm = { Id: draftLinkedFormId };
            linkedForm[FIELDS.Linked_Form__c.Status.fieldApiName] = 'Not Started';
            linkedForm[FIELDS.Linked_Form__c.CurrentPage.fieldApiName] = 1;
            const lightweight = {
                Id: formTemplateId,
                Name: def.formTemplateName,
                pages: [],
                linkedForm,
                isDraft: true
            };
            lightweight[FIELDS.Form_Template__c.SelectorColor.fieldApiName] = def.color;

            this.formData = [...this.formData, lightweight];
            this.formAdditionalStructures(this.formData);
        } catch (err) {
            this.setCriticalInlineMessage(reduceError(err), MESSAGE_VARIANT.ERROR);
        } finally {
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
        }
    }

    // When the user selects a *draft* Linked_Form, the GraphQL detailsQuery
    // won't return it (LDS drafts aren't queryable via uiGraphQLApi). Instead,
    // pull the Form_Template via getRecord (which works against primed data
    // offline) and rebuild the form structure client-side.
    @track _draftTemplateIdForFetch;

    @wire(getRecord, {
        recordId: '$_draftTemplateIdForFetch',
        fields: templateFieldsForDraftLoad()
    })
    draftTemplateResult({ data, error }) {
        if (error) {
            this.setCriticalInlineMessage(reduceError(error), MESSAGE_VARIANT.ERROR);
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
            return;
        }
        if (!data || !this._pendingDraftLinkedFormId) return;

        try {
            const fullForm = buildFormObjectFromPrimedTemplate({
                templateRecord: data,
                draftLinkedFormId: this._pendingDraftLinkedFormId,
                transforms: {
                    combineAndTransformJSON: this.combineAndTransformJSON.bind(this),
                    transformJSON: this.transformJSON.bind(this),
                    updateRenderingConditions: this.updateRenderingConditions.bind(this)
                }
            });
            if (!fullForm) return;

            this.formData = this.formData.map(f =>
                f?.linkedForm?.Id === fullForm.linkedForm.Id ? fullForm : f
            );
            this.selectedForm = fullForm;
            this.showForm = true;
            this.showSelector = false;
        } catch (e) {
            this.setCriticalInlineMessage(reduceError(e), MESSAGE_VARIANT.ERROR);
        } finally {
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
        }
    }

    // -------------------------------------------------------------------------

    // Retained for backwards-compat callers; legacy mobile builds expected this
    // single bootstrap method. The new wire pipeline calls transformListData
    // directly, so this is now a thin shim.
    initializeForms(queryData) {
        try {
            this.formData = this.transformListData(queryData);
            this.formAdditionalStructures(this.formData);
            this.showSelector = true;
            this.listInitialised = true;
        } catch (error) {
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

    // Lightweight transform — builds selector/list data without the heavy JSON
    // snapshot fields or Form_Answers. Pages start empty; they're populated by
    // transformDetailData when the user picks a form.
    transformListData(graphqlData) {
        const edges = graphqlData?.[OBJECTS.Linked_Form__c.objectApiName]?.edges || [];
        return edges.map(templateEdge => {
            const linkedTemplate = this.standardTransform(templateEdge);
            const formTemplate = this.relatedTransform(linkedTemplate, 'Form_Template__r') || {};
            return this.constructFormObject(linkedTemplate, formTemplate, []);
        });
    }

    // Heavy transform — runs only for the single selected Linked_Form. Builds
    // the full pages/sections/questions/answers structure consumed by the
    // renderer. Same shape as the prior transformData() return value.
    transformDetailData(graphqlData) {
        const edges = graphqlData?.[OBJECTS.Linked_Form__c.objectApiName]?.edges || [];
        if (!edges.length) return undefined;

        const templateEdge = edges[0];
        const linkedTemplate = this.standardTransform(templateEdge);
        const formTemplate = this.relatedTransform(linkedTemplate, 'Form_Template__r');

        const answers = this.transformEdges(linkedTemplate?.Form_Answers__r);

        if (linkedTemplate?.Form_Answers__r?.edges?.length >= FORM_ANSWER_FETCH_LIMIT) {
            this.setCriticalInlineMessage(
                `Only the first ${FORM_ANSWER_FETCH_LIMIT} answers were loaded for this form. Some previous answers may be missing.`,
                MESSAGE_VARIANT.WARN
            );
        }

        this.updateAnswerIds(answers);

        const questionJSONArray = [
            formTemplate?.[FIELDS.Form_Template__c.QuestionsJSON.fieldApiName],
            formTemplate?.[FIELDS.Form_Template__c.QuestionsJSON1.fieldApiName],
            formTemplate?.[FIELDS.Form_Template__c.QuestionsJSON2.fieldApiName]
        ];
        let questions = this.combineAndTransformJSON(questionJSONArray, answers, 'answers', OBJECTS.Form_Question__c.objectApiName);
        questions = this.updateRenderingConditions(questions, formTemplate[FIELDS.Form_Template__c.QuestionConditions.fieldApiName]);

        let sections = this.transformJSON(formTemplate?.[FIELDS.Form_Template__c.SectionsJSON.fieldApiName], questions, 'questions', OBJECTS.Form_Section__c.objectApiName);
        sections = this.updateRenderingConditions(sections, formTemplate[FIELDS.Form_Template__c.SectionConditions.fieldApiName]);

        let pages = this.transformJSON(formTemplate?.[FIELDS.Form_Template__c.PagesJSON.fieldApiName], sections, 'sections', OBJECTS.Form_Page__c.objectApiName);
        pages = this.updateRenderingConditions(pages, formTemplate[FIELDS.Form_Template__c.PageConditions.fieldApiName]);

        return this.constructFormObject(linkedTemplate, formTemplate, pages);
    }

    // Back-compat shim. External callers (and our own legacy code paths) may
    // still invoke transformData(); route them to the list transform.
    transformData(graphqlData) {
        return this.transformListData(graphqlData);
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

    handleFormRendererMessage({ detail }) {
        const variant = detail?.variant === 'error'
            ? MESSAGE_VARIANT.ERROR
            : detail?.variant === 'warning'
                ? MESSAGE_VARIANT.WARN
                : MESSAGE_VARIANT.INFO;

        this.messageObj = {
            message: detail?.message ?? '',
            variant,
            isClosable: true
        };
    }

    // The mobile component issues two separate GraphQL queries to stay under the
    // 32 KB offline GraphQL response limit:
    //
    //   listQuery     — lightweight: Linked_Form rows + Form_Template selector
    //                   metadata. Drives the form-picker UI. Always running.
    //   detailsQuery  — heavy: JSON snapshot fields and Form_Answers for ONE
    //                   selected Linked_Form. Only fires after handleFormSelected
    //                   sets selectedLinkedFormId.
    //
    // The previous implementation fetched both in a single query per parent,
    // which pulled five long-text fields (each up to 131,072 chars) plus 500
    // answers in a single round trip — far over the offline limit.

    get parentRelationshipField() {
        switch (this.objectApiName) {
            case 'WorkOrder':
                return 'Work_Order__c';
            case 'WorkOrderLineItem':
                return 'Work_Order_Line_Item__c';
            case 'ServiceAppointment':
                return 'Service_Appointment__c';
            default:
                return undefined;
        }
    }

    get listQuery() {
        if (!this.recordId || !this.parentRelationshipField) return undefined;
        const parentField = this.parentRelationshipField;

        return gql`query getFormTemplatesList($recordId: ID!) {
            uiapi {
                query {
                    Linked_Form__c(
                        where: { ${parentField} : { eq: $recordId } }
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
                                }
                            }
                        }
                    }
                }
            }
        }`;
    }

    get detailsQuery() {
        if (!this.selectedLinkedFormId) return undefined;

        return gql`query getFormTemplateDetails($linkedFormId: ID!) {
            uiapi {
                query {
                    Linked_Form__c(
                        where: { Id : { eq: $linkedFormId } }
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
        // event.detail is the Form_Template Id; we need the Linked_Form Id to
        // drive the details wire.
        this.shouldDoRefreshGraphQl = false;

        try{
            this.formId = event.detail;
            if(!this.formId) return;

            const targetEntry = this.formData.find(form => form.Id === this.formId);
            const linkedFormId = targetEntry?.linkedForm?.Id;
            if (!linkedFormId) {
                this.setCriticalInlineMessage(
                    'This form has no linked record yet. Try refreshing.',
                    MESSAGE_VARIANT.WARN
                );
                return;
            }

            this.setLoading(LOADING_TOKENS.DATA_LOAD, true);
            // If the same form is already fully loaded, surface it directly;
            // otherwise route by storage state:
            //   - draft Linked_Form  -> fetch the Form_Template via getRecord
            //     (GraphQL won't return drafts).
            //   - persisted Linked_Form -> trigger the detailsQuery wire.
            if (targetEntry.pages && targetEntry.pages.length > 0) {
                this.selectedForm = targetEntry;
                this.showForm = true;
                this.showSelector = false;
                this.loadAnswerFiles = this.answersId.length > 0;
                this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
            } else if (targetEntry.isDraft) {
                this._pendingDraftLinkedFormId = linkedFormId;
                this._draftTemplateIdForFetch = targetEntry.Id;
            } else {
                this.selectedLinkedFormId = linkedFormId;
            }
        } catch (err){
            console.error(err);
            this.setLoading(LOADING_TOKENS.DATA_LOAD, false);
        }
    }

    handleRunQuery(){
        this.selectedRecordId = this.recordId;
    }

    handleReturnToHome(){
        this.showForm = false;
        this.showSelector = true;
        this.selectedForm = undefined;
        // Clearing selectedLinkedFormId stops the details wire from re-firing
        // until the user picks another form. Same for the draft fetch.
        this.selectedLinkedFormId = undefined;
        this._draftTemplateIdForFetch = undefined;
        this._pendingDraftLinkedFormId = undefined;
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

    get listVariables() {
        return { recordId: this.recordId };
    }

    get detailsVariables() {
        return this.selectedLinkedFormId
            ? { linkedFormId: this.selectedLinkedFormId }
            : undefined;
    }

    // Back-compat alias for callers that still reference $variables.
    get variables() {
        return this.listVariables;
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