/**
 * Page-dictation helpers — pure transforms extracted from
 * neuraFormRenderer's handlePageDictation in wave 31.
 *
 * What's here:
 *   - collectDictatableQuestions: walks a page tree and produces the
 *     question manifest the Apex mapTranscriptToQuestions endpoint
 *     expects. Skips questions whose conditional rendering hid them
 *     (shouldRender === false).
 *   - formatDictationDiagnostic: picks the right "no mappings found"
 *     toast message. Reads from the Apex result's questionCount /
 *     diagnostic fields.
 *   - formatDictationSuccessMessage: formats the post-mapping toast.
 *
 * What stayed on the renderer (and why):
 *   The orchestration (Apex call, applyDictatedAnswer per mapping,
 *   refs.formPage.applyDictation() to imperatively update the DOM,
 *   showToastMessage side effects) all touch reactive state or child
 *   refs. The renderer keeps that; this module owns the pure transforms
 *   so they're directly testable.
 */

/**
 * Walk a page's sections + questions and emit one entry per visible
 * question with the metadata Apex needs to match a free-text transcript.
 *
 * @param {object} page
 *   The current page object (with sections -> questions).
 * @param {object} fieldNames
 *   Resolved field API names so this module stays namespace-agnostic.
 *   @param {string} fieldNames.type      Question type field name
 *   @param {string} fieldNames.valueSet  Value-set field name (JSON)
 *   @param {string} fieldNames.question  Question-text field name
 * @returns {Array<{questionId:string, label:string, type:string, allowedValues:string[]}>}
 */
export function collectDictatableQuestions(page, fieldNames = {}) {
    const out = [];
    if (!page || !Array.isArray(page.sections)) return out;

    const { type: typeField, valueSet: valueSetField, question: questionField } = fieldNames;

    page.sections.forEach((section) => {
        if (!section || !Array.isArray(section.questions)) return;
        section.questions.forEach((q) => {
            if (!q) return;
            // Conditional rendering may have hidden this question — don't
            // ask the user to dictate into a field they can't see.
            if (q.shouldRender === false) return;

            let allowed = [];
            if (valueSetField) {
                try {
                    const raw = q[valueSetField];
                    if (raw) {
                        allowed = JSON.parse(raw)
                            .map((o) => (o && o.value) || null)
                            .filter(Boolean);
                    }
                } catch (e) {
                    allowed = [];
                }
            }

            out.push({
                questionId: q.Id,
                label: (questionField && q[questionField]) || q.Name || '',
                type: (typeField && q[typeField]) || null,
                allowedValues: allowed
            });
        });
    });

    return out;
}

/**
 * Pick the user-facing message for the "Apex returned no mappings" case.
 * Honors a server-side diagnostic when present, otherwise picks one of
 * three local fallbacks based on how many questions were even available.
 */
export function formatDictationDiagnostic(result) {
    const qCount = result && result.questionCount;
    if (qCount === 0) {
        return 'No questions visible on this page to match against.';
    }
    if (result && result.diagnostic) {
        return result.diagnostic;
    }
    const visible = Number.isFinite(qCount) ? qCount : 0;
    return `Couldn't match any fields to what you said (${visible} questions on page). Try mentioning the field name, like "the customer is John Doe".`;
}

/**
 * Format the success toast after a dictation pass.
 *
 * @param {number} mappingsCount
 * @param {string} [source]  Server-reported source label, e.g. 'agentforce'.
 */
export function formatDictationSuccessMessage(mappingsCount, source) {
    const n = Number(mappingsCount) || 0;
    const fieldWord = n === 1 ? 'field' : 'fields';
    const sourceSuffix = source === 'agentforce' ? ' (Agentforce)' : '';
    return `Filled ${n} ${fieldWord} from dictation${sourceSuffix}. Review before continuing.`;
}
