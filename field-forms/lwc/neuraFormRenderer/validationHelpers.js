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
    if (!requiredField || !answerField) return out;

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
            const value = answer && answer[answerField];
            if (isAnswerEmpty(value)) {
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
