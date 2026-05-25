/**
 * Writes the chunked v2 form-template snapshot (Form_Template_Snapshot__c).
 *
 * One Form_Template's snapshot is N rows, partitioned by Payload_Type__c
 * (Pages / Sections / Questions / PageConditions / SectionConditions /
 * QuestionConditions) and ordered by Chunk_Index__c. Each Payload__c chunk
 * is a complete, parseable JSON array; the renderer concatenates the parsed
 * arrays on read. The chunked layout removes the legacy 393K snapshot cap
 * that blocked large compliance forms (Steritech-class audits).
 *
 * Activated by FieldForms_Configuration__c.Snapshot_V2_Enabled__c. The
 * legacy fields on Form_Template__c remain in place as a fallback when this
 * flag is off. The existing Disable_Form_Template_JSON_Trigger__c kill
 * switch in the page/section/question triggers still suppresses both paths.
 *
 * Strategy: delete-then-insert per template. Idempotent and avoids stale
 * orphan chunks when a template shrinks. Runs inside the existing
 * NeuraFormSnapshotQueueable transaction.
 *
 * See docs/snapshot-v2.md.
 */
public with sharing class NeuraFormSnapshotV2 {

    private static final Integer MAX_CHUNK_LENGTH = 131072;
    private static final String SCHEMA_VERSION = 'v2.0';

    public static final String TYPE_PAGES = 'Pages';
    public static final String TYPE_SECTIONS = 'Sections';
    public static final String TYPE_QUESTIONS = 'Questions';
    public static final String TYPE_PAGE_CONDITIONS = 'PageConditions';
    public static final String TYPE_SECTION_CONDITIONS = 'SectionConditions';
    public static final String TYPE_QUESTION_CONDITIONS = 'QuestionConditions';

    /**
     * True when v2 snapshot writes should be used. Reads the per-user
     * hierarchy custom setting, matching the existing kill-switch lookup
     * pattern in the Form_Page/Section/Question triggers.
     */
    public static Boolean isEnabled() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        return cfg != null && cfg.Snapshot_V2_Enabled__c == true;
    }

    /**
     * Replace the snapshot for each provided template with a fresh set of
     * chunk rows. One delete + one insert; safe to call inside the
     * snapshot queueable.
     */
    public static void rebuild(
        Set<Id> templateIds,
        Map<Id, NeuraFormLogic.FormTemplateWrapper> wrappers
    ) {
        if (templateIds == null || templateIds.isEmpty()) return;
        if (wrappers == null) wrappers = new Map<Id, NeuraFormLogic.FormTemplateWrapper>();

        List<Form_Template_Snapshot__c> existing = [
            SELECT Id FROM Form_Template_Snapshot__c
            WHERE Form_Template__c IN :templateIds
        ];
        if (!existing.isEmpty()) {
            delete existing;
        }

        List<Form_Template_Snapshot__c> rows = new List<Form_Template_Snapshot__c>();
        for (Id templateId : templateIds) {
            NeuraFormLogic.FormTemplateWrapper w = wrappers.get(templateId);
            // Always emit a row per payload type (even '[]') so the read path
            // can detect v2 presence by row count rather than the legacy
            // Form_Template__c fields.
            rows.addAll(buildChunkRows(templateId, TYPE_PAGES,
                w == null ? new List<String>() : serializeRecords(w.pages)));
            rows.addAll(buildChunkRows(templateId, TYPE_SECTIONS,
                w == null ? new List<String>() : serializeRecords(w.sections)));
            rows.addAll(buildChunkRows(templateId, TYPE_QUESTIONS,
                w == null ? new List<String>() : serializeRecords(w.questions)));
            rows.addAll(buildChunkRows(templateId, TYPE_PAGE_CONDITIONS,
                w == null ? new List<String>() : w.pageConditions));
            rows.addAll(buildChunkRows(templateId, TYPE_SECTION_CONDITIONS,
                w == null ? new List<String>() : w.sectionConditions));
            rows.addAll(buildChunkRows(templateId, TYPE_QUESTION_CONDITIONS,
                w == null ? new List<String>() : w.questionConditions));
        }

        if (!rows.isEmpty()) {
            insert rows;
        }
    }

    private static List<String> serializeRecords(List<SObject> records) {
        List<String> out = new List<String>();
        if (records == null) return out;
        for (SObject r : records) out.add(JSON.serialize(r));
        return out;
    }

    private static List<Form_Template_Snapshot__c> buildChunkRows(
        Id templateId, String payloadType, List<String> elements
    ) {
        List<String> chunks = chunkJsonElements(elements);
        List<Form_Template_Snapshot__c> rows = new List<Form_Template_Snapshot__c>();
        for (Integer i = 0; i < chunks.size(); i++) {
            rows.add(new Form_Template_Snapshot__c(
                Form_Template__c = templateId,
                Payload_Type__c = payloadType,
                Chunk_Index__c = i,
                Payload__c = chunks[i],
                External_Id__c = templateId + '|' + payloadType + '|' + i,
                Schema_Version__c = SCHEMA_VERSION
            ));
        }
        return rows;
    }

    /**
     * Pack pre-serialized JSON elements into [...] array chunks no larger
     * than MAX_CHUNK_LENGTH. Each chunk is a complete parseable JSON array.
     * Always emits at least one chunk (a bare '[]') so empty payload types
     * still produce a row.
     */
    @TestVisible
    private static List<String> chunkJsonElements(List<String> elements) {
        List<String> result = new List<String>();
        String current = '[';
        if (elements != null) {
            for (String el : elements) {
                if (el == null) continue;
                // A single element larger than MAX_CHUNK_LENGTH-2 can't fit
                // even in its own chunk — fail loudly rather than silently
                // truncate.
                if (el.length() + 2 > MAX_CHUNK_LENGTH) {
                    throw new NeuraFormLogic.CustomException(
                        'Snapshot element exceeds Payload__c capacity (' +
                        el.length() + ' chars > ' + (MAX_CHUNK_LENGTH - 2) + '). ' +
                        'Reduce the size of the underlying record or split it.'
                    );
                }
                // +2 reserves space for the closing ']' and a possible ','
                if (current.length() + el.length() + 2 > MAX_CHUNK_LENGTH) {
                    current += ']';
                    result.add(current);
                    current = '[';
                }
                if (current.length() > 1) current += ',';
                current += el;
            }
        }
        current += ']';
        result.add(current);
        return result;
    }
}
