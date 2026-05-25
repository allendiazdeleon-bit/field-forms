/**
 * Prefill helpers — pure utilities for the "Same as last visit" feature.
 *
 * Background:
 *   Routine maintenance forms repeat 70%+ of the same answers visit to
 *   visit on the same asset. The prefill button looks up the most recent
 *   completed Linked_Form for the host and copies answers in. Saves a
 *   meaningful amount of time in the field.
 *
 * Why a thin module:
 *   The orchestration (Apex call, applying answers, refreshing the child
 *   page) lives on the renderer because it touches reactive state and
 *   refs. The PURE parts — the host->parent-field mapping and the
 *   user-facing messages — extract cleanly and become testable. Adding
 *   a new host object type is now a one-row change here, not a code
 *   spelunking exercise in the renderer's switch statement.
 *
 * Tests live in __tests__/prefillController.test.js.
 */

/**
 * Maps a host object's API name to the lookup field on Form_Answer that
 * points back to the matching parent record. The Apex
 * NeuraFormMobileController.getLastVisitAnswers query uses this field
 * name to find prior completed forms for the same host record.
 */
const HOST_TO_PARENT_FIELD = Object.freeze({
    WorkOrder: 'Work_Order__c',
    WorkOrderLineItem: 'Work_Order_Line_Item__c',
    ServiceAppointment: 'Service_Appointment__c'
});

/**
 * @param {string} hostObjectApiName
 * @returns {string|null}  The Form_Answer__c lookup field for that host,
 *                         or null if the host isn't supported by prefill.
 */
export function parentFieldForHost(hostObjectApiName) {
    return HOST_TO_PARENT_FIELD[hostObjectApiName] || null;
}

/**
 * User-facing toast after a successful prefill.
 */
export function formatPrefillSuccessMessage(count) {
    const n = Number(count) || 0;
    const answerWord = n === 1 ? 'answer' : 'answers';
    return `Copied ${n} ${answerWord} from the last visit. Review and adjust.`;
}

/**
 * Static messages — centralized so a future i18n pass has one file to
 * walk and so the renderer doesn't carry copy strings inline.
 */
export const PREFILL_MESSAGES = Object.freeze({
    MISSING_CONTEXT:
        'Prefill requires the host record context to be available.',
    NO_PRIOR_FOUND:
        'No prior completed visit found for this asset to copy from.'
});
