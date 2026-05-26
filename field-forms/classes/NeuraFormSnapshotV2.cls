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
     * Content fields that resolve through Form_Question_Catalog__c when
     * Question_Catalog_Enabled__c is on. Subset of the catalog's full field
     * list — only the fields the renderer currently consumes (matches the
     * Form_Question__c SOQL in NeuraFormLogic.updateJSON). Kept in sync
     * with NeuraFormCatalogBackfillBatch.CONTENT_FIELDS by hand; both lists
     * have to grow if a new content field is added to the catalog.
     */
    private static final List<String> CATALOG_RESOLVABLE_FIELDS = new List<String>{
        'Active_Message__c',
        'Calculation_Formula__c',
        'Calculation_Result_Format__c',
        'Decimal_Places__c',
        'Default_Value_Source__c',
        'Default_Value_Static__c',
        'Display_Rich_Text__c',
        'Font_Color__c',
        'Font_Size__c',
        'Inactive_Message__c',
        'Include_Comment__c',
        'Include_Photo__c',
        'Label_Visible__c',
        'Layout_Item__c',
        'Question__c',
        'Required__c',
        'Text_Alignment__c',
        'Type__c',
        'Value_Set__c'
    };

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
     * True when question content should resolve through
     * Form_Question_Catalog__c (with per-binding overrides). Independent
     * of isEnabled() — a customer can flip catalog reads on without
     * touching snapshot v2, though both flags being on is the typical
     * Phase 2 path.
     */
    @TestVisible
    private static Boolean isCatalogEnabled() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        return cfg != null && cfg.Question_Catalog_Enabled__c == true;
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

        // Pre-fetch catalog entries when catalog resolution is enabled.
        // One SOQL for all bindings across all templates in this rebuild.
        Boolean catalogEnabled = isCatalogEnabled();
        Map<Id, Form_Question_Catalog__c> catalogById = catalogEnabled
            ? fetchCatalogForBindings(wrappers)
            : new Map<Id, Form_Question_Catalog__c>();

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
                w == null ? new List<String>() : serializeQuestions(w.questions, catalogById, catalogEnabled)));
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

    /**
     * Serialize question bindings, resolving content through the catalog
     * when catalogEnabled. Bindings whose Form_Question_Catalog__c lookup
     * is null fall back to the binding's own fields — keeps mid-migration
     * orgs (catalog deployed but backfill incomplete) rendering correctly.
     */
    private static List<String> serializeQuestions(
        List<Form_Question__c> questions,
        Map<Id, Form_Question_Catalog__c> catalogById,
        Boolean catalogEnabled
    ) {
        List<String> out = new List<String>();
        if (questions == null) return out;
        for (Form_Question__c q : questions) {
            if (catalogEnabled
                && q.Form_Question_Catalog__c != null
                && catalogById.containsKey(q.Form_Question_Catalog__c)) {
                out.add(JSON.serialize(
                    resolveQuestionThroughCatalog(q, catalogById.get(q.Form_Question_Catalog__c))
                ));
            } else {
                out.add(JSON.serialize(q));
            }
        }
        return out;
    }

    /**
     * Pre-fetch every catalog entry referenced by any binding across the
     * provided wrappers. Single SOQL keyed by binding's
     * Form_Question_Catalog__c lookup. Empty when the wrappers contain no
     * questions or no bindings reference a catalog entry.
     */
    private static Map<Id, Form_Question_Catalog__c> fetchCatalogForBindings(
        Map<Id, NeuraFormLogic.FormTemplateWrapper> wrappers
    ) {
        Set<Id> catalogIds = new Set<Id>();
        for (NeuraFormLogic.FormTemplateWrapper w : wrappers.values()) {
            if (w == null || w.questions == null) continue;
            for (Form_Question__c q : w.questions) {
                if (q.Form_Question_Catalog__c != null) {
                    catalogIds.add(q.Form_Question_Catalog__c);
                }
            }
        }
        if (catalogIds.isEmpty()) return new Map<Id, Form_Question_Catalog__c>();
        return new Map<Id, Form_Question_Catalog__c>([
            SELECT Id, Active_Message__c, Calculation_Formula__c,
                   Calculation_Result_Format__c, Decimal_Places__c,
                   Default_Value_Source__c, Default_Value_Static__c,
                   Display_Rich_Text__c, Font_Color__c, Font_Size__c,
                   Inactive_Message__c, Include_Comment__c, Include_Photo__c,
                   Label_Visible__c, Layout_Item__c, Question__c,
                   Required__c, Text_Alignment__c, Type__c, Value_Set__c
            FROM Form_Question_Catalog__c
            WHERE Id IN :catalogIds
        ]);
    }

    /**
     * Placement / identity fields that always come from the binding (not
     * from the catalog). Listed explicitly here instead of being derived
     * via JSON.serialize round-trip — the round-trip approach blew async
     * heap (12MB cap) at Steritech-scale because each question allocated
     * intermediate JSON string + parsed Map. Manual construction is
     * brittle (must be updated if new placement fields are added) but
     * stays well under the heap budget. See phase-1-findings.md.
     */
    private static final List<String> BINDING_PLACEMENT_FIELDS = new List<String>{
        'Id',
        'Name',
        'Form_Template__c',
        'Form_Section__c',
        'Order__c',
        'Conditions__c'
    };

    /**
     * Merge catalog content with binding overrides into a renderer-shaped
     * Map. Output shape mirrors what JSON.serialize(Form_Question__c)
     * produces (same field keys) so the renderer's existing assembly
     * code is unchanged.
     *
     * Precedence:
     *   1. Catalog content for each field in CATALOG_RESOLVABLE_FIELDS
     *   2. Binding's Override_Question__c (if set) → Question__c
     *   3. Binding's Override_Required__c (if not 'Inherit') → Required__c
     * Placement / relationship fields (Order__c, Column__c, Form_Section__c,
     * Conditions__c, Id, Name) always come from the binding.
     */
    @TestVisible
    private static Map<String, Object> resolveQuestionThroughCatalog(
        Form_Question__c binding, Form_Question_Catalog__c catalog
    ) {
        // Build the renderer-shaped Map directly — no JSON round-trip.
        Map<String, Object> resolved = new Map<String, Object>();
        // Standard SObject attributes block (matches JSON.serialize shape).
        resolved.put('attributes', new Map<String, Object>{
            'type' => 'Form_Question__c'
        });
        // Placement / identity from the binding.
        for (String f : BINDING_PLACEMENT_FIELDS) {
            Object val = binding.get(f);
            if (val != null) resolved.put(f, val);
        }
        // Content from the catalog.
        for (String f : CATALOG_RESOLVABLE_FIELDS) {
            Object val = catalog.get(f);
            if (val != null) resolved.put(f, val);
        }
        // Per-binding overrides.
        if (binding.Override_Question__c != null) {
            resolved.put('Question__c', binding.Override_Question__c);
        }
        if (binding.Override_Required__c != null
            && binding.Override_Required__c != 'Inherit') {
            resolved.put('Required__c', binding.Override_Required__c == 'Yes');
        }
        return resolved;
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
