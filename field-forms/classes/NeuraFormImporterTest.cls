/**
 * Coverage for NeuraFormImporter.runImport. Verifies the upsert chain,
 * idempotent re-import, condition reference resolution, and warning
 * surfaces.
 *
 * All tests run with Disable_Form_Template_JSON_Trigger__c = true so
 * the snapshot queueable doesn't interfere with the import's DML.
 */
@isTest
private class NeuraFormImporterTest {

    @testSetup
    static void suppressTrigger() {
        FieldForms_Configuration__c cfg = new FieldForms_Configuration__c();
        cfg.Disable_Form_Template_JSON_Trigger__c = true;
        insert cfg;
    }

    @isTest
    static void happyPath_createsAllLevels() {
        NeuraFormIR ir = buildSimpleIR('TPL-A');

        Test.startTest();
        NeuraFormImporter.ImportResult r = NeuraFormImporter.runImport(ir);
        Test.stopTest();

        System.assertEquals(1, r.templatesCreated, 'one template created');
        System.assertEquals(0, r.templatesUpdated);
        System.assertEquals(1, r.catalogEntriesCreated);
        System.assertEquals(1, r.pagesCreated);
        System.assertEquals(1, r.sectionsCreated);
        System.assertEquals(1, r.bindingsCreated);
        System.assertNotEquals(null, r.templateId);

        // Each level should be persisted with the expected external ref
        Form_Template__c t = [SELECT Id, Name, External_Reference__c FROM Form_Template__c WHERE External_Reference__c = 'TPL-A'];
        System.assertEquals('Sample template', t.Name);

        Form_Page__c p = [SELECT Id, Form_Template__c, Title__c FROM Form_Page__c WHERE External_Reference__c = 'P-A'];
        System.assertEquals(t.Id, p.Form_Template__c, 'page linked to template');

        Form_Section__c s = [
            SELECT Id, Form_Page__c, Title__c, Policy_Text__c
            FROM Form_Section__c WHERE External_Reference__c = 'S-A'
        ];
        System.assertEquals(p.Id, s.Form_Page__c, 'section linked to page');
        System.assertEquals('Some policy text', s.Policy_Text__c,
            'policy_text persisted to first-class field');

        Form_Question_Catalog__c cat = [
            SELECT Id, Question__c, Type__c, Required__c
            FROM Form_Question_Catalog__c WHERE External_Reference__c = 'C-A'
        ];
        System.assertEquals('Catalog question text', cat.Question__c);

        Form_Question__c q = [
            SELECT Id, Form_Section__c, Form_Question_Catalog__c, Order__c
            FROM Form_Question__c WHERE External_Reference__c = 'B-A'
        ];
        System.assertEquals(s.Id, q.Form_Section__c, 'binding linked to section');
        System.assertEquals(cat.Id, q.Form_Question_Catalog__c, 'binding linked to catalog');
    }

    @isTest
    static void reImport_isIdempotent_upsertsByExternalRef() {
        NeuraFormIR ir = buildSimpleIR('TPL-B');

        Test.startTest();
        NeuraFormImporter.ImportResult first = NeuraFormImporter.runImport(ir);
        NeuraFormImporter.ImportResult second = NeuraFormImporter.runImport(ir);
        Test.stopTest();

        System.assertEquals(1, first.templatesCreated, 'first run creates');
        System.assertEquals(0, second.templatesCreated, 'second run does not create');
        System.assertEquals(1, second.templatesUpdated, 'second run updates');
        System.assertEquals(1, second.catalogEntriesUpdated);
        System.assertEquals(1, second.pagesUpdated);
        System.assertEquals(1, second.sectionsUpdated);
        System.assertEquals(1, second.bindingsUpdated);
        System.assertEquals(first.templateId, second.templateId,
            'same template Id across runs');

        System.assertEquals(1, [SELECT COUNT() FROM Form_Template__c WHERE External_Reference__c = 'TPL-B']);
        System.assertEquals(1, [SELECT COUNT() FROM Form_Page__c WHERE External_Reference__c = 'P-B']);
        System.assertEquals(1, [SELECT COUNT() FROM Form_Section__c WHERE External_Reference__c = 'S-B']);
        System.assertEquals(1, [SELECT COUNT() FROM Form_Question_Catalog__c WHERE External_Reference__c = 'C-B']);
        System.assertEquals(1, [SELECT COUNT() FROM Form_Question__c WHERE External_Reference__c = 'B-B']);
    }

    @isTest
    static void warnings_emittedForMissingRefs() {
        NeuraFormIR ir = new NeuraFormIR();
        NeuraFormIR.Template t = new NeuraFormIR.Template();
        t.external_ref = 'TPL-C';
        t.name = 'Tpl C';
        ir.template = t;

        // Section points at a page that's not in the IR
        NeuraFormIR.Section s = new NeuraFormIR.Section();
        s.external_ref = 'S-C';
        s.page_ref = 'DOES-NOT-EXIST';
        s.title = 'Orphan section';
        ir.sections.add(s);

        // Binding points at a section that's there and a catalog ref
        // that's missing
        NeuraFormIR.Binding b = new NeuraFormIR.Binding();
        b.external_ref = 'B-C';
        b.section_ref = 'S-C';
        b.catalog_ref = 'MISSING-CAT';
        ir.bindings.add(b);

        Test.startTest();
        NeuraFormImporter.ImportResult r = NeuraFormImporter.runImport(ir);
        Test.stopTest();

        System.assert(r.warnings.size() >= 2,
            'Expected at least two warnings (missing page, missing catalog), got: ' + r.warnings);
        Boolean sawPageWarning = false;
        Boolean sawCatalogWarning = false;
        for (String w : r.warnings) {
            if (w.contains('unknown page')) sawPageWarning = true;
            if (w.contains('unknown catalog')) sawCatalogWarning = true;
        }
        System.assert(sawPageWarning, 'Expected a warning about the unknown page ref');
        System.assert(sawCatalogWarning, 'Expected a warning about the unknown catalog ref');

        // Section should still be created (without page link), binding too
        Form_Section__c sec = [
            SELECT Id, Form_Page__c FROM Form_Section__c WHERE External_Reference__c = 'S-C'
        ];
        System.assertEquals(null, sec.Form_Page__c, 'Unresolved page ref leaves Form_Page__c null');
    }

    @isTest
    static void conditions_resolveCatalogRefsToBindingIds() {
        NeuraFormIR ir = new NeuraFormIR();
        NeuraFormIR.Template t = new NeuraFormIR.Template();
        t.external_ref = 'TPL-D';
        t.name = 'Conditions test';
        ir.template = t;

        NeuraFormIR.CatalogEntry c1 = new NeuraFormIR.CatalogEntry();
        c1.external_ref = 'CAT-D1';
        c1.question_text = 'First question';
        c1.type = 'Text';
        ir.catalog_entries.add(c1);
        NeuraFormIR.CatalogEntry c2 = new NeuraFormIR.CatalogEntry();
        c2.external_ref = 'CAT-D2';
        c2.question_text = 'Conditional question';
        c2.type = 'Text';
        ir.catalog_entries.add(c2);

        NeuraFormIR.Section s = new NeuraFormIR.Section();
        s.external_ref = 'S-D';
        s.title = 'Section D';
        ir.sections.add(s);

        NeuraFormIR.Binding b1 = new NeuraFormIR.Binding();
        b1.external_ref = 'B-D1';
        b1.section_ref = 'S-D';
        b1.catalog_ref = 'CAT-D1';
        ir.bindings.add(b1);

        NeuraFormIR.Binding b2 = new NeuraFormIR.Binding();
        b2.external_ref = 'B-D2';
        b2.section_ref = 'S-D';
        b2.catalog_ref = 'CAT-D2';
        // Condition references the catalog ref of the first question;
        // importer resolves it to b1's new Form_Question__c Id.
        NeuraFormIR.Condition cond = new NeuraFormIR.Condition();
        cond.resource = 'CAT-D1';
        cond.operator = 'equals';
        cond.value = 'yes';
        b2.conditions = new List<NeuraFormIR.Condition>{ cond };
        ir.bindings.add(b2);

        Test.startTest();
        NeuraFormImporter.ImportResult r = NeuraFormImporter.runImport(ir);
        Test.stopTest();

        Form_Question__c b1Row = [
            SELECT Id FROM Form_Question__c WHERE External_Reference__c = 'B-D1'
        ];
        Form_Question__c b2Row = [
            SELECT Id, Conditions__c FROM Form_Question__c WHERE External_Reference__c = 'B-D2'
        ];
        System.assertNotEquals(null, b2Row.Conditions__c, 'Conditions__c should be set');
        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(b2Row.Conditions__c);
        List<Object> conditions = (List<Object>) parsed.get('conditions');
        System.assertEquals(1, conditions.size());
        Map<String, Object> cm = (Map<String, Object>) conditions[0];
        System.assertEquals(b1Row.Id, (Id) cm.get('resource'),
            'Condition resource should resolve from catalog ref to the binding Id of that catalog');
        System.assertEquals('equals', cm.get('operator'));
        System.assertEquals('yes', cm.get('value'));
    }

    @isTest
    static void runImport_throwsOnMissingTemplate() {
        NeuraFormIR ir = new NeuraFormIR(); // no template set
        try {
            NeuraFormImporter.runImport(ir);
            System.assert(false, 'Should have thrown for missing template');
        } catch (NeuraFormImporter.AdapterException e) {
            System.assert(e.getMessage().contains('template'),
                'AdapterException should mention missing template block');
        }
    }

    @isTest
    static void runImport_throwsOnMissingTemplateExternalRef() {
        NeuraFormIR ir = new NeuraFormIR();
        ir.template = new NeuraFormIR.Template();
        ir.template.name = 'No external ref';
        try {
            NeuraFormImporter.runImport(ir);
            System.assert(false, 'Should have thrown for missing template external_ref');
        } catch (NeuraFormImporter.AdapterException e) {
            System.assert(e.getMessage().contains('external_ref'),
                'AdapterException should mention missing external_ref');
        }
    }

    @isTest
    static void runImport_throwsOnNullIR() {
        try {
            NeuraFormImporter.runImport(null);
            System.assert(false, 'Should have thrown for null IR');
        } catch (NeuraFormImporter.AdapterException e) {
            System.assert(e.getMessage().contains('null'));
        }
    }

    // -----------------------------------------------------------------
    // helpers
    // -----------------------------------------------------------------

    /**
     * Build a minimal valid IR with one of each level. Lets each test
     * scope its own external_ref suffix so a single test setup doesn't
     * collide across tests.
     */
    private static NeuraFormIR buildSimpleIR(String tplSuffix) {
        String letter = tplSuffix.right(1);
        NeuraFormIR ir = new NeuraFormIR();
        NeuraFormIR.Template t = new NeuraFormIR.Template();
        t.external_ref = tplSuffix;
        t.name = 'Sample template';
        ir.template = t;

        NeuraFormIR.CatalogEntry cat = new NeuraFormIR.CatalogEntry();
        cat.external_ref = 'C-' + letter;
        cat.question_text = 'Catalog question text';
        cat.type = 'Text';
        cat.required = true;
        ir.catalog_entries.add(cat);

        NeuraFormIR.IRPage p = new NeuraFormIR.IRPage();
        p.external_ref = 'P-' + letter;
        p.title = 'Page ' + letter;
        p.order = 1;
        ir.pages.add(p);

        NeuraFormIR.Section s = new NeuraFormIR.Section();
        s.external_ref = 'S-' + letter;
        s.page_ref = 'P-' + letter;
        s.title = 'Section ' + letter;
        s.order = 1;
        s.policy_text = 'Some policy text';
        ir.sections.add(s);

        NeuraFormIR.Binding b = new NeuraFormIR.Binding();
        b.external_ref = 'B-' + letter;
        b.section_ref = 'S-' + letter;
        b.catalog_ref = 'C-' + letter;
        b.order = 1;
        b.column = '1';
        ir.bindings.add(b);

        return ir;
    }
}
