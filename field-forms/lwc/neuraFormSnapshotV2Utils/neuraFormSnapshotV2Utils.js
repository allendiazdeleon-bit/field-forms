/**
 * Read-side assembly helpers for the v2 form-template snapshot.
 *
 * See docs/snapshot-v2.md for the on-disk shape. Briefly: each
 * Form_Template_Snapshot__c row carries one chunk of one payload type
 * (Pages / Sections / Questions / *Conditions) with an ordinal index. The
 * renderer concatenates the parsed arrays per type to reconstruct the
 * legacy-shape JSON strings the rest of the pipeline already consumes.
 *
 * Used by both neuraFormMobile (offline GraphQL + Apex fallback) and
 * neuraFormDataService (desktop UI API).
 */

const PAYLOAD_KEY = Object.freeze({
    Pages: 'Pages_JSON__c',
    Sections: 'Sections_JSON__c',
    Questions: 'Questions_JSON__c',
    PageConditions: 'Page_Conditions__c',
    SectionConditions: 'Section_Conditions__c',
    QuestionConditions: 'Question_Conditions__c'
});

/**
 * Promote v2 chunk rows into the legacy field keys on a formTemplate.
 *
 * @param {object} formTemplate - bare object keyed by Form_Template__c
 *     field API names (Pages_JSON__c, Questions_JSON__c, etc.).
 * @param {Array<{type: string, index: number, payload: string}>} chunks -
 *     normalized chunk rows; pass an empty array when no v2 data is
 *     available.
 * @returns {object} A clone of formTemplate. When chunks are present,
 *     legacy keys are overridden with the assembled v2 payload. When
 *     chunks are empty, formTemplate is returned unchanged so the
 *     renderer reads the legacy fields as before.
 */
export function applySnapshotV2(formTemplate, chunks) {
    if (!chunks || chunks.length === 0) return formTemplate;

    const byType = {};
    for (const c of chunks) {
        if (!c || !c.type) continue;
        if (!byType[c.type]) byType[c.type] = [];
        byType[c.type].push(c);
    }
    for (const arr of Object.values(byType)) {
        arr.sort((a, b) => a.index - b.index);
    }

    const assemble = (type) => {
        const arr = byType[type];
        if (!arr || arr.length === 0) return null;
        const items = [];
        for (const c of arr) {
            if (!c.payload) continue;
            try {
                const parsed = JSON.parse(c.payload);
                if (Array.isArray(parsed)) items.push(...parsed);
            } catch (e) {
                // Bad chunk: degrade to empty rather than blow up the
                // whole form. Logged so the on-call notices it.
                // eslint-disable-next-line no-console
                console.error('Snapshot chunk parse failure', c.type, c.index, e);
            }
        }
        return JSON.stringify(items);
    };

    const result = { ...formTemplate };
    for (const [type, key] of Object.entries(PAYLOAD_KEY)) {
        const assembled = assemble(type);
        if (assembled !== null) result[key] = assembled;
    }
    // v2 consolidates all questions into Questions_JSON__c; clear the
    // legacy overflow chunk fields so downstream concatenation doesn't
    // read stale data.
    if (byType.Questions) {
        result.Questions_JSON_1__c = null;
        result.Questions_JSON_2__c = null;
    }
    return result;
}

/**
 * Normalize a Form_Template_Snapshots__r subquery response (UI API /
 * offline GraphQL) into the {type, index, payload} shape that
 * applySnapshotV2 consumes. Each scalar in the GraphQL response is
 * wrapped in { value: ... } — flatten it.
 */
export function normalizeSnapshotChunksFromGraphQL(formTemplate) {
    const edges = formTemplate &&
        formTemplate.Form_Template_Snapshots__r &&
        formTemplate.Form_Template_Snapshots__r.edges;
    if (!edges) return [];
    return edges.map((e) => ({
        type: e && e.node && e.node.Payload_Type__c && e.node.Payload_Type__c.value,
        index: Number(
            (e && e.node && e.node.Chunk_Index__c && e.node.Chunk_Index__c.value) || 0
        ),
        payload: e && e.node && e.node.Payload__c && e.node.Payload__c.value
    }));
}

/**
 * Normalize an Apex-returned list of Form_Template_Snapshot__c SObjects
 * (from NeuraFormMobileController.FormDetails.snapshotChunks) into the
 * {type, index, payload} shape.
 */
export function normalizeSnapshotChunksFromApex(apexChunks) {
    if (!apexChunks) return [];
    return apexChunks.map((c) => ({
        type: c.Payload_Type__c,
        index: Number(c.Chunk_Index__c == null ? 0 : c.Chunk_Index__c),
        payload: c.Payload__c
    }));
}
