import { LightningElement, api } from 'lwc';
import { FIELDS } from 'c/neuraFormSchemaUtils';

export default class NeuraFormCriteriaLine extends LightningElement {
    @api
    isPopoverOpen = false;
    
    @api
    variant;
    
    @api
    condition;
    
    @api
    index;

    @api
    selection;
    
    @api
    questions = [];

    // allConfiguration is rebroadcast by the store when the builder mutates
    // the page/section/question structure. Convert the @api property into a
    // getter/setter so the option lists rebuild every time it changes - the
    // previous version only computed them in connectedCallback and went
    // stale once the user edited the form after opening a popover.
    _allConfiguration = [];

    @api
    get allConfiguration() {
        return this._allConfiguration;
    }
    set allConfiguration(value) {
        this._allConfiguration = value || [];
        // Re-derive option lists. Preserve currently-filtered slices by
        // re-applying the active page/section filters.
        this.initializeOptions();
        if (this.page) this.filterSections(this.page);
        if (this.section) this.filterQuestions(this.section);
    }

    questionOptions = [];

    filteredQuestionOptions = [];

    sectionOptions = [];

    filteredSectionOptions = [];
    
    pageOptions = [];

    @api
    logicalOperator;

    page;

    section;

    resource;

    operater;

    value;

    operatorOptions = [];

    allOperators = [
        { "label": "Equals", "value": "equals" },
        { "label": "Does Not Equal", "value": "notEquals" },
        { "label": "Greater Than", "value": "greaterThan" },
        { "label": "Less Than", "value": "lessThan" },
        { "label": "Greater Than or Equal", "value": "greaterThanOrEqual" },
        { "label": "Less Than or Equal", "value": "lessThanOrEqual" },
        { "label": "In List", "value": "inList" },
        { "label": "Not In List", "value": "notInList" },
        { "label": "Contains", "value": "contains" },
        { "label": "Starts With", "value": "startsWith" },
        { "label": "Ends With", "value": "endsWith" },
        { "label": "Regular Expression", "value": "regex" },
        { "label": "Is True", "value": "isTrue" },
        { "label": "Is False", "value": "isFalse" }
    ]

    validOperators = {
        "checkbox": ["equals", "notEquals"],
        "date": ["equals", "notEquals", "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual", "inList", "notInList"],
        "dropdown": ["equals", "notEquals", "inList", "notInList"],
        "email": ["equals", "notEquals", "contains", "startsWith", "endsWith", "inList", "notInList", "regex"],
        "file upload": ["equals", "notEquals"],
        "form": ["equals", "notEquals"],
        "geolocation": ["equals", "notEquals", "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual", "inList", "notInList"],
        "multiple choice": ["equals", "notEquals", "inList", "notInList"],
        "number": ["equals", "notEquals", "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual", "inList", "notInList"],
        "phone": ["equals", "notEquals", "contains", "startsWith", "endsWith", "inList", "notInList"],
        "radio buttons": ["equals", "notEquals"],
        "rating": ["equals", "notEquals", "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual", "inList", "notInList"],
        "scan barcode": ["equals", "notEquals", "contains", "startsWith", "endsWith", "inList", "notInList"],
        "signature": ["isTrue", "isFalse"],
        "slider": ["equals", "notEquals", "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual", "inList", "notInList"],
        "text": ["equals", "notEquals", "contains", "startsWith", "endsWith", "inList", "notInList", "regex"],
        "text area": ["equals", "notEquals", "contains", "startsWith", "endsWith", "inList", "notInList", "regex"],
        "time": ["equals", "notEquals", "greaterThan", "lessThan", "greaterThanOrEqual", "lessThanOrEqual", "inList", "notInList"],
        "toggle": ["equals", "notEquals"]
    }

    get typeFromQuestion() {
        // get data Type by finding the question in this.questions that equals the resource

        const dataType = this.questions.find(q => q.id === this.resource)?.attributes[FIELDS.Form_Question__c.Type.fieldApiName];

        const typeMapping = {
            'Checkbox': 'text',
            'Date': 'date',
            'Dropdown': 'text',
            'Email': 'email',
            'File Upload': 'file',
            'Form': 'text', // default to text as there's no specific form type in lightning-input
            'Geolocation': 'text', // could be custom input for lat/long
            'Multiple Choice': 'text', // assuming it's a dropdown
            'Number': 'number',
            'Page': 'text', // default to text as there's no specific page type in lightning-input
            'Phone': 'tel',
            'Radio Buttons': 'text',
            'Rating': 'number', // could be custom stars component
            'Scan Barcode': 'text', // could be custom input for barcode scanner
            'Section': 'text', // default to text as there's no specific section type in lightning-input
            'Signature': 'text', // could be custom input for signature
            'Slider': 'range',
            'Text': 'text',
            'Text Area': 'textarea',
            'Time': 'time',
            'Toggle': 'text'
        };

        return typeMapping[dataType] || 'text';
    }

    get sectionDisabled(){
        return !this.page ? true : false;
    }

    get resourceDisabled(){
        return !this.section ? true : false;
    }

    get isNarrowVariant(){
        return this.variant === 'narrow';
    }

    get isBaseVariant(){
        return this.variant === 'base';
    }

    get logicalOperatorDisplay() {
        return this.logicalOperator == null ? this.index : this.index === 0 ? null : this.logicalOperator;
    }

    get isNewCondition(){
        return this.condition.resource === undefined || this.condition.resource === null || this.condition.resource === '';
    }

    get resourceName(){
        return this.condition.resource ? this.questions.find(q => q.id === this.condition.resource).attributes[FIELDS.Form_Question__c.Question.fieldApiName] : '';
    }

    get operaterName(){
        return this.condition.operator ? this.allOperators.find(op => op.value === this.condition.operator).label : '';
    }

    get showPopover(){
        return this.isPopoverOpen;
    }

    resourceNotSelected = true;

    handleResourceChange(event) {
        try {
            const index = event.target.dataset.index;
            const newValue = event.detail.value;
            this.dispatchEvent(new CustomEvent('resourcechange', { detail: { index, value: newValue } }));

            const selectedResourceId = event.detail.value;
            const selectedQuestion = this.questions.find(q => q.id === selectedResourceId);

            if (selectedQuestion) {
                const type = selectedQuestion.attributes[FIELDS.Form_Question__c.Type.fieldApiName].toLowerCase();
                this.updateOperatorOptions(type);
                this.resetOperatorIfIncompatible(type, index);
            }
        } catch (error) {
            this.handleError(error, 'handleResourceChange');
        }
    }

    /**
     * If the current operator isn't valid for the newly selected question type,
     * clear it so the user can't save an invalid combination (e.g. `equals` on
     * a Signature, which only supports isTrue/isFalse).
     */
    resetOperatorIfIncompatible(typeLower, index) {
        const valid = this.validOperators[typeLower] || [];
        if (this.operator && !valid.includes(this.operator)) {
            this.operator = null;
            this.dispatchUpdateEvent('operatorchange', index, null);
        }
    }

    updateOperatorOptions(type) {
        try {
            this.operatorOptions = this.validOperators[type]
                ? this.allOperators.filter(op => this.validOperators[type].includes(op.value))
                : [];
        } catch (error) {
            this.handleError(error, 'updateOperatorOptions');
        }
    }

    handleOperatorChange(event) {
        try {
            const index = event.target.dataset.index;
            const newValue = event.detail.value;
            this.dispatchEvent(new CustomEvent('operatorchange', { detail: { index, value: newValue } }));
        } catch (error) {
            this.handleError(error, 'handleOperatorChange');
        }
    }

    handleValueChange(event) {
        try {
            const index = event.target.dataset.index;
            const newValue = event.detail.value;
            this.dispatchEvent(new CustomEvent('valuechange', { detail: { index, value: newValue } }));
        } catch (error) {
            this.handleError(error, 'handleValueChange');
        }
    }

    dispatchUpdateEvent(eventType, index, value) {
        this.dispatchEvent(new CustomEvent(eventType, { detail: { index, value: value } }));
    }

    handleNarrowPageChange(event) {
        try {
            this.page = event.detail.value;

            this.filterSections(this.page);

            this.section = null;
            this.resource = null;
            const index = event.target.dataset.index;
            this.dispatchUpdateEvent('pagechange', index, this.page);
        } catch (error) {
            this.handleError(error, 'handleNarrowResourceChange');
        }
    }

    filterSections(page){
        this.filteredSectionOptions = this.sectionOptions.filter(section => section.page === page);
    }

    filterQuestions(section){
        this.filteredQuestionOptions = this.questionOptions.filter(question => question.section === section && question.label);
    }

    handleNarrowSectionChange(event) {
        try {
            this.section = event.detail.value;

            this.filterQuestions(this.section);

            // Clearing the local resource also has to be propagated to the
            // parent condition - otherwise child UI and parent state diverge
            // until Done is clicked, and the saved condition keeps the stale
            // resource Id.
            this.resource = null;
            this.resourceNotSelected = true;
            this.operator = null;
            this.operatorOptions = [];
            const index = event.target.dataset.index;
            this.dispatchUpdateEvent('sectionchange', index, this.section);
            this.dispatchUpdateEvent('resourcechange', index, null);
            this.dispatchUpdateEvent('operatorchange', index, null);
        } catch (error) {
            this.handleError(error, 'handleNarrowSectionChange');
        }
    }

    handleNarrowResourceChange(event) {
        try {
            this.resource = event.detail.value;
            this.resourceNotSelected = !this.resource;
            const index = event.target.dataset.index;
            const selectedQuestion = this.questions.find(q => q.id === this.resource);
            if (selectedQuestion) {
                const type = selectedQuestion.attributes[FIELDS.Form_Question__c.Type.fieldApiName].toLowerCase();
                this.updateOperatorOptions(type);
                this.resetOperatorIfIncompatible(type, index);
            }
            this.dispatchUpdateEvent('resourcechange', index, this.resource);
        } catch (error) {
            this.handleError(error, 'handleNarrowResourceChange');
        }
    }

    handleNarrowOperatorChange(event) {
        // Dispatch the change immediately. The previous version only stored it
        // locally, which meant dismissing the popover by clicking outside
        // silently discarded the user's operator selection.
        this.operator = event.detail.value;
        const index = event.target?.dataset?.index;
        this.dispatchUpdateEvent('operatorchange', index, this.operator);
    }

    handleNarrowValueChange(event) {
        this.value = event.detail.value;
        const index = event.target?.dataset?.index;
        this.dispatchUpdateEvent('valuechange', index, this.value);
    }

    handleRemoveCondition(event) {
        try {
            const index = event.target.dataset.index;
            this.dispatchEvent(new CustomEvent('removecondition', { detail: { index } }));
        } catch (error) {
            this.handleError(error, 'handleRemoveCondition');
        }
    }

    handleOpenPopOver(){
        this.isPopoverOpen = true;
    }

    handleDone() {
        try {
            const popover = this.template.querySelector('.slds-popover__body');
            const allValid = [...popover.querySelectorAll('lightning-combobox, lightning-input')].reduce((validSoFar, inputCmp) => {
                inputCmp.reportValidity();
                return validSoFar && inputCmp.checkValidity();
            }, true);

            if (allValid) {
                this.sendUpdatedCondition();
                this.isPopoverOpen = false;
            }
        } catch (error) {
            this.handleError(error, 'handleDone');
        }
    }

    sendUpdatedCondition(){
        try {
            const conditionEvent = new CustomEvent('conditionchange', {
                detail: {
                    condition: {
                        ...this.condition,
                        resource: this.resource,
                        operator: this.operator,
                        value: this.value
                    },
                    index: this.index
                }
            });

            this.dispatchEvent(conditionEvent);
        } catch (error) {
            this.handleError(error, 'sendUpdatedCondition');
        }
    }
    
    handleError(error, methodName) {
        console.error(`Error in ${methodName}:`, error);
        this.dispatchEvent(new CustomEvent('error', { detail: { error, methodName } }));
    }

    connectedCallback(){

        this.initializeOptions();
        
        if(this.condition.page){
            this.page = this.condition.page;
            this.filterSections(this.page);
        }else{
            this.page = this.selection?.attributes[FIELDS.Form_Question__c.FormPage.fieldApiName] ?? null;
            this.filterSections(this.page);
        }

        this.section = this.condition.section;
        this.filterQuestions(this.section);

        this.resource = this.condition.resource;
        this.resourceNotSelected = !this.resource;
        this.operator = this.condition.operator;
        this.value = this.condition.value;
        const selectedQuestion = this.questions.find(q => q.id === this.resource);
        if (selectedQuestion) {
            this.updateOperatorOptions(selectedQuestion.attributes[FIELDS.Form_Question__c.Type.fieldApiName].toLowerCase());
        }
    }

    initializeOptions(){
        const pages = [];
        const sections = [];
        const questions = [];
        (this._allConfiguration || []).forEach(page => {
            pages.push({ label: page.attributes[FIELDS.Form_Page__c.Title.fieldApiName], value: page.id });
            page.sections.forEach(section => {
                sections.push({ label: section.attributes[FIELDS.Form_Section__c.Title.fieldApiName], value: section.id, page: page.id });

                section.columns.forEach(column => {
                    column.components.forEach(question => {
                        questions.push({ label: question.attributes[FIELDS.Form_Question__c.Question.fieldApiName], value: question.id, section: section.id });
                    });
                });
            });
        });
        // Single assignment per list - the previous version re-assigned inside
        // the loops on every iteration, producing N intermediate renders.
        this.pageOptions = pages;
        this.sectionOptions = sections;
        this.questionOptions = questions;
    }

}