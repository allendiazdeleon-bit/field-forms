// Helpers for the offline draft-parent fallback (audit item B4).
//
// When the host record (WorkOrder / WorkOrderLineItem / ServiceAppointment) is
// itself a draft - i.e. it was created offline - the server-side flow that
// normally materialises Linked_Form records hasn't run, so the mobile component
// finds nothing to render. These helpers let the LWC create draft Linked_Forms
// locally from Default_Form mappings, and rebuild the full form structure from
// a primed Form_Template without going through the offline-unfriendly GraphQL
// detailsQuery (which can't return draft records).

import { createRecord } from 'lightning/uiRecordApi';
import { FIELDS, OBJECTS } from 'c/neuraFormSchemaUtils';

/**
 * Create a draft Linked_Form__c via Lightning Data Service. Returns the
 * resulting record (draft Id under .id). LDS drops the create into the local
 * draft queue when offline; it syncs to the server when the parent record syncs.
 */
export async function createDraftLinkedForm({
    formTemplateId,
    parentField,
    parentRecordId
}) {
    const fields = {
        [FIELDS.Linked_Form__c.FormTemplate.fieldApiName]: formTemplateId,
        [FIELDS.Linked_Form__c.Status.fieldApiName]: 'Not Started',
        [FIELDS.Linked_Form__c.CurrentPage.fieldApiName]: 1
    };
    fields[parentField] = parentRecordId;

    return createRecord({
        apiName: OBJECTS.Linked_Form__c.objectApiName,
        fields
    });
}

/**
 * Returns the API name of the parent lookup on Linked_Form__c for a given
 * host object. Centralised so component code and the briefcase rule stay
 * in lockstep.
 */
export function parentLookupFieldFor(objectApiName) {
    switch (objectApiName) {
        case 'WorkOrder':
            return FIELDS.Linked_Form__c.WorkOrder.fieldApiName;
        case 'WorkOrderLineItem':
            return FIELDS.Linked_Form__c.WorkOrderLineItem.fieldApiName;
        case 'ServiceAppointment':
            return FIELDS.Linked_Form__c.ServiceAppointment.fieldApiName;
        default:
            return undefined;
    }
}

/**
 * Resolve a normalised primitive value from the various wrapper shapes that
 * getRecord, uiGraphQLApi, and the JSON snapshot helpers return. Mirrors the
 * `standardTransform` logic in neuraFormMobile but works on plain records.
 */
export function unwrap(value) {
    if (value && typeof value === 'object' && 'value' in value) {
        return value.value;
    }
    return value;
}

/**
 * Build the full form object (pages -> sections -> questions) from a primed
 * Form_Template getRecord result. Used when a Linked_Form is a local draft so
 * the GraphQL detailsQuery would return no rows. Answers default to an empty
 * list since a brand-new draft Linked_Form has no children yet.
 *
 * The shape produced matches what neuraFormMobile.transformDetailData returns
 * so downstream renderer code is identical.
 */
export function buildFormObjectFromPrimedTemplate({
    templateRecord,
    draftLinkedFormId,
    transforms
}) {
    if (!templateRecord || !templateRecord.fields) return undefined;
    const f = templateRecord.fields;

    const formTemplate = {
        Id: templateRecord.id
    };
    Object.keys(f).forEach(k => {
        formTemplate[k] = unwrap(f[k]);
    });

    const questionJSONArray = [
        formTemplate[FIELDS.Form_Template__c.QuestionsJSON.fieldApiName],
        formTemplate[FIELDS.Form_Template__c.QuestionsJSON1.fieldApiName],
        formTemplate[FIELDS.Form_Template__c.QuestionsJSON2.fieldApiName]
    ];

    let questions = transforms.combineAndTransformJSON(
        questionJSONArray,
        [],
        'answers',
        OBJECTS.Form_Question__c.objectApiName
    );
    questions = transforms.updateRenderingConditions(
        questions,
        formTemplate[FIELDS.Form_Template__c.QuestionConditions.fieldApiName]
    );

    let sections = transforms.transformJSON(
        formTemplate[FIELDS.Form_Template__c.SectionsJSON.fieldApiName],
        questions,
        'questions',
        OBJECTS.Form_Section__c.objectApiName
    );
    sections = transforms.updateRenderingConditions(
        sections,
        formTemplate[FIELDS.Form_Template__c.SectionConditions.fieldApiName]
    );

    let pages = transforms.transformJSON(
        formTemplate[FIELDS.Form_Template__c.PagesJSON.fieldApiName],
        sections,
        'sections',
        OBJECTS.Form_Page__c.objectApiName
    );
    pages = transforms.updateRenderingConditions(
        pages,
        formTemplate[FIELDS.Form_Template__c.PageConditions.fieldApiName]
    );

    const linkedForm = { Id: draftLinkedFormId };
    linkedForm[FIELDS.Linked_Form__c.Status.fieldApiName] = 'Not Started';
    linkedForm[FIELDS.Linked_Form__c.CurrentPage.fieldApiName] = 1;

    const formObject = {
        Id: formTemplate.Id,
        Name: formTemplate.Name,
        pages,
        linkedForm,
        isDraft: true
    };
    formObject[FIELDS.Form_Template__c.SelectorColor.fieldApiName] =
        formTemplate[FIELDS.Form_Template__c.SelectorColor.fieldApiName];

    return formObject;
}

/**
 * Return the list of Form_Template fields to request via getRecord when
 * rebuilding a draft form locally. Explicit field lists are required for
 * offline support.
 */
export function templateFieldsForDraftLoad() {
    return [
        FIELDS.Form_Template__c.Id,
        FIELDS.Form_Template__c.Name,
        FIELDS.Form_Template__c.SelectorColor,
        FIELDS.Form_Template__c.PagesJSON,
        FIELDS.Form_Template__c.SectionsJSON,
        FIELDS.Form_Template__c.QuestionsJSON,
        FIELDS.Form_Template__c.QuestionsJSON1,
        FIELDS.Form_Template__c.QuestionsJSON2,
        FIELDS.Form_Template__c.PageConditions,
        FIELDS.Form_Template__c.SectionConditions,
        FIELDS.Form_Template__c.QuestionConditions
    ];
}
