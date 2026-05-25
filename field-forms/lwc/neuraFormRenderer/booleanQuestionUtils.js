/**
 * Boolean-question utilities — pure helpers for the Toggle / Checkbox
 * question types that need answer-map normalization at page-load time.
 *
 * Why this lives in its own module:
 *   The "what counts as a boolean question?" decision was a literal
 *   string comparison repeated in two methods on neuraFormRenderer
 *   (filter on getBooleanQuestions + branch on updateBooleanQuestionAnswerMap).
 *   Pulling the list into one place means adding a new boolean-like
 *   question type later is a one-line change here, not a hunt through
 *   the renderer. The current renderer comment explicitly anticipates
 *   this: "Add the type accordingly in future when more boolean type
 *   fields are introduced."
 */

/**
 * Question Type__c values that are conceptually boolean — i.e. their
 * answer is true/false rather than a string. Update this list when
 * adding a new boolean-flavored input type.
 */
const BOOLEAN_QUESTION_TYPES = Object.freeze(['Toggle', 'Checkbox']);

/**
 * @param {string} typeValue  A Form_Question__c.Type__c value.
 * @returns {boolean}
 */
export function isBooleanQuestionType(typeValue) {
    return BOOLEAN_QUESTION_TYPES.includes(typeValue);
}

/**
 * Filter a section's questions to those of boolean-flavored type.
 *
 * @param {Array<object>} questions  The section.questions array.
 * @param {string} typeFieldApiName  The Type__c field name as resolved
 *    by the renderer's FIELDS.Form_Question__c.Type.fieldApiName. Passed
 *    in (rather than imported) so this helper stays namespace-agnostic.
 * @returns {Array<object>}
 */
export function filterBooleanQuestions(questions, typeFieldApiName) {
    if (!Array.isArray(questions) || !typeFieldApiName) return [];
    return questions.filter((q) => q && isBooleanQuestionType(q[typeFieldApiName]));
}

// Exposed for tests that want to assert the registry directly.
export { BOOLEAN_QUESTION_TYPES };
