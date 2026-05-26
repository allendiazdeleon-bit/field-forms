/**
 * Pillar 5 helpers for the findings panel ↔ renderer interaction.
 * Extracted as a pure module so the renderer's onfindingclick /
 * onfindingaddphoto path can be unit-tested without spinning up the
 * whole c-neura-form-renderer component.
 */

/**
 * Walk the formObject pages → sections → questions looking for the
 * question whose External_Reference__c matches `externalRef`. Returns
 * `{ pageIndex, questionId }` on hit or null when no question matches.
 *
 * Findings reference questions via External_Reference (the catalog
 * identity that survives binding swaps) — never by question Id.
 *
 * The walk is short-circuit: stops at the first match. For forms with
 * a single catalog ref bound multiple times (uncommon but valid), the
 * first occurrence wins; refining to "nearest to current page" is a
 * follow-up if real usage shows the wrong target on repeat refs.
 */
export function findQuestionLocation(formObject, externalRef) {
    if (!externalRef) return null;
    const pages = formObject?.pages || [];
    for (let i = 0; i < pages.length; i++) {
        const sections = pages[i]?.sections || [];
        for (const section of sections) {
            const questions = section?.questions || [];
            for (const q of questions) {
                if (q?.External_Reference__c === externalRef) {
                    return { pageIndex: i, questionId: q.Id };
                }
            }
        }
    }
    return null;
}
