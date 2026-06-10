/**
 * Validation helpers — pure tree walkers extracted from
 * neuraFormRenderer's collectMissingRequiredLabels in wave 32.
 *
 * Why this is here:
 *   The renderer's checkValidations() is now a thin shim around
 *   refs.formPage.checkValidity(). The actual "what does the user need
 *   to know is missing?" logic — required + visible + empty — was
 *   inline in collectMissingRequiredLabels. Pulling it into a pure
 *   walker means we can test the empty-detection rules directly
 *   (whitespace, null, undefined, present-with-value) without standing
 *   up a renderer instance.
 *
 *   The full save-pipeline orchestration (handleFooterButtonClick →
 *   checkValidations → deleteAnswers → uploadAnswers → changePage)
 *   stays on the renderer because it's inherently coupled to reactive
 *   state and child refs. Extracting it would require a much bigger
 *   architecture change (move to a reactive state container) than is
 *   in scope for this session.
 */
import { QUESTION_TYPE_GROUPS } from 'c/neuraFormSchemaUtils';

/**
 * Walk the current page's questions and return the user-facing labels
 * of every required-and-visible question whose answer is empty.
 *
 * @param {object} page  The currentPage object (sections -> questions).
 * @param {Map<string, object>|null|undefined} questionAnswerMap
 *     Live answer map (question Id -> answer entry). May be a real Map,
 *     a Map-like, or null — handled defensively.
 * @param {object} fieldNames  Resolved field API names (namespace-aware
 *     in production, plain in tests).
 *   @param {string} fieldNames.required  Form_Question__c.Required__c
 *   @param {string} fieldNames.question  Form_Question__c.Question__c
 *   @param {string} fieldNames.answer    Form_Answer__c.Answer__c
 * @returns {string[]}  Labels of empty-required-visible questions.
 */
export function collectMissingRequiredLabels(page, questionAnswerMap, fieldNames = {}) {
    const out = [];
    if (!page || !Array.isArray(page.sections)) return out;

    const requiredField = fieldNames.required;
    const questionField = fieldNames.question;
    const answerField = fieldNames.answer;
    const typeField = fieldNames.type;
    if (!requiredField || !answerField) return out;

    // File/signature answers don't populate Answer__c — their content is
    // the attached file. Validate them on file presence, not the text value.
    const FILE_TYPES = QUESTION_TYPE_GROUPS.FILE;

    const getAnswer = (id) => {
        if (!questionAnswerMap || typeof questionAnswerMap.get !== 'function') {
            return undefined;
        }
        return questionAnswerMap.get(id);
    };

    page.sections.forEach((section) => {
        if (!section || !Array.isArray(section.questions)) return;
        section.questions.forEach((q) => {
            if (!q) return;
            if (!q[requiredField]) return;
            // Conditional rendering hid the question — don't gate
            // submit on something the user can't see.
            if (q.shouldRender === false) return;
            const answer = getAnswer(q.Id);
            const qType = typeField ? q[typeField] : undefined;
            let empty;
            if (FILE_TYPES.includes(qType)) {
                // Answered when a file is attached (pre-upload filesData) or a
                // saved answer record exists (file lives as a ContentVersion).
                const hasFile = !!answer && (
                    (Array.isArray(answer.filesData) && answer.filesData.length > 0) ||
                    !!answer.Id ||
                    answer.uploadCompleted === true
                );
                empty = !hasFile;
            } else {
                empty = isAnswerEmpty(answer && answer[answerField]);
            }
            if (empty) {
                const label =
                    (questionField && q[questionField]) ||
                    q.Name ||
                    'Unnamed question';
                out.push(label);
            }
        });
    });
    return out;
}

/**
 * The "empty answer" rule lives in one place so the renderer + future
 * validation surfaces share it. An answer counts as empty when it's
 * undefined, null, or a string that's whitespace-only.
 */
export function isAnswerEmpty(value) {
    if (value === undefined || value === null) return true;
    return String(value).trim() === '';
}
