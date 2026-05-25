/**
 * Skip-queue helpers — pure utilities for the "flag to revisit" pattern.
 *
 * Background:
 *   Technicians long-press a question to defer it and come back later.
 *   The renderer surfaces a count badge near the footer and blocks the
 *   final Submit until the queue is empty.
 *
 * Why a thin module instead of a controller factory:
 *   The skip queue's state is just an array of question ids that the
 *   template reads reactively. Keep the @track array on the renderer
 *   (so LWC sees it change); delegate the toggle + label math to pure
 *   functions here.
 *
 * Tests live in __tests__/skipQueueController.test.js.
 */

/**
 * Add or remove a question id from the skip queue. Returns a NEW array
 * so LWC's reactivity sees the change.
 *
 * @param {ReadonlyArray<string>} currentIds
 * @param {string} questionId  — no-op if falsy
 * @returns {string[]}
 */
export function toggleSkipped(currentIds, questionId) {
    if (!questionId) return currentIds;
    const list = Array.isArray(currentIds) ? currentIds : [];
    const idx = list.indexOf(questionId);
    if (idx >= 0) return list.filter((x) => x !== questionId);
    return [...list, questionId];
}

/**
 * User-facing label for the skip-queue badge near the form footer.
 */
export function formatSkippedBadgeLabel(count) {
    const n = Number(count) || 0;
    return n === 1 ? '1 to revisit' : `${n} to revisit`;
}

/**
 * Message shown when the user tries to Finish with items still skipped.
 * The renderer surfaces this via showToastMessage.
 */
export function formatBlockedSubmitMessage(count) {
    const n = Number(count) || 0;
    const fieldWord = n === 1 ? 'field' : 'fields';
    return `You still have ${n} ${fieldWord} flagged to revisit. Clear them before submitting.`;
}
