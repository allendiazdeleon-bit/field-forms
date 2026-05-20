/**
 * @description A form builder component that allows users to create and edit forms.
 * @property {string} recordId - The ID of the form template record.
 * @author Dane Peterson, Neuraflash
 * @date 2024-01-15
 * @version 1.0.0
 * 
 * 
 */



import { LightningElement, api } from 'lwc';
import { generateUUID } from 'c/utilityService';
import getFormDetails from '@salesforce/apex/neuraFormBuilderController.getFormDetails';
import getFormMetadata from '@salesforce/apex/neuraFormBuilderController.getFormMetadata';
import processFormRecord from '@salesforce/apex/neuraFormBuilderController.processFormRecord';
import processPageRecords from '@salesforce/apex/neuraFormBuilderController.processPageRecords';
import processSectionRecords from '@salesforce/apex/neuraFormBuilderController.processSectionRecords';
import processQuestionRecords from '@salesforce/apex/neuraFormBuilderController.processQuestionRecords';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';

import { FIELDS } from 'c/neuraFormSchemaUtils';

import { store } from 'c/neuraFormStore';


export default class NeuraFormBuilder extends LightningElement {
    
    // STATE MANAGED VARIABLES
    _formSettings; // Main object that contains all of the form settings

    get formSettings(){
        return this._formSettings ?? {};
    }

    set formSettings(value){
        console.log('Setting Form Settings');
        console.dir(value);
        
        this._formSettings = value;

        store.setAllConfig(this._formSettings?.pages ?? []);
    }

    currentPage; // The current page being displayed
    selection; // The current selection in the form builder for attributes editing
    selectionId; // The id of the current selection
    selectionStructure; // The structure of the current selection (Page, Section, Component)
    pageArray = []; // The array of page names used by the header
    //totalPageCount = 0; // The total number of pages in the form used by the header
    get totalPageCount(){
        return this.formSettings?.pages?.length ?? 0;
    }
    
    //currentPageIndex = 0; // The index of the current page in the form used by the header
    historicalPageIndex = 0;

    get currentPageIndex(){
        return this.formSettings?.pages?.indexOf(this.currentPage) ?? 0;
    }

    deletedPageIds = []; // The array of deleted page ids to be passed when saved
    deletedSectionIds = []; // The array of deleted section ids to be passed when saved
    deletedQuestionIds = []; // The array of deleted question ids to be passed when saved
    

    currentDraggedItem = {}; // The current item being dragged for drag and drop purposes
    loaded = false; // Indicates if the form has been loaded
    loading = false; // Indicates if the form is currently loading
    componentItems = []; // The array of component items for the component panel
    layoutItems = []; // The array of layout items for the component panel
    activeSections = ['Layout', 'Components', 'Pages']; // The array of active accordion sections in the component panel
    componentPanel = true; // Indicates if the component panel is visible
    settingsPanel = true; // Indicates if the settings panel is visible
    breadCrumb = 'Settings'; // The current breadcrumb value

    copyComponent; // The component to be copied
    copyComponentStructure; // The structure of the component to be copied

    _builderFormFactor = 'desktop-view';
    _viaBuilder = true;

    @api
    get builderFormFactor() {
        return this._builderFormFactor;
    }

    set builderFormFactor(value) {
        try {
            console.log('Setting Builder Form Factor: ' + value);
            this._builderFormFactor = value;
            store.setBuilderFormFactor(value);
        } catch (error) {
            console.error(error);
        }
    }

    @api
    get viaBuilder() {
        return this._viaBuilder;
    }

    set viaBuilder(value) {
        this._viaBuilder = value;
        store.setViaBuilder(value);
    }

    @api recordId; 

    _settingsPanel = true;

    @api 
    get settingsPanel(){
        return this._settingsPanel && this.selection;
    }
    set settingsPanel(value){
        this._settingsPanel = value;
    }

    get currentSelectionId(){
        return this.selection ? this.selection.id : undefined;
    }

    get draggedItemInfo(){
        return this.currentDraggedItem;
    }
    get pageList(){
        // comma separated list of page names
        return this.pageArray;
    }

    get showSecondLevelCrumb(){
        return this.selection && (this.selectionStructure === 'Section' || this.selectionStructure=== 'Component');
    }

    get showThirdLevelCrumb(){
        return this.showSecondLevelCrumb || this.selectionStructure === 'Page';
    }

    get disableUndo(){
        return this.pastStates.length <= 0;
    }

    get disableRedo(){
        return this.futureStates.length <= 0;
    }

    _screenSizeClass = 'desktop-view';

    get screenSizeClass(){
        return 'canvas-page ' + this._screenSizeClass;
    }

    set screenSizeClass(value){
        this._screenSizeClass = value;
        this.builderFormFactor = value;
    }

    get indicatorType() {
        return this.formSettings?.attributes?.[FIELDS.Form_Template__c.IndicatorType.fieldApiName] ?? null;
    }

    get currentPageTitle(){
        return this.currentPage ? this.currentPage.attributes[FIELDS.Form_Page__c.Title.fieldApiName] : '';
    }

    allQuestions = [];

    updateAllQuestions(value){
        // takes in a formsettings object and returns all questions
        let questions = [];
        let config = [];
        value.pages.forEach(page => {
            let pageConfig = {
                ...page,
                sections: []
            };
            page.sections.forEach(section => {
                let sectionConfig = {
                    ...section,
                    questions: []
                };
                section.columns.forEach(column => {
                    column.components.forEach(question => {
                        questions.push(question);
                        sectionConfig.questions.push(question);
                    });
                });
                pageConfig.sections.push(sectionConfig);
            });
            config.push(pageConfig);
        });
        this.allQuestions = questions;
        store.setAllQuestions(this.allQuestions);
       // store.setAllConfig(config);
        
    }

   

    handleScreenSizeChange(value) {
        this.screenSizeClass = value;
    }

    /**
     * Retrieves the form details from the server using an Apex method.
     * @returns {void}
     */
    getFormApex(){
        getFormDetails({formTemplateId : this.recordId})
            .then(data => {
                if (data) {
                    this.processFormDetails(data);
                } else {
                    this.showToast(
                        'Form not found',
                        'No form template was returned for this record. It may have been deleted.',
                        'error'
                    );
                }
                this.loading = false;
            })
            .catch(error => {
                console.error(error);
                this.showToast('Error loading form', this.errorMessage(error), 'error');
                this.loading = false;
            });
    }

    /**
     * Retrieves form metadata using Apex method getFormMetadata().
     * Populates componentItems and layoutItems based on the retrieved data.
     */
    getFormMetadataApex(){
        getFormMetadata()
            .then(data => {
                if (!data) return;
                const structureKey = FIELDS.Form_Setting__mdt.Structure.fieldApiName;
                this.componentItems = data.filter(item => item[structureKey] === 'Component');
                this.layoutItems = data.filter(item => item[structureKey] === 'Layout');
            })
            .catch(error => {
                console.error(error);
                this.showToast('Error loading metadata', this.errorMessage(error), 'error');
            });
    }

    errorMessage(error) {
        return error?.body?.message || error?.message || 'Unknown error';
    }


    /**
     * Processes the form details and organizes them into a structured format.
     * @param {Object} data - The data containing the form details.
     */
    processFormDetails(data) {
        let form = data.formTemplate;
        console.dir(form);
        console.dir(data.pages);
        let pages = this.organizePages(data.pages);
        let sections = this.organizeSections(data.sections);
        let questions = this.organizeQuestions(data.questions);

        

        // First, set the basic properties of formSettings
        this.formSettings = {
            id: form.Id,
            name: form.Name,
            type: 'Form',
            attributes: form
        };

        // if the form has no pages, create a new page
        if(pages.length === 0){
            pages.push(this.createNewPage());
        }

        this.formSettings.pages = pages.map(page => ({
                ...page,
                sections: sections
                    .filter(section => section.attributes[FIELDS.Form_Section__c.FormPage.fieldApiName] === page.id)
                    .map(section => ({
                        ...section,
                        columns: this.buildColumns(section, questions)
                    }))
            }));
        
        console.log(JSON.stringify(this.formSettings));
        this.pageArray = this.formSettings.pages.map(page => (page.attributes[FIELDS.Form_Page__c.Title.fieldApiName]));
        this.currentPage = this.formSettings.pages[this.historicalPageIndex];

        // Snapshot the loaded attributes for each record so processPages/Sections/
        // Questions can skip unchanged records on save (audit item M2).
        this.loadedAttributesById = {};
        const snap = (rec) => {
            if (rec?.id && !this.isUUID(rec.id)) {
                this.loadedAttributesById[rec.id] = JSON.stringify(rec.attributes || {});
            }
        };
        this.formSettings.pages.forEach(p => {
            snap(p);
            p.sections.forEach(s => {
                snap(s);
                s.columns.forEach(c => c.components.forEach(snap));
            });
        });

        this.updateAllQuestions(this.formSettings);

        this.loaded = true;
        this.isDirty = false;
    }

    /**
     * Organizes the pages by mapping each page to a new object with specific properties.
     * 
     * @param {Array} pages - The array of pages to be organized.
     * @returns {Array} - The organized array of pages.
     */
    organizePages(pages) {
        return pages.map(page => ({
            id: page.Id,
            name: page.Name,
            order__c: page[FIELDS.Form_Page__c.Order.fieldApiName],
            type: 'Page',
            attributes : page,
        }));
    }

    /**
     * Organizes the sections.
     * @param {Array} sections - The sections to be organized.
     * @returns {Array} - The organized sections.
     */
    organizeSections(sections) {
        return sections.map(section => ({
            id: section.Id,
            type: 'Section',
            order__c: section[FIELDS.Form_Section__c.Order.fieldApiName],
            title: section[FIELDS.Form_Section__c.Title.fieldApiName],
            attributes : section,
        }));
    }

    /**
     * Organizes an array of questions.
     * @param {Array} questions - The array of questions to be organized.
     * @returns {Array} - The organized array of questions.
     */
    organizeQuestions(questions) {
        console.log(JSON.parse(JSON.stringify(FIELDS.Form_Question__c)));
        return questions.map(question => ({
            id: question.Id,
            type: question[FIELDS.Form_Question__c.Type.fieldApiName], 
            // UNUSED: title: question[FIELDS.Form_Question__c.Title.fieldApiName],
            Order__c: question[FIELDS.Form_Question__c.Order.fieldApiName],
            attributes: question
        }));
    }

    /**
     * Builds columns for a given section and questions.
     * 
     * @param {Object} section - The section object.
     * @param {Array} questions - The array of question objects.
     * @returns {Array} - The array of columns.
     */
    buildColumns(section, questions) {
        let columns = [];
        let numberOfColumns = parseInt(section.attributes[FIELDS.Form_Section__c.Columns.fieldApiName], 10);
        
        for (let i = 1; i <= numberOfColumns; i++) {
            let columnQuestions = questions
                .filter(q => q.attributes[FIELDS.Form_Question__c.FormSection.fieldApiName] === section.id && q.attributes[FIELDS.Form_Question__c.Column.fieldApiName] === i.toString())
                .sort((a, b) => a[FIELDS.Form_Question__c.Order.fieldApiName] - b[FIELDS.Form_Question__c.Order.fieldApiName]); // Sorting questions by Order__c
    
            let components = columnQuestions.map(q => ({
                id: `${q.id}`, // Unique ID for each component
                type: q.type,
                title: q.title,
                attributes: q.attributes
            }));
    
            columns.push({
                id: `col${section.id}-${i}`,
                components: components
            });
        }
    
        return columns;
    }

      
    // Dirty-state tracking. Flipped to true on any saveState() call (which all
    // mutating handlers trigger), reset to false after a successful save.
    // Drives the beforeunload guard and the back-button confirm.
    isDirty = false;

    _beforeUnloadHandler;

    connectedCallback(){
        this.getFormApex();
        this.getFormMetadataApex();
        this.viaBuilder = true;

        // Browser-level guard: warn before tab close / refresh / hard navigation
        // when there are unsaved changes. Standard returnValue=string mechanism
        // (most browsers display a generic message, not ours, but we set one).
        this._beforeUnloadHandler = (e) => {
            if (this.isDirty) {
                e.preventDefault();
                e.returnValue = 'You have unsaved changes in the form builder. Leave anyway?';
                return e.returnValue;
            }
            return undefined;
        };
        window.addEventListener('beforeunload', this._beforeUnloadHandler);
    }

    disconnectedCallback() {
        if (this._beforeUnloadHandler) {
            window.removeEventListener('beforeunload', this._beforeUnloadHandler);
            this._beforeUnloadHandler = undefined;
        }
    }


    // REFACTORED CODE

    // SAVING METHODS

    /**
     * Handles the save-as operation for the form builder.
     * This function creates a new form template with a given name, duplicating pages, sections, and questions.
     * @param {String} name - The name for the new form template.
     * @returns {Promise<void>} A promise that resolves when the operation is complete.
     */
    async handleSaveAs(name) {
        try {
            this.loading = true;
            this.historicalPageIndex = this.currentPageIndex;

            // copy FormSettings to a new object
            let newFormSettings = {...this.formSettings};
            // adjust the attributes.name = name 
            newFormSettings.name = name;
            newFormSettings.attributes.Name = name;


            // Clone the form attributes and assign a new name
            let newFormTemplate = {...newFormSettings.attributes};
            delete newFormTemplate.Id; // Ensure it's treated as a new record

            // Handle the creation of the new form template
            newFormTemplate = await this.handleFormOperationsAsNew(newFormTemplate);
            newFormSettings.attributes = newFormTemplate;
            newFormSettings.id = newFormTemplate.Id;
            
            // Update all related pages, sections, and questions with the new form template ID and UUIDs
            // This will be done in sequence to ensure that all references are updated correctly
            let tempOldPageIdsToNew = {};
            let tempOldSectionIdsToNew = {};
            let tempOldQuestionIdsToNew = {};

            newFormSettings.pages.forEach(page => {
                let newPageId = generateUUID();
                tempOldPageIdsToNew[page.id] = newPageId;
                page.attributes[FIELDS.Form_Page__c.FormTemplate.fieldApiName] = newFormTemplate.Id;
                page.id = newPageId;
                page.attributes.Id = newPageId;
                page.sections.forEach(section => {
                    let newSectionId = generateUUID();
                    tempOldSectionIdsToNew[section.id] = newSectionId;
                    section.attributes[FIELDS.Form_Section__c.FormTemplate.fieldApiName] = newFormTemplate.Id;
                    section.id = newSectionId;
                    section.attributes.Id = newSectionId;
                    section.columns.forEach(column => {
                        column.components.forEach(question => {
                            let newQuestionId = generateUUID();
                            tempOldQuestionIdsToNew[question.id] = newQuestionId;
                            question.attributes[FIELDS.Form_Question__c.FormTemplate.fieldApiName] = newFormTemplate.Id;
                            question.id = newQuestionId;
                            question.attributes.Id = newQuestionId;
                        });
                    });
                });
            });

            // now we need to update any conditions that reference an old UUID
            newFormSettings.pages.forEach(page => {
                if(this.isValidConditionField(page.attributes, FIELDS.Form_Page__c.Conditions.fieldApiName)){
                    let result = this.updateConditions(page.attributes[FIELDS.Form_Page__c.Conditions.fieldApiName], tempOldPageIdsToNew, tempOldSectionIdsToNew, tempOldQuestionIdsToNew, true);
                    if(result.madeChange){
                        page.attributes[FIELDS.Form_Page__c.Conditions.fieldApiName] = result.updatedConditions;
                    }   
                }
                
                page.sections.forEach(section => {
                    if(this.isValidConditionField(section.attributes, FIELDS.Form_Section__c.Conditions.fieldApiName)){
                        let result = this.updateConditions(section.attributes[FIELDS.Form_Section__c.Conditions.fieldApiName], tempOldPageIdsToNew, tempOldSectionIdsToNew, tempOldQuestionIdsToNew, true);
                        if(result.madeChange){
                            section.attributes[FIELDS.Form_Section__c.Conditions.fieldApiName] = result.updatedConditions;
                        }
                    }
                    section.columns.forEach(column => {
                        column.components.forEach(question => {
                            if(this.isValidConditionField(question.attributes, FIELDS.Form_Question__c.Conditions.fieldApiName)){
                                let result = this.updateConditions(question.attributes[FIELDS.Form_Question__c.Conditions.fieldApiName], tempOldPageIdsToNew, tempOldSectionIdsToNew, tempOldQuestionIdsToNew, true);
                                if(result.madeChange){
                                    question.attributes[FIELDS.Form_Question__c.Conditions.fieldApiName] = result.updatedConditions;
                                }
                            }
                        });
                    });
                });
            });






            const { newPages, updatedPages } = this.processPages(newFormSettings.pages);
            const { newSections, updatedSections } = this.processSections(newFormSettings.pages);
            const { newQuestions, updatedQuestions } = this.processQuestions(newFormSettings.pages);
            
            let oldPageIdsToNew = await this.handlePageOperations(newPages, updatedPages);


            // update new Sections with the new page Ids
            if(newPages.length > 0){
                newSections.forEach(section => {
                    section[FIELDS.Form_Section__c.FormPage.fieldApiName] = oldPageIdsToNew[section[FIELDS.Form_Section__c.FormPage.fieldApiName]];
                });

                newPages.forEach(page => {
                    page.Id = oldPageIdsToNew[page.Id];
                });
            }

            let oldSectionIdsToNew = await this.handleSectionOperations(newSections, updatedSections);

            // if new Sections is > 0 then update new Questions with the new section Ids
            if(newSections.length > 0){
                newQuestions.forEach(question => {
                    question[FIELDS.Form_Question__c.FormSection.fieldApiName] = oldSectionIdsToNew[question[FIELDS.Form_Question__c.FormSection.fieldApiName]];
                });

                newSections.forEach(section => {
                    section.Id = oldSectionIdsToNew[section.Id];
                });
            }

            let oldQuestionIdsToNew = await this.handleQuestionOperations(newQuestions, updatedQuestions);

            if(newQuestions.length > 0){
                // update the new Questions with the new question Ids
                newQuestions.forEach(question => {
                    question.Id = oldQuestionIdsToNew[question.Id];
                })
            }


            // CONDITIONS CHECKS 
            // Now let's find any conditions that reference a UUID and update them to the new question Ids
            let allPages = [...newPages, ...updatedPages];
            let allSections = [...newSections, ...updatedSections];
            let allQuestions = [...newQuestions, ...updatedQuestions];

            let modifiedPages = this.updateItemsConditions(allPages, FIELDS.Form_Page__c.Conditions.fieldApiName, oldPageIdsToNew, oldSectionIdsToNew, oldQuestionIdsToNew);
            let modifiedSections = this.updateItemsConditions(allSections, FIELDS.Form_Section__c.Conditions.fieldApiName, oldPageIdsToNew, oldSectionIdsToNew, oldQuestionIdsToNew);
            let modifiedQuestions = this.updateItemsConditions(allQuestions, FIELDS.Form_Question__c.Conditions.fieldApiName, oldPageIdsToNew, oldSectionIdsToNew, oldQuestionIdsToNew);

            // Update the form settings with the new page, section, and question IDs
            if (modifiedPages.length > 0) {
                await this.handlePageOperations([], modifiedPages);
            }
            if (modifiedSections.length > 0) {
                await this.handleSectionOperations([], modifiedSections);
            }
            if (modifiedQuestions.length > 0) {
                await this.handleQuestionOperations([], modifiedQuestions);
            }
            

            // update record Id to the new form template Id
            this.recordId = newFormTemplate.Id;
            this.getFormApex();
            this.loading = false;
            console.log('Save as operation completed successfully.');
        } catch (error) {
            console.error('Error in save-as operation:', error);
            console.log(JSON.stringify(error.message));
            this.loading = false;
        }
    }

    /**
     * Special handler for creating a new form template record.
     * @param {Object} newFormTemplate - The new form template to be created.
     * @returns {Promise<void>} A promise that resolves when the form template is successfully created.
     */
    async handleFormOperationsAsNew(newFormTemplate) {
        return new Promise((resolve, reject) => {
            processFormRecord({ toCreate: newFormTemplate })
                .then(response => {
                    resolve(response);
                })
                .catch(error => {
                    console.error('Error creating new form template:', error);
                    reject(error);
                });
        });
    }


    /**
     * Handles the save operation for the form builder.
     * Extracts and processes records from the nested structure,
     * performs CRUD operations for each entity type in sequence,
     * and refreshes all metadata.
     * @returns {Promise<void>} A promise that resolves when the save operation is complete.
     */
    async handleSave() {
        // Note: incremental dirty tracking (only updating changed records) is
        // tracked separately (see Wave 6, audit item M2). For now, every existing
        // record is treated as dirty - see isUpdatedRecord().
        let lastStep = 'starting save';
        try {
            this.loading = true;
            this.historicalPageIndex = this.currentPageIndex;

            const { newPages, updatedPages } = this.processPages(this.formSettings.pages);
            const { newSections, updatedSections } = this.processSections(this.formSettings.pages);
            const { newQuestions, updatedQuestions } = this.processQuestions(this.formSettings.pages);

            lastStep = 'updating form template';
            await this.handleFormOperations();

            lastStep = 'saving pages';
            let oldPageIdsToNew = await this.handlePageOperations(newPages, updatedPages);
            if (newPages.length > 0) {
                newSections.forEach(section => {
                    section[FIELDS.Form_Section__c.FormPage.fieldApiName] = oldPageIdsToNew[section[FIELDS.Form_Section__c.FormPage.fieldApiName]];
                });
                newPages.forEach(page => {
                    page.Id = oldPageIdsToNew[page.Id];
                });
            }

            lastStep = 'saving sections';
            let oldSectionIdsToNew = await this.handleSectionOperations(newSections, updatedSections);
            if (newSections.length > 0) {
                newQuestions.forEach(question => {
                    question[FIELDS.Form_Question__c.FormSection.fieldApiName] = oldSectionIdsToNew[question[FIELDS.Form_Question__c.FormSection.fieldApiName]];
                });
                newSections.forEach(section => {
                    section.Id = oldSectionIdsToNew[section.Id];
                });
            }

            lastStep = 'saving questions';
            let oldQuestionIdsToNew = await this.handleQuestionOperations(newQuestions, updatedQuestions);
            if (newQuestions.length > 0) {
                newQuestions.forEach(question => {
                    question.Id = oldQuestionIdsToNew[question.Id];
                });
            }

            // Resolve UUID references in conditional logic to the real Ids that
            // the Apex calls just returned.
            lastStep = 'updating conditional logic';
            const allPages = [...newPages, ...updatedPages];
            const allSections = [...newSections, ...updatedSections];
            const allQuestions = [...newQuestions, ...updatedQuestions];
            const modifiedPages = this.updateItemsConditions(allPages, FIELDS.Form_Page__c.Conditions.fieldApiName, oldPageIdsToNew, oldSectionIdsToNew, oldQuestionIdsToNew);
            const modifiedSections = this.updateItemsConditions(allSections, FIELDS.Form_Section__c.Conditions.fieldApiName, oldPageIdsToNew, oldSectionIdsToNew, oldQuestionIdsToNew);
            const modifiedQuestions = this.updateItemsConditions(allQuestions, FIELDS.Form_Question__c.Conditions.fieldApiName, oldPageIdsToNew, oldSectionIdsToNew, oldQuestionIdsToNew);
            if (modifiedPages.length > 0) await this.handlePageOperations([], modifiedPages);
            if (modifiedSections.length > 0) await this.handleSectionOperations([], modifiedSections);
            if (modifiedQuestions.length > 0) await this.handleQuestionOperations([], modifiedQuestions);

            this.isDirty = false;
            this.showToast('Saved', 'Form template saved successfully.', 'success');
            this.getFormApex(); // refreshes loading=false on completion
        } catch (error) {
            console.error(error);
            // Pinpoint which sub-step the save was on so admins know what may
            // have committed before the failure - Apex DML inside one method
            // rolls back, but across the multi-call save flow, earlier methods
            // are already committed when a later one throws.
            this.showToast(
                'Save failed',
                `Failed while ${lastStep}. ${this.errorMessage(error)}`,
                'error'
            );
            this.loading = false;
        }
    }

    updateItemsConditions(items, conditionsFieldApiName, pagesOldToNewMap, sectionsOldToNewMap, questionsOldToNewMap) {
        let modifiedItems = [];
        items.forEach(item => {
            if (this.isValidConditionField(item, conditionsFieldApiName)) {
                let result = this.updateConditions(item[conditionsFieldApiName], pagesOldToNewMap, sectionsOldToNewMap, questionsOldToNewMap);
                if (result.madeChange) {
                    item[conditionsFieldApiName] = result.updatedConditions;
                    modifiedItems.push(item);
                }
            }
        });
        return modifiedItems;
    }

    isValidConditionField(item, conditionsFieldApiName) {
        return item[conditionsFieldApiName] && item[conditionsFieldApiName].length > 0 && item[conditionsFieldApiName] !== '{}';
    }

    updateConditions(conditionsValue, pagesOldToNewMap, sectionsOldToNewMap, questionsOldToNewMap, overrideUUID = false) {
        let madeChange = false; // Flag to track if any changes were made
        try {
            let conditionsStatement = JSON.parse(conditionsValue);
    
            if (conditionsStatement && Array.isArray(conditionsStatement.conditions)) {
                conditionsStatement.conditions.forEach(condition => {
                    if (condition.resource && (condition.resource.startsWith('UUID') || overrideUUID) && questionsOldToNewMap[condition.resource]) {
                        condition.resource = questionsOldToNewMap[condition.resource];
                        madeChange = true; // Set the flag to true as a change was made
                    }

                    if(condition.page && (condition.page.startsWith('UUID') || overrideUUID) && pagesOldToNewMap[condition.page]){
                        condition.page = pagesOldToNewMap[condition.page];
                        madeChange = true;
                    }

                    if(condition.section && (condition.section.startsWith('UUID') || overrideUUID) && sectionsOldToNewMap[condition.section]){
                        condition.section = sectionsOldToNewMap[condition.section];
                        madeChange = true;
                    }
                });
    
                if (madeChange) {
                    return { updatedConditions: JSON.stringify(conditionsStatement), madeChange };
                }
            }
        } catch (error) {
            console.error('Failed to parse conditionsValue:', error);
        }
        return { updatedConditions: conditionsValue, madeChange }; // Return original and change flag
    }

    /**
     * Processes the given pages and returns new, updated, and deleted page information.
     * @param {Array} pages - The array of pages to be processed.
     * @returns {Object} - An object containing newPages, updatedPages, and deletedPageIds.
     */
    processPages(pages) {
        let newPages = [], updatedPages = [], deletedPageIds = [];
        pages.forEach((page, index) => {
            
            // Update the Order__c field for each page
            page.attributes[FIELDS.Form_Page__c.Order.fieldApiName] = index + 1;
            
            if (this.isNewRecord(page)) {
                newPages.push(page.attributes);
            } else if (this.isUpdatedRecord(page)) {
                updatedPages.push(page.attributes);
            }
        });
        
        return { newPages, updatedPages, deletedPageIds };
    }

    /**
     * Processes the sections of the given pages.
     * 
     * @param {Array} pages - The array of pages.
     * @returns {Object} - An object containing the new sections and updated sections.
     */
    processSections(pages) {
        let newSections = [], updatedSections = [];
        pages.forEach(page => {
            page.sections.forEach((section, sectionIndex) => {
                // Pass parent page ID for new sections
                if (this.isNewRecord(section)) {
                    section.parentPageId = page.id; // Store parent page ID
                    section.attributes[FIELDS.Form_Section__c.Order.fieldApiName] = sectionIndex + 1;
                    section.attributes[FIELDS.Form_Section__c.FormPage.fieldApiName] = page.id;
                    newSections.push(section.attributes);
                } else if (this.isUpdatedRecord(section)) {
                    section.parentPageId = page.id; // Store parent page ID
                    section.attributes[FIELDS.Form_Section__c.Order.fieldApiName] = sectionIndex + 1;
                    section.attributes[FIELDS.Form_Section__c.FormPage.fieldApiName] = page.id;
                    updatedSections.push(section.attributes);
                }
            });
        });
        return { newSections, updatedSections };
    }

    /**
     * Processes the questions from the given pages and returns new and updated questions.
     * 
     * @param {Array} pages - The array of pages containing questions.
     * @returns {Object} - An object containing newQuestions and updatedQuestions arrays.
     */
    processQuestions(pages) {
        let newQuestions = [], updatedQuestions = [];
        pages.forEach(page => {
            page.sections.forEach(section => {
                section.columns.forEach((column, columnIndex) => {
                    column.components.forEach((question, questionIndex) => {
                        if (this.isNewRecord(question)) {
                            question.attributes[FIELDS.Form_Question__c.Column.fieldApiName] = (columnIndex + 1).toString();;
                            question.attributes[FIELDS.Form_Question__c.Order.fieldApiName] = questionIndex+1;
                            question.attributes[FIELDS.Form_Question__c.FormSection.fieldApiName] = section.id;
                            newQuestions.push(question.attributes);
                        } else if (this.isUpdatedRecord(question)) {
                            question.parentSectionId = section.id; // Store parent section ID
                            question.attributes[FIELDS.Form_Question__c.Column.fieldApiName] = (columnIndex + 1).toString();;
                            question.attributes[FIELDS.Form_Question__c.Order.fieldApiName] = questionIndex+1;
                            question.attributes[FIELDS.Form_Question__c.FormSection.fieldApiName] = section.id;
                            updatedQuestions.push(question.attributes);
                        }
                    });
                });
            });
        });
        return { newQuestions, updatedQuestions };
    }

   
    /**
     * Handles form operations by updating the form record.
     * @returns {Promise<void>} A promise that resolves when the form record is successfully updated.
     */
    async handleFormOperations() {
        return new Promise((resolve, reject) => {
            // Update Form
            processFormRecord({toUpdate: this.formSettings.attributes})
                .then(response => {
                    resolve();
                })
                .catch(error => {
                    console.error(error);
                    reject(error);
                });
        });
    }

    /**
     * Handles page operations by creating new pages, updating existing pages, and deleting pages.
     * @param {Array<Object>} newPages - The array of new pages to be created.
     * @param {Array<Object>} updatedPages - The array of updated pages.
     * @returns {Promise<Array<Object>>} A promise that resolves with an array of new pages with updated IDs.
     * @throws {Error} If an error occurs during the process.
     */
    async handlePageOperations(newPages, updatedPages) {
        return new Promise((resolve, reject) => {
            // Create new pages

            // remove the id from the newPages
            let tempNewPages = newPages.map(page => {
                let tempPage = {...page};
                delete tempPage.Id;
                return tempPage;
            });
            processPageRecords({ toCreate: tempNewPages, toUpdate: updatedPages, toDelete: this.deletedPageIds})
                .then(response => {
                    //reset Deleted Page Ids
                    this.deletedPageIds = [];
                    resolve(this.mapNewIdsToOld(newPages, response));
                    // Handle updates and deletions similarly
                    //resolve();
                })
                .catch(error => {
                    console.error(error);
                    reject(error);
                });
        });
    }

    /**
     * Maps existing item IDs to new item IDs based on the response.
     * @param {Array} existingItems - The array of existing items.
     * @param {Array} response - The array of response items.
     * @returns {Object} - The object mapping existing item IDs to new item IDs.
     */
    mapNewIdsToOld(existingItems, response) {
        try {
            let existingPageIdsToResponseIds = {};
            existingItems.forEach((item, index) => {
                console.log('Old Item:' + JSON.stringify(item));
                console.log('New Item:' + JSON.stringify(response[index]));
                existingPageIdsToResponseIds[item.Id] = response[index].Id;
            });
            return existingPageIdsToResponseIds;
        } catch (error) {
            console.error(error.message);
            return {};
        }
    }

    /**
     * Handles section operations.
     * 
     * @param {Array} newSections - The new sections to be created.
     * @param {Array} updatedSections - The updated sections.
     * @returns {Promise} A promise that resolves with the mapped new section IDs to old section IDs.
     */
    async handleSectionOperations(newSections, updatedSections) {
        return new Promise((resolve, reject) => {
            // Create new sections

                let tempNewSections = newSections.map(section => {
                    let tempSection = {...section};
                    tempSection.Id = null;
                    return tempSection;
                });
                // CHECK INPUT VARIABLES
                console.log('tempNewSections: ' + JSON.stringify(tempNewSections));
                console.log('updatedSections: ' + JSON.stringify(updatedSections));
                console.log('ToDelete: ' + JSON.stringify(this.deletedSectionIds));
                processSectionRecords({ toCreate: tempNewSections, toUpdate: updatedSections, toDelete : this.deletedSectionIds })
                    .then(response => {
                        //reset Deleted Section Ids
                        this.deletedSectionIds = [];
                        console.log('returned from Section: ' + JSON.stringify(response));
                        resolve(this.mapNewIdsToOld(newSections, response));
                        // Handle updates and deletions similarly
                        //resolve();
                    })
                    .catch(error => {
                        console.log('In Sections');
                        console.error(error);
                        reject(error);
                    });
        });
    }

    /**
     * Handles question operations by creating, updating, and deleting questions.
     * 
     * @param {Array<Object>} newQuestions - The new questions to be created.
     * @param {Array<Object>} updatedQuestions - The updated questions to be updated.
     * @returns {Promise} A promise that resolves when the question operations are completed successfully, or rejects with an error if there is an error.
     */
    handleQuestionOperations(newQuestions, updatedQuestions) {
        return new Promise((resolve, reject) => {
            // Create new questions
            let tempNewQuestions = newQuestions.map(question => {
                let tempQuestion = {...question};
                delete tempQuestion.Id;
                return tempQuestion;
            });

                            // CHECK INPUT VARIABLES
            console.log('tempNewQuestions: ' + JSON.stringify(tempNewQuestions));
            console.log('updatedQuestions: ' + JSON.stringify(updatedQuestions));
            console.log('ToDelete: ' + JSON.stringify(this.deletedQuestionIds));
            processQuestionRecords({ toCreate: tempNewQuestions, toUpdate: updatedQuestions, toDelete : this.deletedQuestionIds })
                .then(response => {
                    console.log('returned from Question: ' + JSON.stringify(response));
                    // reset Deleted Question Ids
                    this.deletedQuestionIds = [];
                    console.log('returned from Section: ' + JSON.stringify(response));
                    resolve(this.mapNewIdsToOld(newQuestions, response));
                })
                .catch(error => {
                    console.error(error);
                    reject(error);
                });
        });
    }

    /**
     * Updates the local IDs of new items with the corresponding SObject IDs.
     * 
     * @param {Array} newItems - The array of new items.
     * @param {Array} responseIds - The array of response IDs.
     */
    updateLocalIds(newItems, responseIds) {
        newItems.forEach((item, index) => {
            let newId = responseIds[index];
            this.updateChildItemsParentId(item, newId);
        });
    }
    

    /**
     * Checks if the given record is a new record.
     * @param {Object} record - The record object to check.
     * @returns {boolean} - Returns true if the record has an id that starts with 'UUID', otherwise false.
     */
    isNewRecord(record) {
        // DEBUG
        console.log('In is New Record: ');
        console.dir(record);
        console.log('Is New Record: ' + record.id.startsWith('UUID'));
       // return true if the record has an id that starts with 'UUID'
        return record.id.startsWith('UUID');
    }
    
    /**
     * Determines whether an existing (already-saved) record needs to be sent
     * back to Apex on save. Compares the current attributes JSON against the
     * snapshot captured in processFormDetails. New records (UUID ids) are
     * always considered "dirty" via isNewRecord and never reach this method.
     */
    isUpdatedRecord(record) {
        if (!record || !record.id || !record.attributes) return false;
        const baseline = this.loadedAttributesById?.[record.id];
        if (!baseline) {
            // No snapshot (shouldn't happen for non-UUID Ids) - be conservative
            // and treat it as dirty so we don't drop a real edit.
            return true;
        }
        return JSON.stringify(record.attributes) !== baseline;
    }
    

    /**
     * Checks if a record is marked as deleted.
     * @param {Object} record - The record to check.
     * @returns {boolean} - True if the record is marked as deleted, false otherwise.
     */
    isDeletedRecord(record) {
        // NOT NEEDED as we will maintain this list separately
        
    }


    // HANDLERS
    /**
     * Handles the selection event.
     * 
     * @param {Event} event - The selection event.
     * @returns {void}
     */
    handleSelection(event) {
        const selectionId = event.detail.id;
        const selectionType = event.detail.type;
        console.log('Selection Type: ' + selectionType);
        console.log('Selection Id: ' + selectionId);

        if(selectionType === 'Page'){
            this.currentPage = this.findPageById(selectionId);
            //this.currentPageIndex = this.findPageIndexById(selectionId);
        }
        this.selection = 
        selectionType === 'Form' ? this.formSettings :
            selectionType === 'Page' ? this.currentPage : 
                selectionType == 'Section' ? this.findSectionById(selectionId) : 
                    selectionType == 'Component' ? this.findComponentById(selectionId) : undefined;
        this.settingsPanel = true;
        this.selectionId = selectionId;
        this.selectionStructure = selectionType;
        console.log('Selection: ' + JSON.stringify(this.selection));
        console.log('Updated this.SettingsPanel');
        
    }

    /**
     * Handles the selection of a breadcrumb.
     * 
     * @param {Event} event - The event object containing the selected breadcrumb data.
     */
    handleBreadCrumbSelection(event) {
        // get the data id from the event
        let newEvent = {};
        newEvent.detail = { id : event.currentTarget.dataset.id, type : event.currentTarget.dataset.type };
        
        this.handleSelection(newEvent);
    }
    
    /**
     * Closes the settings panel.
     * @param {Event} event - The event object.
     */
    handleCloseSettings(event) {
        this.settingsPanel = false;
    }

    /**
     * Handles the update to the form setting.
     * The update will contain the updates of a component or section.
     * It finds the section or component in the formSettings and updates it accordingly.
     * 
     * @param {CustomEvent} event - The event containing the update details.
     */
    handleUpdateToFormSetting(event) {
        // the update will contain the updates of a component or section. We need to find the section or component in the formSettings and update it.
        const updatedSelection = event.detail.newSelection;
        const updatedField = event.detail.editedField;
        console.log('Updated Selection:');
        console.dir(updatedSelection);
        console.log(JSON.stringify(updatedSelection));
        if(updatedSelection.type === 'Form'){
            this.formSettings = updatedSelection;
            this.selection = updatedSelection;
        } else if (updatedSelection.type) {
            if(updatedSelection.type === 'Section' && updatedField.field === FIELDS.Form_Section__c.Columns.fieldApiName){        
                // get the number of columns in the section
                const currentNumberOfColumns = updatedSelection.columns.length;
                // get the number of columns in the updatedSelection
                const updatedNumberOfColumns = updatedField.newValue;

                if(currentNumberOfColumns > updatedNumberOfColumns){
                    // remove columns
                    // get the number of columns to remove
                    const numberOfColumnsToRemove = currentNumberOfColumns - updatedNumberOfColumns;

                    // get the new last column
                    const lastColumn = updatedSelection.columns[updatedNumberOfColumns - 1];

                    // add the components from all later columns to the last column
                    for(let i = updatedNumberOfColumns; i < currentNumberOfColumns; i++){
                        lastColumn.components = lastColumn.components.concat(updatedSelection.columns[i].components);
                    }

                    // remove the columns
                    updatedSelection.columns.splice(updatedNumberOfColumns, numberOfColumnsToRemove);
                } else if(currentNumberOfColumns < updatedNumberOfColumns){
                    // add columns
                    // get the number of columns to add
                    const numberOfColumnsToAdd = updatedNumberOfColumns - currentNumberOfColumns;

                    // add the columns
                    for(let i = 0; i < numberOfColumnsToAdd; i++){
                        updatedSelection.columns.push(this.createNewColumn());
                    }
                }
            }

            this.updateToItem(updatedSelection);
        }

    }

    /**
     * Handles the creation of a new page in the form builder.
     * Saves the current state, creates a new page, and updates the form settings.
     * Also updates the page array and total page count.
     */
    handleNewPage(){
        this.saveState();
        const newPage = this.createNewPage();
        this.formSettings = {
            ...this.formSettings,
            pages: [...this.formSettings.pages, newPage]
        };
        this.pageArray.push(newPage.attributes[FIELDS.Form_Page__c.Title.fieldApiName]);
        
        // MOVED TO GETTER
        //this.totalPageCount = this.formSettings.pages.length;
    }

    handleReOrderPage(event){
        try {
            this.saveState();
            const {id, direction} = event.detail;
            const index = this.findPageIndexById(id);
            console.log('In handleReOrderPage');
            if(direction === 'up'){
                if(index > 0){
                    this.formSettings = {
                        ...this.formSettings,
                        pages: this.swapPageElements(this.formSettings.pages, index, index - 1)
                    }
                }
            } else if(direction === 'down'){
                if(index < this.formSettings.pages.length - 1){
                    this.formSettings = {
                        ...this.formSettings, 
                        pages: this.swapPageElements(this.formSettings.pages, index, index + 1)
                    };
                }
            }

            console.log('After Swap');
            this.pageArray = this.formSettings.pages.map(page => page.attributes[FIELDS.Form_Page__c.Title.fieldApiName]);

            console.log('updated pageArray');

            // reset the currentPage to have the updated order if it was changed.
            this.currentPage = this.findPageById(this.currentPage.id);
            console.log('updated current page Settings');
        } catch (error) {
            console.error('Error in handleReOrderPage: ' + error.message);
        }
    }

    handleDeletePage(event){
        // Route page-item delete through the central handleDelete so the
        // confirmation prompt and saveState are applied consistently.
        this.handleDelete({ detail: { id: event.detail.id, type: 'Page' } });
    }

    swapPageElements(array, indexA, indexB){
        let tempA = array[indexA];
        let tempB = array[indexB];
        // swap the elements order__c attribute
        let tempOrderA = tempA.attributes[FIELDS.Form_Page__c.Order.fieldApiName];
        let tempOrderB = tempB.attributes[FIELDS.Form_Page__c.Order.fieldApiName];

        tempA.order__c = tempOrderB;
        tempB.order__c = tempOrderA;
        tempA.attributes[FIELDS.Form_Page__c.Order.fieldApiName] = tempOrderB;
        tempB.attributes[FIELDS.Form_Page__c.Order.fieldApiName] = tempOrderA;
        array[indexA] = tempB;
        array[indexB] = tempA;
        return array;
    }


    /**
     * Handles the drag start event for the neuraFormBuilder component.
     * 
     * @param {Event} event - The drag start event.
     */
    handleNFDragStart(event){
        this.currentDraggedItem = event.detail;
        console.log('Form Builder - handleNFDragStart: ');
        console.dir(JSON.parse(JSON.stringify(this.currentDraggedItem)));
        console.log(event.detail.structure);
        console.dir(this.draggedItemInfo.structure);
    }

    /**
     * Handles the drag end event for the form builder.
     * @param {Event} event - The drag end event.
     */
    handleNFDragEnd(event){
        this.currentDraggedItem = null;
        console.log('Form Builder - handleNFDragEnd: ');
        console.dir(this.draggedItemInfo);
    }  

    /**
     * Handles the click event of the footer buttons.
     * @param {Event} event - The click event.
     * @returns {void}
     */
    handleFooterButtonClick(event) {
        const actionType = event.detail.actionType;
        switch (actionType) {
            case 'previous':
                this.changePage(-1);
                break;
            case 'next':
                this.changePage(1);
                break;
            case 'finish':
                this.handleFinish();
                break;
            default:
                console.warn('Unhandled action type:', actionType);
        }
    }

    /**
     * Handles the deletion of an element. Always prompts for confirmation —
     * deletes cascade (page wipes sections+questions, section wipes questions)
     * and the only mitigation is undo, which doesn't survive a page refresh.
     */
    async handleDelete(event) {
        const elementId = event.detail.id;
        const elementType = event.detail.type;

        const confirmMessage = this.buildDeleteConfirmMessage(elementType, elementId);
        const proceed = await LightningConfirm.open({
            message: confirmMessage,
            label: `Delete ${elementType}`,
            variant: 'header',
            theme: 'warning'
        });
        if (!proceed) return;

        this.saveState();
        try {
            switch (elementType) {
                case 'Page':
                    this.deletePage(elementId);
                    break;
                case 'Section':
                    this.deleteSection(elementId);
                    break;
                case 'Component':
                    this.deleteComponent(elementId);
                    break;
                default:
                    console.error('Unknown element type');
            }
            this.updateFormSettings();
            this.clearSelectionIfNecessary(elementId);
        } catch (error) {
            console.error('Error in handleDelete:', error.message);
        }
    }

    buildDeleteConfirmMessage(type, id) {
        if (type === 'Page') {
            const page = this.findPageById(id);
            const sectionCount = page?.sections?.length ?? 0;
            const questionCount = page?.sections?.reduce(
                (sum, s) => sum + s.columns.reduce((c, col) => c + col.components.length, 0),
                0
            ) ?? 0;
            return `Delete this page along with its ${sectionCount} section(s) and ${questionCount} question(s)? This cannot be undone after Save.`;
        }
        if (type === 'Section') {
            const section = this.findSectionById(id);
            const questionCount = section?.columns?.reduce(
                (sum, col) => sum + col.components.length, 0
            ) ?? 0;
            return `Delete this section and its ${questionCount} question(s)? This cannot be undone after Save.`;
        }
        return 'Delete this component? This cannot be undone after Save.';
    }

    /**
     * Handles the drop event when a component is dropped onto the form builder.
     * 
     * @param {Event} event - The drop event.
     * @returns {void}
     */
    handleComponentDrop(event) {
        console.log('Component Drop');
        console.log('Event Detail: ' + JSON.stringify(event.detail));
        let { component, targetColumnId, targetSectionId, dragSlotIndex } = event.detail;
    
        try {
            // Create a new component with the specified type
            this.saveState();

            let newComponent;
            const isExisting = component.id;
            // If the component has an id, it is an existing component
            if (isExisting) {
                // Find the component in the form settings
                newComponent = {... this.findComponentById(component.id)};
            } else {
                // If the component does not have an id, it is a new component
                newComponent = this.createNewComponent(component.type);
            }
            
            // Find the target page and section
            let pageWithSection = this.formSettings.pages.find(page => page.sections.some(section => section.id === targetSectionId));
            if (!pageWithSection) {
                console.error('Target section not found');
                return;
            }
    
            let sectionToUpdate = pageWithSection.sections.find(section => section.id === targetSectionId);
            let columnToUpdate = sectionToUpdate.columns.find(column => column.id === targetColumnId);
    
            if (!columnToUpdate) {
                console.error('Target column not found');
                return;
            }

            // Initialize components array if it doesn't exist
            if (!Array.isArray(columnToUpdate.components)) {
                columnToUpdate.components = [];
                dragSlotIndex = 0;
            }
            if(dragSlotIndex == -1){
                dragSlotIndex = 0;
            }
            
            // Determine if the existing component is already in this column and is before the dragSlotIndex
            if(component.id){
                let existingComponentIndex = columnToUpdate.components.findIndex(c => c.id === component.id);
                if (existingComponentIndex !== -1 && existingComponentIndex < dragSlotIndex) {
                    // If the existing component is before the dragSlotIndex, we need to decrement the dragSlotIndex
                    dragSlotIndex--;
                }
                // If the component is already in the column, remove it, otherwise remove it from the form settings
                if (existingComponentIndex !== -1) {
                    columnToUpdate.components.splice(existingComponentIndex, 1);
                } else {
                    this.deleteComponent(component.id, false);
                }
            }

            // Insert the new component at the specified index in the column
            columnToUpdate.components.splice(dragSlotIndex, 0, newComponent);
    
            // Update the currentPage if it is the same page
            this.currentPage = this.formSettings.pages.find(page => page.id === this.currentPage.id);
            
            // if the newComponent is a new component then set the selection to the new component
            // TODO: Review if desired for this to pop attributes when a new component is created.
            if(!isExisting){
                this.selection = this.findComponentById(newComponent.id);
                this.selectionId = newComponent.id;
                this.selectionStructure = 'Component';
                this.settingsPanel = true;
            } 

            console.log('Component added at index:', dragSlotIndex, newComponent);
        } catch (error) {
            console.error('Error in Component Drop', error.message);
        }
    }

    /**
     * Handles the drop event for sections in the form builder.
     * @param {Event} event - The drop event.
     * @returns {void}
     */
    handleSectionDrop(event) {
        console.log('handleSectionDrop');
        //console.log('Drop Item ID:', event.detail.dropItemId);
        //console.log('Drag Slot Index:', event.detail.dragSlotIndex);
    
        let dropItemId = event.detail?.droppedItemId;
        let dragSlotIndex = event.detail.dragSlotIndex;
    
        try {
            this.saveState();
            const isExistingItem = typeof dropItemId !== "undefined" && this.findSectionById(dropItemId);
    
            if (isExistingItem) {
                // Handling existing item
                const draggedSection = this.formSettings.pages.find(page => page.sections.find(section => section.id === dropItemId));
                const draggedSectionIndex = draggedSection.sections.findIndex(section => section.id === dropItemId);
                // if the draggedSectionIndex is after the dragSlotIndex then we need to decrement the dragSlotIndex
                if (draggedSectionIndex < dragSlotIndex) {
                    dragSlotIndex--;
                }

                if (draggedSectionIndex !== -1) {
                    const [sectionToMove] = draggedSection.sections.splice(draggedSectionIndex, 1);
                    draggedSection.sections.splice(dragSlotIndex, 0, sectionToMove);
                }
            } else {
                // Handling new item (section)
                const newSection = this.createNewSection();
                const pageWithSection = this.formSettings.pages.find(page => page.id === this.currentPage.id);
                pageWithSection.sections.splice(dragSlotIndex, 0, newSection);
            }

            // Update the currentPage if it is the same page
            this.currentPage = this.formSettings.pages.find(page => page.id === this.currentPage.id);
        } catch (error) {
            console.error(JSON.stringify(error));
            console.error('Error in handleSectionDrop:', error.message);
        }
    }

    /**
     * Handles going back to the record detail page. Confirms if there are
     * unsaved changes, since the reload discards them.
     */
    async handleBack(){
        if (this.isDirty) {
            const proceed = await LightningConfirm.open({
                message: 'You have unsaved changes. Leaving will discard them. Continue?',
                label: 'Discard unsaved changes',
                variant: 'header',
                theme: 'warning'
            });
            if (!proceed) return;
        }
        window.location.reload();
    }

    /**
     * Handles the click event on the header.
     *
     * @param {Event} event - The click event.
     * @returns {void}
     */
    handleHeaderClick(event) {
        console.log('handleHeaderClick');
        console.log('Event Detail: ' + JSON.stringify(event.detail));
        let actionType = event.detail.actionType;
        let value = event.detail.value;
        // check if event detail is toggle, settings, undo,redo, save, saveas, help, dropdown, back
        switch (actionType) {
            case 'toggle':
                this.componentPanel = !this.componentPanel;
                break;
            case 'settings':
                //this.handleSettings();
                break;
            case 'undo':
                this.handleUndo();
                break;
            case 'redo':
                this.handleRedo();
                break;
            case 'save':
                this.handleSave();
                break;
            case 'saveas':
                this.handleSaveAs(value);
                break;
            case 'help':
                //this.handleHelp();
                break;
            case 'dropdown':
                //this.handleDropdown();
                break;
            case 'screensize':
                this.handleScreenSizeChange(value);
                break;
            case 'back':
                this.handleBack();
                break;
            case 'copy':
                this.handleCopy();
                break;
            case 'paste':
                this.handlePaste();
                break;
            default:
                console.warn('Unhandled action type:', actionType);
        }

    }

    // OBJECT CREATION
    /**
     * Creates a new column object.
     * @returns {Object} The newly created column object.
     */
    createNewColumn(){
        return {
            "id": generateUUID(),
            "components": []
        };
    }

    /**
     * Creates a new section object with default values.
     * @returns {Object} The newly created section object.
     */
    createNewSection(){
        const id = generateUUID();
        return {
            id: id,
            type : "Section",
            attributes : {
                Id : id,
                [FIELDS.Form_Section__c.FormTemplate.fieldApiName] : this.formSettings.id,
                [FIELDS.Form_Section__c.Columns.fieldApiName]: "1",
                [FIELDS.Form_Section__c.BackgroundColor.fieldApiName] : "",
                [FIELDS.Form_Section__c.ShowTitle.fieldApiName] : false,
                [FIELDS.Form_Section__c.TitleAlignment.fieldApiName] : null,
                [FIELDS.Form_Section__c.Title.fieldApiName] : "Section Title",
                [FIELDS.Form_Section__c.Order.fieldApiName] : 1,
                Name : "Section Title"
            },
            columns: [this.createNewColumn()]
        };
    }

    /**
     * Creates a new component with the specified type.
     * @param {string} componentType - The type of the component.
     * @returns {Object} - The newly created component object.
     */
    createNewComponent(componentType){
        console.log('New Component Type: ' + componentType)
        const isDisplayOnly = componentType === 'Display Text'; 
        const id = generateUUID();
        return {
            id: id,
            type: componentType,
            title: "Type title",
            attributes : {
                Id : id,
                [FIELDS.Form_Question__c.FormTemplate.fieldApiName] : this.formSettings.id,
                [FIELDS.Form_Question__c.Question.fieldApiName] : isDisplayOnly ? '' : componentType,
                [FIELDS.Form_Question__c.DisplayRichText.fieldApiName] : isDisplayOnly ? 'Display Text' : '',
                [FIELDS.Form_Question__c.Type.fieldApiName] : componentType,
                [FIELDS.Form_Question__c.FontColor.fieldApiName] : "",
                [FIELDS.Form_Question__c.FontSize.fieldApiName] : "",
                [FIELDS.Form_Question__c.Length.fieldApiName] : 255,
                [FIELDS.Form_Question__c.Order.fieldApiName] : 1,
                [FIELDS.Form_Question__c.Required.fieldApiName] : false,
                [FIELDS.Form_Question__c.TextAlignment.fieldApiName] : "",
                [FIELDS.Form_Question__c.ValueSet.fieldApiName] : "",
                [FIELDS.Form_Question__c.DecimalPlaces.fieldApiName] : componentType === 'Number' ? 0 : null
            }
        }
    };

    /**
     * Creates a new page for the form builder.
     * @returns {Object} The newly created page object.
     */
    createNewPage(){

        let newNumber = this.totalPageCount + 1;
        let pageName = 'Page ' + newNumber;
        const id = generateUUID();
        return {
            id: id,
            name: pageName,
            order__c: newNumber,
            type: "Page",
            attributes : {
                Id : id,
                [FIELDS.Form_Page__c.Title.fieldApiName] : pageName,
                Name : pageName,
                [FIELDS.Form_Page__c.FormTemplate.fieldApiName] : this.formSettings.id,
                [FIELDS.Form_Page__c.Order.fieldApiName] : newNumber
            },
            sections: [
                this.createNewSection()
            ]
        };
    }

    // UTILS

    /**
     * Updates the item and performs necessary updates to the current page, form settings, and selection.
     * @param {Object} updatedItem - The updated item.
     * @returns {void}
     */
    updateToItem(updatedItem) {
        // Update the currentPage with the updated page
        if (this.currentPage) {
            this.currentPage = this.updateCurrentPage(this.currentPage, updatedItem);
        }
    
        // Update formSettings and selection if necessary
        this.updateFormSettings();
        this.selection = updatedItem;
        //TODO: Determine if needed this.clearSelectionIfNecessary(updatedComponent.id);
        
    }

    /**
     * Updates the current page with the provided updated item.
     * If the updated item is the page itself, it returns the updated item.
     * If the updated item is a section, it replaces the corresponding section in the page.
     * If the updated item is a component within a section, it replaces the corresponding component in the page.
     * @param {Object} page - The current page object.
     * @param {Object} updatedItem - The updated item object.
     * @returns {Object} - The updated page object.
     */
    updateCurrentPage(page, updatedItem) {
        // Check if the updated item is the page itself
       if (updatedItem.id === page.id) {
           return updatedItem;
       }

       return {
           ...page,
           sections: page.sections.map(section => {
               if (section.id === updatedItem.id) {
                   // If the updated item is a section
                   return updatedItem;
               } else {
                   // If the updated item is a component within a section
                   return {
                       ...section,
                       columns: section.columns.map(column => ({
                           ...column,
                           components: column.components.map(component => 
                               component.id === updatedItem.id ? updatedItem : component
                           )
                       }))
                   };
               }
           })
       };
    }

    /**
     * Finds the index of a page in the formSettings array based on its id.
     * @param {string} pageId - The id of the page to search for.
     * @returns {number} - The index of the page in the formSettings array, or -1 if not found.
     */
    findPageIndexById(pageId) {
        return this.formSettings.pages.findIndex(page => page.id === pageId);
    }

    /**
     * Updates the form settings by replacing the current page with the updated page.
     */
    updateFormSettings() {
        this.formSettings = {
            ...this.formSettings,
            pages: this.formSettings.pages.map(page =>
                page.id === this.currentPage.id ? this.currentPage : page
            )
        };

        this.updateAllQuestions(this.formSettings);
        // Attribute edits flow through updateToItem -> updateFormSettings without
        // ever calling saveState, so mark dirty here to make sure the
        // beforeunload guard and back-button confirm see the change.
        this.isDirty = true;
    }

    /**
     * Finds a page in the form settings by its ID.
     * @param {string} pageId - The ID of the page to find.
     * @returns {object|undefined} - The page object if found, otherwise undefined.
     */
    findPageById(pageId) {
        return this.formSettings.pages.find(page => page.id === pageId);
    }
    
    /**
     * Finds a section by its ID in the form settings.
     * @param {string} sectionId - The ID of the section to find.
     * @returns {object|undefined} - The section object if found, otherwise undefined.
     */
    findSectionById(sectionId) {
        return this.formSettings.pages.flatMap(page => page.sections)
                                      .find(section => section.id === sectionId);
    }

    /**
     * Finds a component by its ID.
     * @param {string} componentId - The ID of the component to find.
     * @returns {object|undefined} - The found component, or undefined if not found.
     */
    findComponentById(componentId) {
        return this.formSettings.pages.flatMap(page => page.sections)
                                      .flatMap(section => section.columns)
                                      .flatMap(column => column.components)
                                      .find(component => component.id === componentId);
    }

    /**
     * Finds a components parent column from the currentPage
     * @param {string} componentId - The ID of the component to find.
     * @returns {object | undefined} - The parent column.
     */
   getColumnByComponetId(componentId) {
            for (const section of this.currentPage.sections) {
                for (const column of section.columns) {
                    const component = column.components.find(c => c.id === componentId);
                    if (component) {
                        return column;
                    }
                }
            }
        return undefined;
    }

    /**
     * Finds a section by its ID in the current page.
     * @param {string} sectionId - The ID of the section to find.
     * @returns {object|undefined} - The section object if found, otherwise undefined.
     **/ 

    getSectionBySectionId(sectionId) {
        return this.currentPage.sections.find(section => section.id === sectionId);
    }

    /**
     * Changes the current page index and updates the current page based on the given delta.
     * @param {number} delta - The change in page index.
     */
    changePage(delta) {
        const newIndex = this.currentPageIndex + delta;
        if (newIndex >= 0 && newIndex < this.totalPageCount) {
            //this.currentPageIndex = newIndex;
            this.currentPage = this.formSettings.pages[newIndex];
            this.selection = this.currentPage;
            this.selectionId = this.currentPage.id;
            this.selectionStructure = 'Page';
        }
    }

    /**
     * Clears the selection if it is on the deleted page.
     * @param {string} elementId - The ID of the element to check against the selection.
     * @returns {void}
     */
    clearSelectionIfNecessary(elementId) {
        // Clear the selection if it is on the deleted page
        if (this.selection && this.selection.id === elementId) {
            this.selection = undefined;
        }
    }

    /**
     * Finds a collection of Non-UUID questionIds and sectionIds from a section.
     * @param {*} sections 
     * @returns {Object} - An object containing an array of questionIds and an array of sectionIds.
     * {
     *   questionIds: [],
     *   sectionIds: []
     * }
     */
    collectNonUUIDIds(sections) {
        let questionIds = [];
        let sectionIds = [];
    
        sections.forEach(section => {
            section.columns.forEach(column => {
                column.components.forEach(component => {
                    if (!this.isUUID(component.id)) {
                        questionIds.push(component.id);
                    }
                });
            });
            if (!this.isUUID(section.id)) {
                sectionIds.push(section.id);
            }
        });
    
        return { questionIds, sectionIds };
    }

    /**
     * Checks for validation errors within a section based on deleting a question.
     * @param {*} sections 
     * @returns {boolean} - True if there are validation errors, false otherwise.
     */
    checkForValidationErrors(sections) {
        return sections.some(section => 
            section.columns.some(column => 
                column.components.some(component => 
                    this.isValidationError('delete', 'question', component.id)
                )
            )
        );
    }
    
    /**
     * Deletes a page from the formSettings and performs additional handling if the deleted page is the current page.
     * @param {string} pageId - The ID of the page to be deleted.
     * @returns {void}
     */
    deletePage(pageId) {
        const pages = this.formSettings.pages;

        if (pages.length === 1) {
            this.showToast(
                'Cannot delete',
                'You must create a new page before deleting the only remaining page.',
                'warning'
            );
            return;
        }

        if (this.isValidationError('delete', 'page', pageId)) return;

        const pageIndex = pages.findIndex(page => page.id === pageId);
        const page = pages[pageIndex];

        if (!page) return;

        // Per-question validation (existing behavior; redundant with the page-
        // level cascade check above but kept for defence-in-depth).
        if (this.checkForValidationErrors(page.sections)) return;
    
        // Collect non-UUID IDs
        const { questionIds, sectionIds } = this.collectNonUUIDIds(page.sections);
    
        if (questionIds.length > 0) {
            this.deletedQuestionIds = this.deletedQuestionIds.concat(questionIds);
        }
    
        if (sectionIds.length > 0) {
            this.deletedSectionIds = this.deletedSectionIds.concat(sectionIds);
        }
    
        if (!this.isUUID(pageId)) {
            this.deletedPageIds.push(pageId);
        }
    
        // Remove the page from formSettings
        this.formSettings = {
            ...this.formSettings,
            pages: pages.filter(page => page.id !== pageId)
        };
        this.pageArray = this.formSettings.pages.map(page => (page.attributes[FIELDS.Form_Page__c.Title.fieldApiName]));
        console.log('Updated formSettings after page deletion:', this.formSettings);
    
        // Set this.currentPage to the previous page or the next page if the deleted page was the first
        if (this.currentPage && this.currentPage.id === pageId) {
            if (pageIndex > 0) {
                this.currentPage = pages[pageIndex - 1]; // Previous page
            } else {
                this.currentPage = pages[pageIndex + 1]; // Next page if the deleted page was the first
            }
            console.log('Current page updated after deletion:', this.currentPage);
        }
    }
    
    /**
     * Deletes a section from the current page.
     * If the section ID is a valid UUID, it is added to the deletedSectionIds array.
     * If the section ID exists in the current page, it is removed from the currentPage object.
     * @param {string} sectionId - The ID of the section to be deleted.
     * @returns {void}
     */
    deleteSection(sectionId) {
        const section = this.currentPage.sections.find(section => section.id === sectionId);

        if (!section) return;

        if (this.isValidationError('delete', 'section', sectionId)) return;

        // Per-question validation kept for defence-in-depth.
        if (this.checkForValidationErrors([section])) return;
    
        // Collect non-UUID IDs
        const { questionIds } = this.collectNonUUIDIds([section]);
    
        if (questionIds.length > 0) {
            this.deletedQuestionIds = this.deletedQuestionIds.concat(questionIds);
        }
    
        if (!this.isUUID(sectionId)) {
            this.deletedSectionIds.push(sectionId);
        }

        this.currentPage = {
            ...this.currentPage, 
            sections: this.currentPage.sections.filter(section => section.id !== sectionId)
        };
        console.log('Updated currentPage after section deletion:', this.currentPage);

    }
    
    /**
     * Deletes a component from the current page.
     * If the componentId is not a valid UUID, it is added to the deletedQuestionIds array.
     * The component is removed from the currentPage.sections.columns.components array.
     * @param {string} componentId - The ID of the component to be deleted.
     * @returns {void}
     */
    deleteComponent(componentId, trackDeletion = true) {
        if (this.isValidationError('delete', 'question', componentId)) return;
    
        if (trackDeletion && !this.isUUID(componentId)) {
            this.deletedQuestionIds.push(componentId);
        }
    
        this.currentPage.sections.forEach(section => {
            section.columns.forEach(column => {
                column.components = column.components.filter(component => component.id !== componentId);
            });
        });
    
        console.log('Updated currentPage after component deletion:', this.currentPage);
    }

    /**
     * Checks if the given ID starts with 'UUID'.
     * @param {string} id - The ID to check.
     * @returns {boolean} - Returns true if the ID starts with 'UUID', otherwise false.
     */
    isUUID(id){
        return id.startsWith('UUID');
    }

    // STATE MANAGEMENT
    pastStates = [];
    futureStates = [];

    // Call this method whenever there is a change in state
    /**
     * Saves the current state of the form builder.
     * This method pushes the current state into the pastStates array, which can be used for undo functionality.
     * It deep clones the necessary properties of the current state using JSON.parse and JSON.stringify.
     * It also clears the futureStates array to ensure a new action starts a new future state.
     */
    // Soft cap on the undo stack to prevent unbounded memory growth on long
    // editing sessions with large templates (each state is a full deep clone).
    static UNDO_HISTORY_CAP = 50;

    saveState() {
        this.pastStates.push({
            formSettings: JSON.parse(JSON.stringify(this.formSettings)),
            currentPage: JSON.parse(JSON.stringify(this.currentPage)),
            deletedPageIds: [...this.deletedPageIds],
            deletedSectionIds: [...this.deletedSectionIds],
            deletedQuestionIds: [...this.deletedQuestionIds],
            selection: this.selection ? JSON.parse(JSON.stringify(this.selection)) : this.selection,
            selectionId: this.selectionId,
            selectionStructure: this.selectionStructure,
            pageArray: [...this.pageArray],
            currentPageIndex: this.currentPageIndex
        });
        if (this.pastStates.length > NeuraFormBuilder.UNDO_HISTORY_CAP) {
            // Drop the oldest entries when we exceed the cap.
            this.pastStates.splice(0, this.pastStates.length - NeuraFormBuilder.UNDO_HISTORY_CAP);
        }
        this.isDirty = true;
        // Any new action invalidates the redo stack.
        this.futureStates = [];
    }

    /**
     * Handles the undo functionality by reverting to the previous state.
     */
    handleUndo() {
        if (this.pastStates.length > 0) {
            const lastState = this.pastStates.pop();
            this.futureStates.push(this.getCurrentState());

            this.applyState(lastState);
        }
    }

    /**
     * Handles the redo functionality by applying the next state from the futureStates array.
     * Moves the current state to the pastStates array before applying the next state.
     */
    handleRedo() {
        if (this.futureStates.length > 0) {
            const nextState = this.futureStates.pop();
            this.pastStates.push(this.getCurrentState());

            this.applyState(nextState);
        }
    }

    /**
     * Returns the current state of the form builder.
     * @returns {Object} The current state of the form builder.
     */
    getCurrentState() {
        return {
            formSettings: this.formSettings,
            currentPage: this.currentPage,
            deletedPageIds: this.deletedPageIds,
            deletedSectionIds: this.deletedSectionIds,
            deletedQuestionIds: this.deletedQuestionIds,
            selection: this.selection,
            selectionId: this.selectionId,
            selectionStructure: this.selectionStructure,
            pageArray: this.pageArray,
            // MOVED TO GETTER
            // totalPageCount: this.totalPageCount,
            currentPageIndex: this.currentPageIndex
        };
    }

    /**
     * Applies the given state to the neuraFormBuilder component.
     * 
     * @param {Object} state - The state object containing the properties to be applied.
     * @returns {void}
     */
    applyState(state) {
        this.formSettings = state.formSettings;
        this.currentPage = state.currentPage;
        this.deletedPageIds = state.deletedPageIds;
        this.deletedSectionIds = state.deletedSectionIds;
        this.deletedQuestionIds = state.deletedQuestionIds;
        this.selection = state.selection;
        this.selectionId = state.selectionId;
        this.selectionStructure = state.selectionStructure;
        this.pageArray = state.pageArray;
        // MOVED TO GETTER
        //this.totalPageCount = state.totalPageCount;
        //this.currentPageIndex = state.currentPageIndex;        
    }


    handleCopy(){
        console.log('handleCopyComponent');
        // only copy if it's a component
        this.copyComponent = {...this.selection};
        this.copyComponentStructure = this.selectionStructure;

    }

    handlePaste(){
        console.log('handlePasteComponent');
        try{

            if((!this.copyComponent || !this.copyComponentStructure) && this.selectionStructure !== 'Page' && this.selectionStructure !== 'Section' && this.selectionStructure !== 'Component'){
                return;
            }
            // if the copy componet is a component then we can only paste it if the selection is a section or component
            this.saveState();
            let newAddition = JSON.parse(JSON.stringify(this.copyComponent));
            newAddition.id = generateUUID();
            newAddition.attributes.Id = newAddition.id;

            if(this.copyComponentStructure === 'Component' && (this.selectionStructure === 'Section' || this.selectionStructure === 'Component')){

                // if the selection is a section then we need to add the component to the last column of the section
                if(this.selectionStructure === 'Section'){
                    let section = this.getSectionBySectionId(this.selectionId);
                    let lastColumn = section.columns[section.columns.length - 1];
                    lastColumn.components.push(newAddition);
                } else {
                    // if the selection is a component then we need to add the component to the same column as the selection
                    let column = this.getColumnByComponetId(this.selectionId);
                    column.components.push(newAddition);
                }
                this.selectionStructure = 'Component';
            }

            // if the copy component is a section then we can only paste it if the selection is a section or page.
            if(this.copyComponentStructure === 'Section' && (this.selectionStructure === 'Page' || this.selectionStructure === 'Section')){
                
                // update id's of all components within the copyComponent
                newAddition = this.updateComponentsToUUID(newAddition);
                console.log('new Addtion');
                console.dir(newAddition);
                // if the selection is a page then we need to add the section to the last page
                this.currentPage.sections.push(newAddition);
                this.selectionStructure = 'Section';
            }

            // if the copy component is a page then we can ignore selection and paste it as a new page.
            if(this.copyComponentStructure === 'Page'){
                newAddition.attributes[FIELDS.Form_Page__c.Title.fieldApiName] = newAddition.attributes[FIELDS.Form_Page__c.Title.fieldApiName] + ' (Copy)';

                // update id's of all sections and components within the copyComponent
                newAddition = this.updateSectionsToUUID(newAddition);

                this.formSettings.pages.push(newAddition);
                this.pageArray.push(newAddition.attributes[FIELDS.Form_Page__c.Title.fieldApiName]);
                
                // MOVED TO GETTER
                //this.totalPageCount = this.formSettings.pages.length;
                //update currentPage and selection
                this.currentPage = newAddition;
                //this.currentPageIndex = this.findPageIndexById(this.currentPage.id);
                this.selectionStructure = 'Page';

            }

            this.selection = newAddition;
            this.selectionId = newAddition.id;

            this.updateFormSettings();


        } catch (error) {
            console.error('Error in handlePaste', error.message);
        }
    }
    

    updateSectionsToUUID(newAddition){
        newAddition.sections.forEach(section => {
            section.id = generateUUID();
            section.attributes.Id = section.id;
            section.columns.forEach(column => {
                column.id = generateUUID();
                column.components.forEach(component => {
                    component.id = generateUUID();
                    component.attributes.Id = component.id;
                });
            });
        });

        return newAddition;
    }

    updateComponentsToUUID(newAddition){
        newAddition.columns.forEach(column => {
            column.id = generateUUID();
            column.components.forEach(component => {
                component.id = generateUUID();
                component.attributes.Id = component.id;
            });
        });

        return newAddition;
    }

    isValidationError(action, type, id){
        // Returns true if the action should be blocked.

        if (action !== 'delete') return false;

        // Direct: deleting a question that is referenced by any condition.
        if (type === 'question' && this.isQuestionUsedInConditions(id)) {
            this.showToast(
                'Cannot delete',
                'This question is referenced by a condition and cannot be deleted. Remove the condition first.',
                'error'
            );
            return true;
        }

        // Cascade: deleting a section that *contains* such a question.
        if (type === 'section') {
            const blocker = this.findReferencedQuestionInSection(this.findSectionById(id));
            if (blocker) {
                this.showToast(
                    'Cannot delete',
                    `Section contains a question ("${blocker}") referenced by a condition. Remove the condition first.`,
                    'error'
                );
                return true;
            }
        }

        // Cascade: deleting a page that contains any such question.
        if (type === 'page') {
            const page = this.findPageById(id);
            for (const section of (page?.sections ?? [])) {
                const blocker = this.findReferencedQuestionInSection(section);
                if (blocker) {
                    this.showToast(
                        'Cannot delete',
                        `Page contains a question ("${blocker}") referenced by a condition. Remove the condition first.`,
                        'error'
                    );
                    return true;
                }
            }
        }

        return false;
    }

    findReferencedQuestionInSection(section) {
        if (!section) return null;
        for (const column of section.columns) {
            for (const component of column.components) {
                if (this.isQuestionUsedInConditions(component.id)) {
                    return component.attributes?.[FIELDS.Form_Question__c.Question.fieldApiName] || component.id;
                }
            }
        }
        return null;
    }

    showToast(title, message, variant) {
        const toastEvent = new ShowToastEvent({ title, message, variant });
        this.dispatchEvent(toastEvent);
    }

    isQuestionUsedInConditions(questionId) {
        const allConditions = this.getAllConditions();
        
        for (let condition of allConditions) {
            if (condition.resource === questionId) {
                return true;
            }
        }
        return false;
    }

    getAllConditions() {
        const allConditions = [];
        
        this.formSettings.pages.forEach(page => {
            // Extract conditions from page level
            const pageConditionsString = page.attributes[FIELDS.Form_Page__c.Conditions.fieldApiName];
            if (pageConditionsString) {
                const pageConditions = JSON.parse(pageConditionsString).conditions;
                allConditions.push(...pageConditions);
            }
    
            page.sections.forEach(section => {
                // Extract conditions from section level
                const sectionConditionsString = section.attributes[FIELDS.Form_Section__c.Conditions.fieldApiName];
                if (sectionConditionsString) {
                    const sectionConditions = JSON.parse(sectionConditionsString).conditions;
                    allConditions.push(...sectionConditions);
                }
    
                section.columns.forEach(column => {
                    column.components.forEach(question => {
                        // Extract conditions from question level
                        const questionConditionsString = question.attributes[FIELDS.Form_Question__c.Conditions.fieldApiName];
                        if (questionConditionsString) {
                            const questionConditions = JSON.parse(questionConditionsString).conditions;
                            allConditions.push(...questionConditions);
                        }
                    });
                });
            });
        });
    
        return allConditions;
    }

}