/**
 * Coverage for NeuraFormFieldFormsAdapter — verifies that the existing
 * exporter shape (a JSON array of FormTemplateWrapper objects) parses
 * cleanly into a valid NeuraFormIR.
 *
 * The fixture is built by handing JSON.serialize a synthetic Map that
 * mirrors what `neuraFormExportController.fetchTemplatesData` produces:
 * each record is a flat field map keyed by the namespaced field names.
 */
@isTest
private class NeuraFormFieldFormsAdapterTest {

    @isTest
    static void label_isStable() {
        NeuraFormFieldFormsAdapter a = new NeuraFormFieldFormsAdapter();
        System.assertEquals(NeuraFormImportPipeline.LABEL_FIELD_FORMS, a.label(),
            'Adapter label is the stable identifier in the registry');
    }

    @isTest
    static void canHandle_recognizesWrapperShape() {
        NeuraFormFieldFormsAdapter a = new NeuraFormFieldFormsAdapter();
        String good = buildWrapperJson('TPL-FF');
        System.assert(a.canHandle(good) >= 0.5,
            'Wrapper shape should score reasonably high');
        System.assertEquals(0, a.canHandle(null), 'null source scores 0');
        System.assertEquals(0, a.canHandle(''), 'empty source scores 0');
        System.assertEquals(0, a.canHandle('{"unrelated":1}'),
            'Non-array JSON should score 0');
    }

    @isTest
    static void parse_producesValidIRFromWrapperShape() {
        NeuraFormFieldFormsAdapter a = new NeuraFormFieldFormsAdapter();
        String json = buildWrapperJson('TPL-FF1');

        Test.startTest();
        NeuraFormIR ir = a.parse(json, null);
        Test.stopTest();

        System.assertEquals('1.0', ir.ir_version);
        System.assertEquals('TPL-FF1', ir.template.external_ref);
        System.assertEquals('Round Trip Template', ir.template.name);

        System.assertEquals(1, ir.pages.size());
        System.assertEquals('PAGE-FF1', ir.pages[0].external_ref);
        System.assertEquals('Page 1', ir.pages[0].title);
        System.assertEquals(1, ir.pages[0].order);

        System.assertEquals(1, ir.sections.size());
        System.assertEquals('SEC-FF1', ir.sections[0].external_ref);
        System.assertEquals('PAGE-FF1', ir.sections[0].page_ref);

        // Each question yields one catalog entry + one binding
        System.assertEquals(2, ir.catalog_entries.size(),
            'Each question emits a catalog entry');
        System.assertEquals(2, ir.bindings.size(),
            'Each question emits a binding');

        // Catalog ref namespaced with ff_ to avoid collision with
        // backfill / builder synthetic refs
        for (NeuraFormIR.CatalogEntry cat : ir.catalog_entries) {
            System.assert(cat.external_ref.startsWith('ff_'),
                'Adapter-created catalog refs use ff_ prefix');
        }

        // Binding catalog_ref matches the catalog external_ref
        for (NeuraFormIR.Binding b : ir.bindings) {
            Boolean matched = false;
            for (NeuraFormIR.CatalogEntry cat : ir.catalog_entries) {
                if (cat.external_ref == b.catalog_ref) { matched = true; break; }
            }
            System.assert(matched, 'Each binding should reference an existing catalog entry');
        }
    }

    @isTest
    static void parse_throwsAdapterExceptionOnInvalidJson() {
        NeuraFormFieldFormsAdapter a = new NeuraFormFieldFormsAdapter();
        try {
            a.parse('not json', null);
            System.assert(false, 'Should have thrown');
        } catch (NeuraFormImporter.AdapterException e) {
            System.assert(e.getMessage().contains('Could not parse'),
                'Should produce a parse-failure message');
        }
    }

    @isTest
    static void parse_throwsOnMissingTemplateExternalRef() {
        // Wrapper missing External_Reference on template block
        Map<String, Object> tpl = new Map<String, Object>{
            'Name' => 'No ext ref'
        };
        String json = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'template' => tpl,
                'pages' => new List<Object>(),
                'sections' => new List<Object>(),
                'questions' => new List<Object>()
            }
        });

        NeuraFormFieldFormsAdapter a = new NeuraFormFieldFormsAdapter();
        try {
            a.parse(json, null);
            System.assert(false, 'Should have thrown for missing template ext ref');
        } catch (NeuraFormImporter.AdapterException e) {
            System.assert(
                e.getMessage().contains('External_Reference__c'),
                'AdapterException should mention the missing external ref'
            );
        }
    }

    @isTest
    static void parse_throwsOnEmptyArray() {
        NeuraFormFieldFormsAdapter a = new NeuraFormFieldFormsAdapter();
        try {
            a.parse('[]', null);
            System.assert(false);
        } catch (NeuraFormImporter.AdapterException e) {
            System.assert(e.getMessage().contains('No templates'));
        }
    }

    @isTest
    static void pipeline_endToEnd_createsRecords() {
        // Verifies the adapter + importer chain through the pipeline.
        FieldForms_Configuration__c cfg = new FieldForms_Configuration__c();
        cfg.Disable_Form_Template_JSON_Trigger__c = true;
        insert cfg;

        String json = buildWrapperJson('TPL-E2E');

        Test.startTest();
        NeuraFormImportPipeline.PipelineResult pr =
            NeuraFormImportPipeline.importSource(json, null, null);
        Test.stopTest();

        System.assertEquals(NeuraFormImportPipeline.LABEL_FIELD_FORMS, pr.adapterLabel,
            'Auto-pick should land on the Field Forms adapter');
        System.assertEquals(1, pr.createdCount);
        System.assertEquals(0, pr.updatedCount);
        System.assertEquals(1, [SELECT COUNT() FROM Form_Template__c WHERE External_Reference__c = 'TPL-E2E']);
        System.assertEquals(2, [SELECT COUNT() FROM Form_Question_Catalog__c WHERE External_Reference__c LIKE 'ff_%']);
    }

    /**
     * Construct an exporter-shape JSON payload identical to what
     * neuraFormExportController.fetchTemplatesData emits. Each record is
     * a flat Map with namespaced field names; conditions live as JSON
     * strings inside Conditions__c.
     */
    private static String buildWrapperJson(String tplRef) {
        String ns = NeuraFormUtils.getNamespacePrefix();
        Map<String, Object> tpl = new Map<String, Object>{
            'Name' => 'Round Trip Template',
            ns + 'External_Reference__c' => tplRef
        };
        Map<String, Object> page = new Map<String, Object>{
            ns + 'External_Reference__c' => 'PAGE-FF1',
            ns + 'Title__c' => 'Page 1',
            ns + 'Order__c' => 1
        };
        Map<String, Object> section = new Map<String, Object>{
            ns + 'External_Reference__c' => 'SEC-FF1',
            ns + 'Form_Page__c' => 'PAGE-FF1',
            ns + 'Title__c' => 'Section 1',
            ns + 'Order__c' => 1,
            ns + 'Columns__c' => '1'
        };
        Map<String, Object> q1 = new Map<String, Object>{
            ns + 'External_Reference__c' => 'Q-FF1',
            ns + 'Form_Section__c' => 'SEC-FF1',
            ns + 'Question__c' => 'First question?',
            ns + 'Type__c' => 'Text',
            ns + 'Order__c' => 1,
            ns + 'Required__c' => true
        };
        Map<String, Object> q2 = new Map<String, Object>{
            ns + 'External_Reference__c' => 'Q-FF2',
            ns + 'Form_Section__c' => 'SEC-FF1',
            ns + 'Question__c' => 'Second question?',
            ns + 'Type__c' => 'Multiple Choice',
            ns + 'Value_Set__c' => '[{"id":"a","label":"A","value":"a"}]',
            ns + 'Order__c' => 2
        };
        return JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'template' => tpl,
                'pages' => new List<Object>{ page },
                'sections' => new List<Object>{ section },
                'questions' => new List<Object>{ q1, q2 }
            }
        });
    }
}
