/**
 * Shared importer: turns a NeuraFormIR into upserted Form_Template__c /
 * Form_Page__c / Form_Section__c / Form_Question_Catalog__c /
 * Form_Question__c rows. One code path for every adapter — new customer
 * formats just produce IR, never touch this class.
 *
 * Upsert order (each step external-ref keyed for idempotency):
 *   1. Form_Template__c     (by External_Reference__c)
 *   2. Form_Question_Catalog__c entries (by External_Reference__c)
 *   3. Form_Page__c         (by External_Reference__c, parented to template)
 *   4. Form_Section__c      (by External_Reference__c, parented to page)
 *   5. Form_Question__c     (by External_Reference__c, parented to section,
 *                            linked to a catalog entry)
 *   6. Second pass: rewrite Conditions__c JSON from catalog_ref strings
 *      to the new question Ids, then update only the rows that changed.
 *
 * Snapshot rebuild is not triggered by this class directly — the
 * existing trigger pipeline on Form_Page/Section/Question will pick it
 * up via the standard NeuraFormSnapshotQueueable. Callers that want a
 * synchronous rebuild (e.g. the Aura entry point that needs the new
 * template to render immediately) invoke NeuraFormLogic.processTemplates
 * themselves after this returns — keeps the importer transport-agnostic.
 *
 * The entire import is wrapped in a single Savepoint by callers; this
 * class throws on any DML failure so the caller can rollback cleanly.
 *
 * Heap note: we build SObject collections directly (no chained
 * Map<String, Object> → serialize → deserialize) because that pattern
 * blew async heap in Phase 1 at Steritech scale. See
 * docs/phase-1-findings.md.
 *
 * See docs/phase-2-pillar-3-adapter-framework.md.
 */
public with sharing class NeuraFormImporter {

    /**
     * Thrown by adapters when a source can't be parsed. Distinct from
     * runtime errors during the importer's DML pass so the import UI can
     * surface "your file looks wrong" vs. "Salesforce rejected the
     * write".
     */
    public class AdapterException extends Exception {}

    /**
     * Result of running an import. Counts are tallied per-record-type so
     * a dry-run preview UI can show "X templates new, Y catalog entries
     * updated" without re-querying. Warnings carry non-fatal issues
     * (e.g. condition references that didn't resolve in this payload).
     */
    public class ImportResult {
        @AuraEnabled public Id templateId;
        @AuraEnabled public String templateExternalRef;
        @AuraEnabled public Integer templatesCreated = 0;
        @AuraEnabled public Integer templatesUpdated = 0;
        @AuraEnabled public Integer catalogEntriesCreated = 0;
        @AuraEnabled public Integer catalogEntriesUpdated = 0;
        @AuraEnabled public Integer pagesCreated = 0;
        @AuraEnabled public Integer pagesUpdated = 0;
        @AuraEnabled public Integer sectionsCreated = 0;
        @AuraEnabled public Integer sectionsUpdated = 0;
        @AuraEnabled public Integer bindingsCreated = 0;
        @AuraEnabled public Integer bindingsUpdated = 0;
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    /**
     * Single entry point. Caller supplies a fully-populated IR; importer
     * runs upserts and returns counts + warnings. Throws on DML failure
     * (caller wraps in a Savepoint so a mid-pipeline failure rolls back
     * everything).
     *
     * Method named `runImport` rather than `import` because `import` is
     * a reserved keyword in Apex. The design doc shows `import` for
     * readability; the actual identifier is `runImport`.
     */
    public static ImportResult runImport(NeuraFormIR ir) {
        if (ir == null) {
            throw new AdapterException('Import called with null IR.');
        }
        if (ir.template == null) {
            throw new AdapterException('IR is missing required `template` block.');
        }
        if (String.isBlank(ir.template.external_ref)) {
            throw new AdapterException('IR template is missing required external_ref.');
        }

        ImportResult result = new ImportResult();

        // 1. Template ---------------------------------------------------
        Form_Template__c template = upsertTemplate(ir.template, result);
        result.templateId = template.Id;
        result.templateExternalRef = ir.template.external_ref;

        // 2. Catalog entries -------------------------------------------
        Map<String, Id> catalogIdByRef = upsertCatalogEntries(
            ir.catalog_entries, result
        );

        // 3. Pages ------------------------------------------------------
        Map<String, Id> pageIdByRef = upsertPages(
            ir.pages, template.Id, result
        );

        // 4. Sections ---------------------------------------------------
        Map<String, Id> sectionIdByRef = upsertSections(
            ir.sections, template.Id, pageIdByRef, result
        );

        // 5. Bindings ---------------------------------------------------
        Map<String, Id> bindingIdByRef = upsertBindings(
            ir.bindings,
            template.Id,
            sectionIdByRef,
            pageIdByRef,
            catalogIdByRef,
            result
        );

        // 6. Second pass: rewrite condition `resource` references from
        // catalog_ref strings to the new Form_Question__c Ids. Bindings
        // whose conditions didn't reference any catalog ref skip the
        // update DML entirely.
        rewriteConditionReferences(
            ir.bindings,
            bindingIdByRef,
            catalogIdByRef,
            result
        );

        return result;
    }

    // -----------------------------------------------------------------
    // Template
    // -----------------------------------------------------------------

    private static Form_Template__c upsertTemplate(
        NeuraFormIR.Template ir, ImportResult result
    ) {
        Form_Template__c t = new Form_Template__c();
        // Look up existing by external_ref so the upsert reports created
        // vs. updated. Database.upsert(records, externalIdField) returns
        // UpsertResult[] with isCreated, but a single-row upsert through
        // the SObjectField overload is the cleanest signal.
        Form_Template__c existing = queryTemplateByRef(ir.external_ref);
        if (existing != null) {
            t.Id = existing.Id;
            result.templatesUpdated++;
        } else {
            result.templatesCreated++;
        }
        t.External_Reference__c = ir.external_ref;
        if (String.isNotBlank(ir.name)) t.Name = ir.name;
        if (String.isNotBlank(ir.indicator_type)) t.Indicator_Type__c = ir.indicator_type;
        if (String.isNotBlank(ir.selector_color)) t.Selector_Color__c = ir.selector_color;
        upsert t;
        return t;
    }

    private static Form_Template__c queryTemplateByRef(String ref) {
        if (String.isBlank(ref)) return null;
        List<Form_Template__c> rows = [
            SELECT Id, External_Reference__c, Name
            FROM Form_Template__c
            WHERE External_Reference__c = :ref
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    // -----------------------------------------------------------------
    // Catalog entries
    // -----------------------------------------------------------------

    /**
     * Upsert every catalog entry in the IR, keyed by external_ref.
     * Returns a map of external_ref → Id for the bindings step to use.
     * Empty catalog_entries list is OK — adapters that don't produce
     * shared questions just emit zero entries here and place the content
     * directly on the binding's Override fields.
     */
    private static Map<String, Id> upsertCatalogEntries(
        List<NeuraFormIR.CatalogEntry> entries, ImportResult result
    ) {
        Map<String, Id> out = new Map<String, Id>();
        if (entries == null || entries.isEmpty()) return out;

        // Collect refs and bulk-query existing catalog rows to tally
        // created vs. updated. One SOQL regardless of catalog size.
        Set<String> refs = new Set<String>();
        for (NeuraFormIR.CatalogEntry e : entries) {
            if (String.isNotBlank(e.external_ref)) refs.add(e.external_ref);
        }
        Map<String, Id> existingByRef = new Map<String, Id>();
        if (!refs.isEmpty()) {
            for (Form_Question_Catalog__c row : [
                SELECT Id, External_Reference__c
                FROM Form_Question_Catalog__c
                WHERE External_Reference__c IN :refs
            ]) {
                existingByRef.put(row.External_Reference__c, row.Id);
            }
        }

        List<Form_Question_Catalog__c> toUpsert = new List<Form_Question_Catalog__c>();
        for (NeuraFormIR.CatalogEntry e : entries) {
            if (String.isBlank(e.external_ref)) {
                result.warnings.add(
                    'Catalog entry skipped: missing external_ref (question_text="' +
                    truncateForWarning(e.question_text) + '").'
                );
                continue;
            }
            Form_Question_Catalog__c row = new Form_Question_Catalog__c();
            if (existingByRef.containsKey(e.external_ref)) {
                row.Id = existingByRef.get(e.external_ref);
                result.catalogEntriesUpdated++;
            } else {
                result.catalogEntriesCreated++;
            }
            row.External_Reference__c = e.external_ref;
            applyCatalogFields(row, e);
            toUpsert.add(row);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
            for (Form_Question_Catalog__c row : toUpsert) {
                out.put(row.External_Reference__c, row.Id);
            }
        }
        return out;
    }

    /**
     * Copy IR catalog fields onto the SObject. Each field is null-checked
     * so the importer never overwrites an existing value with null on
     * re-import — matters when an admin has edited the catalog entry
     * after the initial import and the source format didn't carry the
     * edited field. (For the strict overwrite semantics documented in
     * the design doc, set fields explicitly to null in the IR.)
     */
    private static void applyCatalogFields(
        Form_Question_Catalog__c row, NeuraFormIR.CatalogEntry e
    ) {
        if (String.isNotBlank(e.question_text)) row.Question__c = e.question_text;
        if (String.isNotBlank(e.type)) row.Type__c = e.type;
        if (String.isNotBlank(e.value_set)) row.Value_Set__c = e.value_set;
        if (e.required != null) row.Required__c = e.required;
        if (e.length != null) row.Length__c = e.length;
        if (e.min != null) row.Min__c = e.min;
        if (e.max != null) row.Max__c = e.max;
        if (e.decimal_places != null) row.Decimal_Places__c = e.decimal_places;
        if (String.isNotBlank(e.slider_size)) row.Slider_Size__c = e.slider_size;
        if (e.slider_step != null) row.Slider_Step__c = e.slider_step;
        if (String.isNotBlank(e.default_value_source)) row.Default_Value_Source__c = e.default_value_source;
        if (String.isNotBlank(e.default_value_static)) row.Default_Value_Static__c = e.default_value_static;
        if (String.isNotBlank(e.calculation_formula)) row.Calculation_Formula__c = e.calculation_formula;
        if (String.isNotBlank(e.calculation_result_format)) row.Calculation_Result_Format__c = e.calculation_result_format;
        if (String.isNotBlank(e.date_time_save_format)) row.Date_Time_Save_Format__c = e.date_time_save_format;
        if (String.isNotBlank(e.active_message)) row.Active_Message__c = e.active_message;
        if (String.isNotBlank(e.inactive_message)) row.Inactive_Message__c = e.inactive_message;
        if (String.isNotBlank(e.display_rich_text)) row.Display_Rich_Text__c = e.display_rich_text;
        if (e.include_comment != null) row.Include_Comment__c = e.include_comment;
        if (e.include_photo != null) row.Include_Photo__c = e.include_photo;
        if (e.label_visible != null) row.Label_Visible__c = e.label_visible;
        if (String.isNotBlank(e.text_alignment)) row.Text_Alignment__c = e.text_alignment;
        if (String.isNotBlank(e.font_size)) row.Font_Size__c = e.font_size;
        if (String.isNotBlank(e.font_color)) row.Font_Color__c = e.font_color;
        if (String.isNotBlank(e.lookup_child_object)) row.Lookup_Child_Object__c = e.lookup_child_object;
        if (String.isNotBlank(e.lookup_display_field)) row.Lookup_Display_Field__c = e.lookup_display_field;
        if (String.isNotBlank(e.lookup_related_list)) row.Lookup_Related_List__c = e.lookup_related_list;
        if (e.tags != null && !e.tags.isEmpty()) {
            row.Tags__c = String.join(e.tags, ',');
        }
    }

    // -----------------------------------------------------------------
    // Pages
    // -----------------------------------------------------------------

    private static Map<String, Id> upsertPages(
        List<NeuraFormIR.IRPage> pages, Id templateId, ImportResult result
    ) {
        Map<String, Id> out = new Map<String, Id>();
        if (pages == null || pages.isEmpty()) return out;

        Set<String> refs = new Set<String>();
        for (NeuraFormIR.IRPage p : pages) {
            if (String.isNotBlank(p.external_ref)) refs.add(p.external_ref);
        }
        Map<String, Id> existingByRef = new Map<String, Id>();
        if (!refs.isEmpty()) {
            for (Form_Page__c row : [
                SELECT Id, External_Reference__c
                FROM Form_Page__c
                WHERE External_Reference__c IN :refs
            ]) {
                existingByRef.put(row.External_Reference__c, row.Id);
            }
        }

        List<Form_Page__c> toUpsert = new List<Form_Page__c>();
        for (NeuraFormIR.IRPage p : pages) {
            if (String.isBlank(p.external_ref)) {
                result.warnings.add('Page skipped: missing external_ref.');
                continue;
            }
            Form_Page__c row = new Form_Page__c();
            Boolean isNew = !existingByRef.containsKey(p.external_ref);
            if (!isNew) {
                row.Id = existingByRef.get(p.external_ref);
                result.pagesUpdated++;
            } else {
                result.pagesCreated++;
            }
            row.External_Reference__c = p.external_ref;
            // Master-detail parents are immutable post-insert; only assign
            // on net-new records or Apex throws "Field is not writeable".
            if (isNew) row.Form_Template__c = templateId;
            if (String.isNotBlank(p.title)) row.Title__c = p.title;
            if (p.order != null) row.Order__c = p.order;
            toUpsert.add(row);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
            for (Form_Page__c row : toUpsert) {
                out.put(row.External_Reference__c, row.Id);
            }
        }
        return out;
    }

    // -----------------------------------------------------------------
    // Sections
    // -----------------------------------------------------------------

    private static Map<String, Id> upsertSections(
        List<NeuraFormIR.Section> sections,
        Id templateId,
        Map<String, Id> pageIdByRef,
        ImportResult result
    ) {
        Map<String, Id> out = new Map<String, Id>();
        if (sections == null || sections.isEmpty()) return out;

        Set<String> refs = new Set<String>();
        for (NeuraFormIR.Section s : sections) {
            if (String.isNotBlank(s.external_ref)) refs.add(s.external_ref);
        }
        Map<String, Id> existingByRef = new Map<String, Id>();
        if (!refs.isEmpty()) {
            for (Form_Section__c row : [
                SELECT Id, External_Reference__c
                FROM Form_Section__c
                WHERE External_Reference__c IN :refs
            ]) {
                existingByRef.put(row.External_Reference__c, row.Id);
            }
        }

        List<Form_Section__c> toUpsert = new List<Form_Section__c>();
        for (NeuraFormIR.Section s : sections) {
            if (String.isBlank(s.external_ref)) {
                result.warnings.add('Section skipped: missing external_ref.');
                continue;
            }
            Form_Section__c row = new Form_Section__c();
            Boolean isNew = !existingByRef.containsKey(s.external_ref);
            if (!isNew) {
                row.Id = existingByRef.get(s.external_ref);
                result.sectionsUpdated++;
            } else {
                result.sectionsCreated++;
            }
            row.External_Reference__c = s.external_ref;
            // Master-detail parent immutable post-insert.
            if (isNew) row.Form_Template__c = templateId;
            if (String.isNotBlank(s.page_ref)) {
                Id pageId = pageIdByRef.get(s.page_ref);
                if (pageId == null) {
                    result.warnings.add(
                        'Section "' + s.external_ref + '" references unknown page "' +
                        s.page_ref + '"; left unlinked.'
                    );
                } else {
                    row.Form_Page__c = pageId;
                }
            }
            if (String.isNotBlank(s.title)) row.Title__c = s.title;
            if (s.order != null) row.Order__c = s.order;
            if (String.isNotBlank(s.policy_text)) row.Policy_Text__c = s.policy_text;
            if (String.isNotBlank(s.columns)) row.Columns__c = s.columns;
            toUpsert.add(row);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
            for (Form_Section__c row : toUpsert) {
                out.put(row.External_Reference__c, row.Id);
            }
        }
        return out;
    }

    // -----------------------------------------------------------------
    // Bindings (Form_Question__c placements)
    // -----------------------------------------------------------------

    private static Map<String, Id> upsertBindings(
        List<NeuraFormIR.Binding> bindings,
        Id templateId,
        Map<String, Id> sectionIdByRef,
        Map<String, Id> pageIdByRef,
        Map<String, Id> catalogIdByRef,
        ImportResult result
    ) {
        Map<String, Id> out = new Map<String, Id>();
        if (bindings == null || bindings.isEmpty()) return out;

        Set<String> refs = new Set<String>();
        for (NeuraFormIR.Binding b : bindings) {
            if (String.isNotBlank(b.external_ref)) refs.add(b.external_ref);
        }
        Map<String, Id> existingByRef = new Map<String, Id>();
        if (!refs.isEmpty()) {
            for (Form_Question__c row : [
                SELECT Id, External_Reference__c
                FROM Form_Question__c
                WHERE External_Reference__c IN :refs
            ]) {
                existingByRef.put(row.External_Reference__c, row.Id);
            }
        }

        List<Form_Question__c> toUpsert = new List<Form_Question__c>();
        for (NeuraFormIR.Binding b : bindings) {
            if (String.isBlank(b.external_ref)) {
                result.warnings.add('Binding skipped: missing external_ref.');
                continue;
            }
            Form_Question__c row = new Form_Question__c();
            Boolean isNew = !existingByRef.containsKey(b.external_ref);
            if (!isNew) {
                row.Id = existingByRef.get(b.external_ref);
                result.bindingsUpdated++;
            } else {
                result.bindingsCreated++;
            }
            row.External_Reference__c = b.external_ref;
            // Master-detail parent immutable post-insert.
            if (isNew) row.Form_Template__c = templateId;

            if (String.isNotBlank(b.section_ref)) {
                Id sectionId = sectionIdByRef.get(b.section_ref);
                if (sectionId == null) {
                    result.warnings.add(
                        'Binding "' + b.external_ref + '" references unknown section "' +
                        b.section_ref + '"; left unlinked.'
                    );
                } else {
                    row.Form_Section__c = sectionId;
                }
            }
            if (String.isNotBlank(b.catalog_ref)) {
                Id catId = catalogIdByRef.get(b.catalog_ref);
                if (catId == null) {
                    result.warnings.add(
                        'Binding "' + b.external_ref + '" references unknown catalog entry "' +
                        b.catalog_ref + '"; left unlinked.'
                    );
                } else {
                    row.Form_Question_Catalog__c = catId;
                }
            }
            if (b.order != null) row.Order__c = b.order;
            if (String.isNotBlank(b.column)) row.Column__c = b.column;
            if (String.isNotBlank(b.override_question)) {
                row.Override_Question__c = b.override_question;
            }
            if (String.isNotBlank(b.override_required)) {
                row.Override_Required__c = b.override_required;
            }
            // Conditions__c is filled in during the second pass once
            // every binding Id is known. Set to a stub here so the row
            // is valid; the rewrite step overwrites if any condition
            // resolves.
            row.Conditions__c = serializeConditionsWithRefs(b.conditions);
            toUpsert.add(row);
        }

        if (!toUpsert.isEmpty()) {
            upsert toUpsert;
            for (Form_Question__c row : toUpsert) {
                out.put(row.External_Reference__c, row.Id);
            }
        }
        return out;
    }

    /**
     * Serialize IR conditions into the renderer's expected
     * Conditions__c shape, keyed by catalog_ref strings. The second
     * pass replaces those strings with the resolved Form_Question__c
     * Ids once all bindings are upserted.
     *
     * Output shape mirrors what NeuraFormExportController.modifyCriteria
     * already produces:
     *   { "conditions": [ {"resource":"<id-or-ref>", "operator":"equals", "value":"x"}, ... ] }
     */
    private static String serializeConditionsWithRefs(
        List<NeuraFormIR.Condition> conditions
    ) {
        if (conditions == null || conditions.isEmpty()) return null;
        List<Object> items = new List<Object>();
        for (NeuraFormIR.Condition c : conditions) {
            Map<String, Object> m = new Map<String, Object>();
            if (String.isNotBlank(c.resource)) m.put('resource', c.resource);
            if (String.isNotBlank(c.operator)) m.put('operator', c.operator);
            if (c.value != null) m.put('value', c.value);
            items.add(m);
        }
        return JSON.serialize(new Map<String, Object>{ 'conditions' => items });
    }

    // -----------------------------------------------------------------
    // Condition rewrite (second pass)
    // -----------------------------------------------------------------

    /**
     * After all bindings are upserted, resolve every condition's
     * `resource` from a catalog_ref string to the actual
     * Form_Question__c Id that references that catalog entry inside
     * this template. Only bindings whose conditions actually contained
     * a recognized catalog_ref get re-DMLed.
     *
     * Resolution path:
     *   condition.resource (catalog_ref) → catalogIdByRef → catalog Id
     *   → find the binding in this import that points at that catalog
     *     Id → use that binding's Id as the resolved value.
     *
     * Most adapters point conditions at the catalog ref directly; the
     * Steritech adapter's flatten step produces one binding per
     * placement so each catalog has one binding per section, and the
     * conditions on sibling bindings within the same section all
     * resolve to that one binding. Adapters that need cross-section
     * conditions (rare) can extend this by adding section context to
     * Condition.
     */
    private static void rewriteConditionReferences(
        List<NeuraFormIR.Binding> bindings,
        Map<String, Id> bindingIdByRef,
        Map<String, Id> catalogIdByRef,
        ImportResult result
    ) {
        if (bindings == null || bindings.isEmpty()) return;

        // Build a quick lookup: catalog_ref → binding_external_ref so a
        // condition pointing at catalog_ref resolves to the binding's
        // new Id. When multiple bindings reference the same catalog
        // entry, the first one wins; adapters that need finer control
        // should include the binding's external_ref directly in the
        // condition rather than the catalog ref.
        Map<String, String> catalogToBindingRef = new Map<String, String>();
        for (NeuraFormIR.Binding b : bindings) {
            if (String.isBlank(b.catalog_ref) || String.isBlank(b.external_ref)) continue;
            if (!catalogToBindingRef.containsKey(b.catalog_ref)) {
                catalogToBindingRef.put(b.catalog_ref, b.external_ref);
            }
        }

        List<Form_Question__c> toUpdate = new List<Form_Question__c>();
        for (NeuraFormIR.Binding b : bindings) {
            if (b.conditions == null || b.conditions.isEmpty()) continue;
            Id bindingId = bindingIdByRef.get(b.external_ref);
            if (bindingId == null) continue;

            List<Object> resolvedItems = new List<Object>();
            Boolean anyResolved = false;
            for (NeuraFormIR.Condition c : b.conditions) {
                Map<String, Object> m = new Map<String, Object>();
                if (String.isNotBlank(c.operator)) m.put('operator', c.operator);
                if (c.value != null) m.put('value', c.value);

                String resourceRef = c.resource;
                if (String.isBlank(resourceRef)) {
                    resolvedItems.add(m);
                    continue;
                }
                // Try resolving as a catalog_ref first; if not found, try
                // as a binding external_ref directly. Adapters can use
                // either depending on which is more natural.
                String targetBindingRef = catalogToBindingRef.get(resourceRef);
                Id resolvedId = (targetBindingRef != null)
                    ? bindingIdByRef.get(targetBindingRef)
                    : bindingIdByRef.get(resourceRef);

                if (resolvedId != null) {
                    m.put('resource', resolvedId);
                    anyResolved = true;
                } else {
                    // Leave the raw ref in place — better than null so
                    // the renderer can at least flag a broken condition
                    // rather than silently evaluate "everything passes".
                    m.put('resource', resourceRef);
                    result.warnings.add(
                        'Binding "' + b.external_ref + '" has a condition referencing "' +
                        resourceRef + '" which did not resolve to any binding in this import.'
                    );
                }
                resolvedItems.add(m);
            }

            if (anyResolved) {
                Form_Question__c upd = new Form_Question__c(Id = bindingId);
                upd.Conditions__c = JSON.serialize(
                    new Map<String, Object>{ 'conditions' => resolvedItems }
                );
                toUpdate.add(upd);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }

    // -----------------------------------------------------------------
    // Small helpers
    // -----------------------------------------------------------------

    private static String truncateForWarning(String s) {
        if (s == null) return '';
        return s.length() > 40 ? s.substring(0, 40) + '...' : s;
    }
}
