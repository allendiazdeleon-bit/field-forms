/**
 * Coverage for NeuraFormIR — the shape's stability matters because
 * adapters serialize against it and the importer deserializes against
 * it. A field rename or accidental member loss here would silently
 * break every adapter, so the round-trip + key presence checks guard
 * the contract.
 *
 * No DML; pure construction + JSON.serialize/deserialize.
 */
@isTest
private class NeuraFormIRTest {

    @isTest
    static void newIR_initializesEmptyCollections() {
        NeuraFormIR ir = new NeuraFormIR();
        System.assertEquals(NeuraFormIR.CURRENT_VERSION, ir.ir_version,
            'New IR should stamp the current version');
        System.assertNotEquals(null, ir.catalog_entries, 'catalog_entries should be initialized');
        System.assertNotEquals(null, ir.pages, 'pages should be initialized');
        System.assertNotEquals(null, ir.sections, 'sections should be initialized');
        System.assertNotEquals(null, ir.bindings, 'bindings should be initialized');
        System.assertEquals(0, ir.catalog_entries.size(), 'catalog_entries should be empty');
    }

    @isTest
    static void roundTrip_preservesAllFields() {
        NeuraFormIR ir = buildSampleIR();
        String jsonStr = JSON.serialize(ir);
        NeuraFormIR copy = (NeuraFormIR) JSON.deserialize(jsonStr, NeuraFormIR.class);

        System.assertEquals(ir.ir_version, copy.ir_version, 'ir_version round-trips');
        System.assertEquals(ir.template.external_ref, copy.template.external_ref);
        System.assertEquals(ir.template.name, copy.template.name);
        System.assertEquals(ir.template.indicator_type, copy.template.indicator_type);
        System.assertEquals(ir.template.selector_color, copy.template.selector_color);

        System.assertEquals(1, copy.catalog_entries.size());
        NeuraFormIR.CatalogEntry cat = copy.catalog_entries[0];
        System.assertEquals('cat-1', cat.external_ref);
        System.assertEquals('What is your name?', cat.question_text);
        System.assertEquals('Text', cat.type);
        System.assertEquals(true, cat.required);
        System.assertEquals(40, cat.length, 'length decimal survives');

        System.assertEquals(1, copy.pages.size());
        System.assertEquals('p-1', copy.pages[0].external_ref);
        System.assertEquals(1, copy.pages[0].order);

        System.assertEquals(1, copy.sections.size());
        NeuraFormIR.Section sec = copy.sections[0];
        System.assertEquals('Policy goes here', sec.policy_text, 'policy_text round-trips');
        System.assertEquals('p-1', sec.page_ref);

        System.assertEquals(1, copy.bindings.size());
        NeuraFormIR.Binding b = copy.bindings[0];
        System.assertEquals('b-1', b.external_ref);
        System.assertEquals('cat-1', b.catalog_ref);
        System.assertEquals(1, b.conditions.size());
        System.assertEquals('cat-other', b.conditions[0].resource);
        System.assertEquals('equals', b.conditions[0].operator);
        System.assertEquals('yes', b.conditions[0].value);
    }

    @isTest
    static void shapeStability_documentedKeysPresent() {
        // Documented IR keys per docs/phase-2-pillar-3-adapter-framework.md.
        // If any of these go missing, adapters break silently.
        Set<String> requiredTopLevelKeys = new Set<String>{
            'ir_version', 'template', 'catalog_entries', 'pages', 'sections', 'bindings'
        };
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(
            JSON.serialize(buildSampleIR())
        );
        for (String key : requiredTopLevelKeys) {
            System.assert(root.containsKey(key),
                'IR JSON should expose top-level key "' + key + '"');
        }
    }

    @isTest
    static void emptyIR_serializesCleanly() {
        NeuraFormIR ir = new NeuraFormIR();
        ir.template = new NeuraFormIR.Template();
        ir.template.external_ref = 'tpl-empty';
        String jsonStr = JSON.serialize(ir);
        System.assert(String.isNotBlank(jsonStr));
        NeuraFormIR copy = (NeuraFormIR) JSON.deserialize(jsonStr, NeuraFormIR.class);
        System.assertEquals('tpl-empty', copy.template.external_ref);
    }

    private static NeuraFormIR buildSampleIR() {
        NeuraFormIR ir = new NeuraFormIR();
        NeuraFormIR.Template t = new NeuraFormIR.Template();
        t.external_ref = 'tpl-1';
        t.name = 'Sample';
        t.indicator_type = 'PASS_FAIL';
        t.selector_color = 'blue';
        ir.template = t;

        NeuraFormIR.CatalogEntry cat = new NeuraFormIR.CatalogEntry();
        cat.external_ref = 'cat-1';
        cat.question_text = 'What is your name?';
        cat.type = 'Text';
        cat.required = true;
        cat.length = 40;
        cat.tags = new List<String>{ 'pii', 'identity' };
        ir.catalog_entries.add(cat);

        NeuraFormIR.IRPage p = new NeuraFormIR.IRPage();
        p.external_ref = 'p-1';
        p.title = 'Page 1';
        p.order = 1;
        ir.pages.add(p);

        NeuraFormIR.Section sec = new NeuraFormIR.Section();
        sec.external_ref = 's-1';
        sec.page_ref = 'p-1';
        sec.title = 'Section 1';
        sec.order = 1;
        sec.policy_text = 'Policy goes here';
        ir.sections.add(sec);

        NeuraFormIR.Binding b = new NeuraFormIR.Binding();
        b.external_ref = 'b-1';
        b.section_ref = 's-1';
        b.catalog_ref = 'cat-1';
        b.order = 1;
        b.column = '1';
        NeuraFormIR.Condition c = new NeuraFormIR.Condition();
        c.resource = 'cat-other';
        c.operator = 'equals';
        c.value = 'yes';
        b.conditions = new List<NeuraFormIR.Condition>{ c };
        ir.bindings.add(b);

        return ir;
    }
}
