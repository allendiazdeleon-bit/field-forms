/**
 * Adapter for the existing NeuraFormExportController export shape — a
 * JSON-serialized `List<neuraFormExportController.FormTemplateWrapper>`,
 * where each wrapper carries one template plus its pages, sections, and
 * questions as SObject dictionaries keyed by namespaced field names
 * (e.g. `Form_Template__c` rather than `template`).
 *
 * Lifts the work that today lives inline in
 * `neuraFormExportController.importTemplates` into an adapter:
 * deserialize → walk wrappers → emit IR. The IR is then handed to
 * NeuraFormImporter, which owns the DML. The existing
 * `importTemplates` entry point is reworked (in a sibling commit) to
 * delegate to this adapter so existing flows keep working.
 *
 * Catalog handling: the existing exporter shape does NOT include catalog
 * entries explicitly. Each question carries the full content (Question__c,
 * Type__c, Value_Set__c, etc.). This adapter mirrors the
 * "catalog-of-one" backfill model — emits one IR catalog_entry per
 * question, keyed by either the binding's existing
 * External_Reference__c (preferred — round-trips cleanly when an
 * import-from-export flow targets the same org) or a synthetic
 * `ff_<source-extref>` namespace so we don't collide with the
 * `cat_<bindingId>` (backfill) or `builder_<timestamp>_<rand>` (Wave
 * 35.8) namespaces.
 *
 * See docs/phase-2-pillar-3-adapter-framework.md.
 */
public with sharing class NeuraFormFieldFormsAdapter implements NeuraFormSourceAdapter {

    /**
     * Synthetic catalog external_ref prefix. Distinct from
     * `cat_<bindingId>` (Pillar 2 backfill batch) and
     * `builder_<timestamp>_<rand>` (Wave 35.8 builder auto-create) so
     * adapter-imported catalog entries are identifiable in the org.
     */
    private static final String CATALOG_REF_PREFIX = 'ff_';

    public String label() {
        return 'Field Forms (native export)';
    }

    /**
     * Confidence heuristic: the export shape is a JSON array of objects
     * with `template`, `pages`, `sections`, `questions` keys. Cheap
     * string match before attempting a full parse — keeps the auto-pick
     * step fast when many adapters are registered.
     */
    public Decimal canHandle(String source) {
        if (String.isBlank(source)) return 0;
        String head = source.length() > 4000 ? source.substring(0, 4000) : source;
        Boolean looksLikeArray = head.trim().startsWith('[');
        Boolean hasTemplate = head.contains('"template"');
        Boolean hasPages = head.contains('"pages"');
        Boolean hasQuestions = head.contains('"questions"');
        if (looksLikeArray && hasTemplate && hasPages && hasQuestions) return 0.9;
        if (looksLikeArray && hasTemplate) return 0.5;
        return 0;
    }

    /**
     * Parse the source JSON and return a populated IR.
     *
     * The export shape stores Form_Template__c / Form_Page__c etc. via
     * the namespaced field map. We deserialize each level into an
     * untyped Map so we can read both namespaced and bare field keys
     * (managed vs unmanaged orgs use different prefixes). Adapters that
     * own their own JSON shape (Steritech) don't need this two-step.
     */
    public NeuraFormIR parse(String source, Map<String, String> options) {
        if (String.isBlank(source)) {
            throw new NeuraFormImporter.AdapterException('Empty source payload.');
        }

        List<Object> wrappers;
        try {
            wrappers = (List<Object>) JSON.deserializeUntyped(source);
        } catch (Exception e) {
            throw new NeuraFormImporter.AdapterException(
                'Could not parse Field Forms JSON: ' + e.getMessage()
            );
        }
        if (wrappers == null || wrappers.isEmpty()) {
            throw new NeuraFormImporter.AdapterException('No templates found in payload.');
        }

        // v1: one template per IR. The existing exporter packs N
        // templates into a single file; the importer pipeline handles
        // one at a time. Caller iterates the wrapper list and invokes
        // the adapter per element.
        Object first = wrappers[0];
        if (!(first instanceof Map<String, Object>)) {
            throw new NeuraFormImporter.AdapterException(
                'Expected a JSON array of template wrappers.'
            );
        }
        return parseWrapper((Map<String, Object>) first);
    }

    /**
     * Public test seam: convert one wrapper Map into IR. Surfaces so the
     * caller (e.g. `importTemplates` shim) can iterate a multi-template
     * payload and call this per wrapper without re-parsing the source
     * string each time.
     */
    public NeuraFormIR parseWrapper(Map<String, Object> wrapper) {
        NeuraFormIR ir = new NeuraFormIR();
        String ns = NeuraFormUtils.getNamespacePrefix();

        // ---- template ----
        Map<String, Object> tplMap = asMap(wrapper.get('template'));
        if (tplMap == null) {
            throw new NeuraFormImporter.AdapterException(
                'Wrapper is missing required `template` block.'
            );
        }
        NeuraFormIR.Template tpl = new NeuraFormIR.Template();
        tpl.external_ref = readStringField(tplMap, ns, 'External_Reference__c');
        tpl.name = readStringField(tplMap, '', 'Name');
        if (String.isBlank(tpl.name)) tpl.name = readStringField(tplMap, ns, 'Name');
        tpl.indicator_type = readStringField(tplMap, ns, 'Indicator_Type__c');
        tpl.selector_color = readStringField(tplMap, ns, 'Selector_Color__c');
        if (String.isBlank(tpl.external_ref)) {
            throw new NeuraFormImporter.AdapterException(
                'Template is missing External_Reference__c — required for upsert.'
            );
        }
        ir.template = tpl;

        // ---- pages ----
        for (Object p : asList(wrapper.get('pages'))) {
            Map<String, Object> pm = asMap(p);
            if (pm == null) continue;
            NeuraFormIR.IRPage page = new NeuraFormIR.IRPage();
            page.external_ref = readStringField(pm, ns, 'External_Reference__c');
            page.title = readStringField(pm, ns, 'Title__c');
            page.order = readDecimalField(pm, ns, 'Order__c');
            if (String.isBlank(page.external_ref)) continue;
            ir.pages.add(page);
        }

        // ---- sections ----
        for (Object s : asList(wrapper.get('sections'))) {
            Map<String, Object> sm = asMap(s);
            if (sm == null) continue;
            NeuraFormIR.Section section = new NeuraFormIR.Section();
            section.external_ref = readStringField(sm, ns, 'External_Reference__c');
            section.title = readStringField(sm, ns, 'Title__c');
            section.order = readDecimalField(sm, ns, 'Order__c');
            section.columns = readStringField(sm, ns, 'Columns__c');
            // Section's page reference in the export shape is the Form_Page__c
            // FK populated with the page's External_Reference__c string
            // (export controller does this via addExternalIdValues).
            section.page_ref = readStringField(sm, ns, 'Form_Page__c');
            section.policy_text = readStringField(sm, ns, 'Policy_Text__c');
            if (String.isBlank(section.external_ref)) continue;
            ir.sections.add(section);
        }

        // ---- questions: emit one catalog entry + one binding per row ----
        for (Object q : asList(wrapper.get('questions'))) {
            Map<String, Object> qm = asMap(q);
            if (qm == null) continue;
            String questionExtRef = readStringField(qm, ns, 'External_Reference__c');
            if (String.isBlank(questionExtRef)) continue;

            // Catalog entry: dedupe by question External_Reference__c
            // namespaced with `ff_` so we don't collide with backfill or
            // builder-namespaced refs in the same org. The same
            // questionExtRef on a re-import maps to the same catalog
            // entry — round-trips cleanly.
            String catalogRef = CATALOG_REF_PREFIX + questionExtRef;

            NeuraFormIR.CatalogEntry cat = new NeuraFormIR.CatalogEntry();
            cat.external_ref = catalogRef;
            cat.question_text = readStringField(qm, ns, 'Question__c');
            cat.type = readStringField(qm, ns, 'Type__c');
            cat.value_set = readStringField(qm, ns, 'Value_Set__c');
            cat.required = readBooleanField(qm, ns, 'Required__c');
            cat.length = readDecimalField(qm, ns, 'Length__c');
            cat.min = readDecimalField(qm, ns, 'Min__c');
            cat.max = readDecimalField(qm, ns, 'Max__c');
            cat.decimal_places = readDecimalField(qm, ns, 'Decimal_Places__c');
            cat.slider_size = readStringField(qm, ns, 'Slider_Size__c');
            cat.slider_step = readDecimalField(qm, ns, 'Slider_Step__c');
            cat.default_value_source = readStringField(qm, ns, 'Default_Value_Source__c');
            cat.default_value_static = readStringField(qm, ns, 'Default_Value_Static__c');
            cat.calculation_formula = readStringField(qm, ns, 'Calculation_Formula__c');
            cat.calculation_result_format = readStringField(qm, ns, 'Calculation_Result_Format__c');
            cat.date_time_save_format = readStringField(qm, ns, 'Date_Time_Save_Format__c');
            cat.active_message = readStringField(qm, ns, 'Active_Message__c');
            cat.inactive_message = readStringField(qm, ns, 'Inactive_Message__c');
            cat.display_rich_text = readStringField(qm, ns, 'Display_Rich_Text__c');
            cat.include_comment = readBooleanField(qm, ns, 'Include_Comment__c');
            cat.include_photo = readBooleanField(qm, ns, 'Include_Photo__c');
            cat.label_visible = readBooleanField(qm, ns, 'Label_Visible__c');
            cat.text_alignment = readStringField(qm, ns, 'Text_Alignment__c');
            cat.font_size = readStringField(qm, ns, 'Font_Size__c');
            cat.font_color = readStringField(qm, ns, 'Font_Color__c');
            cat.lookup_child_object = readStringField(qm, ns, 'Lookup_Child_Object__c');
            cat.lookup_display_field = readStringField(qm, ns, 'Lookup_Display_Field__c');
            cat.lookup_related_list = readStringField(qm, ns, 'Lookup_Related_List__c');
            ir.catalog_entries.add(cat);

            // Binding row
            NeuraFormIR.Binding bind = new NeuraFormIR.Binding();
            bind.external_ref = questionExtRef;
            bind.section_ref = readStringField(qm, ns, 'Form_Section__c');
            bind.catalog_ref = catalogRef;
            bind.order = readDecimalField(qm, ns, 'Order__c');
            bind.column = readStringField(qm, ns, 'Column__c');
            bind.conditions = parseConditions(readStringField(qm, ns, 'Conditions__c'));
            ir.bindings.add(bind);
        }

        return ir;
    }

    public Decimal canHandleStatic(String source) {
        // Some test runners can't invoke instance methods on adapter
        // factories. Static helper mirrors canHandle() so smoke tests
        // can verify the heuristic without instantiating.
        return new NeuraFormFieldFormsAdapter().canHandle(source);
    }

    // -----------------------------------------------------------------
    // Conditions parsing (existing exporter shape)
    // -----------------------------------------------------------------

    /**
     * Existing exporter stores conditions as
     *   {"conditions":[{"resource":"<questionRef>","operator":"equals","value":"x"}, ...]}
     * Translate that to IR Condition objects with the catalog ref
     * (synthetic `ff_<questionRef>`) as the resource, so the importer's
     * second pass can resolve them to the new Form_Question__c Ids.
     */
    private static List<NeuraFormIR.Condition> parseConditions(String raw) {
        List<NeuraFormIR.Condition> out = new List<NeuraFormIR.Condition>();
        if (String.isBlank(raw)) return out;
        Object parsed;
        try { parsed = JSON.deserializeUntyped(raw); } catch (Exception e) { return out; }
        if (!(parsed instanceof Map<String, Object>)) return out;
        List<Object> items = (List<Object>) ((Map<String, Object>) parsed).get('conditions');
        if (items == null) return out;
        for (Object item : items) {
            if (!(item instanceof Map<String, Object>)) continue;
            Map<String, Object> m = (Map<String, Object>) item;
            NeuraFormIR.Condition c = new NeuraFormIR.Condition();
            Object res = m.get('resource');
            if (res instanceof String && String.isNotBlank((String) res)) {
                // The export carries the question's External_Reference__c
                // string. Translate to the catalog ref the binding uses
                // (CATALOG_REF_PREFIX + ref). Importer resolves the
                // catalog ref → binding Id during the second pass.
                c.resource = CATALOG_REF_PREFIX + (String) res;
            }
            Object op = m.get('operator');
            if (op instanceof String) c.operator = (String) op;
            Object val = m.get('value');
            if (val != null) c.value = String.valueOf(val);
            out.add(c);
        }
        return out;
    }

    // -----------------------------------------------------------------
    // Field accessors (namespaced + bare fallback)
    // -----------------------------------------------------------------

    /**
     * Read a field from the SObject Map, trying the namespaced key
     * first (`ns + name`) and falling back to the bare name. Handles
     * both managed and unmanaged package exports without forcing the
     * adapter to know which packaging mode produced the file.
     */
    private static String readStringField(Map<String, Object> m, String ns, String name) {
        if (m == null) return null;
        Object v = m.get(ns + name);
        if (v == null) v = m.get(name);
        return (v == null) ? null : String.valueOf(v);
    }

    private static Decimal readDecimalField(Map<String, Object> m, String ns, String name) {
        if (m == null) return null;
        Object v = m.get(ns + name);
        if (v == null) v = m.get(name);
        if (v == null) return null;
        if (v instanceof Decimal) return (Decimal) v;
        if (v instanceof Integer) return Decimal.valueOf((Integer) v);
        if (v instanceof Long) return Decimal.valueOf((Long) v);
        if (v instanceof Double) return Decimal.valueOf(String.valueOf((Double) v));
        if (v instanceof String) {
            try { return Decimal.valueOf((String) v); } catch (Exception e) { return null; }
        }
        return null;
    }

    private static Boolean readBooleanField(Map<String, Object> m, String ns, String name) {
        if (m == null) return null;
        Object v = m.get(ns + name);
        if (v == null) v = m.get(name);
        if (v == null) return null;
        if (v instanceof Boolean) return (Boolean) v;
        if (v instanceof String) return ((String) v).equalsIgnoreCase('true');
        return null;
    }

    private static Map<String, Object> asMap(Object o) {
        return (o instanceof Map<String, Object>) ? (Map<String, Object>) o : null;
    }

    private static List<Object> asList(Object o) {
        return (o instanceof List<Object>) ? (List<Object>) o : new List<Object>();
    }
}
