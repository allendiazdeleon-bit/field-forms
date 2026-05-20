@isTest
public class NeuraFormExportControllerTest {
    
    // Utility method to create test data for Form_Template__c and related objects
    static void createTestData() {
        Form_Template__c template = new Form_Template__c(Name='Test Template');
        insert template;
        System.debug('Test Template Id: ' + template.Id);
        
        Form_Page__c page = new Form_Page__c(Name='Test Page', Form_Template__c=template.Id);
        insert page;
        
        Form_Section__c section = new Form_Section__c(Name='Test Section', Form_Template__c=template.Id, Form_Page__c=page.Id);
        insert section;
        
        List<Form_Question__c> questions = new List<Form_Question__c>();
        Form_Question__c question = new Form_Question__c(Question__c='Test Question', Form_Template__c=template.Id, Form_Section__c=section.Id);
        Form_Question__c question2 = new Form_Question__c(Question__c='Test Question 2', Form_Template__c=template.Id, Form_Section__c=section.Id);
        questions.add(question);
        questions.add(question2);
        insert questions;
    }

    static void setCustomSetting(){
        FieldForms_Configuration__c cusSetting = new FieldForms_Configuration__c();
        cusSetting.Disable_Form_Template_JSON_Trigger__c = true; 
        insert cusSetting;
    }
    @isTest static void testRunTemplateRollup(){
        setCustomSetting();
        createTestData();
        
        Form_Template__c template = [SELECT Id, External_Reference__c FROM Form_Template__c LIMIT 1];
        List<Form_Question__c> questions = [SELECT Id, Name, Form_Section__c, Order__c, Question__c, Label_Visible__c, Text_Alignment__c, Font_Size__c, Font_Color__c, Value_Set__c, Include_Comment__c, Include_Photo__c, Type__c, Form_Template__c,Layout_Item__c,Display_Rich_Text__c, Conditions__c FROM Form_Question__c WHERE Form_Template__c = :template.Id];
        Test.startTest();
        System.debug('In Test Template Id: ' + template.Id);
        System.debug('Questions: ' + questions);
        Boolean result = neuraFormExportController.runTemplateRollup(new List<String>{template.Id});
        Test.stopTest();
        Form_Template__c newTemplate = [SELECT Id, Pages_JSON__c, Sections_JSON__c, Questions_JSON__c, External_Reference__c FROM Form_Template__c LIMIT 1];
        System.assert(newTemplate.Pages_JSON__c != null, 'Pages_JSON__c should not be null');
        System.assert(newTemplate.Sections_JSON__c != null, 'Sections_JSON__c should not be null');
        System.assert(newTemplate.Questions_JSON__c != null, 'Questions_JSON__c should not be null');
    }

    // Test method for fetchTemplatesData
    @isTest static void testFetchTemplatesData() {
        createTestData();
        Form_Template__c template = [SELECT Id, External_Reference__c FROM Form_Template__c LIMIT 1];

        Test.startTest();
        String jsonData = neuraFormExportController.fetchTemplatesData(new List<String>{template.Id});
        Test.stopTest();
        
        // Asserts
        System.assertNotEquals(null, jsonData, 'The JSON data should not be null');
    }

    // Test method for importTemplates
    @isTest static void testImportTemplates() {
        createTestData();
        // Determine if in NameSpace context or not
        String namespacePrefix = NeuraFormUtils.getNamespacePrefix();
        String fieldName = namespacePrefix + 'External_Reference__c';

        Form_Template__c template = [SELECT Id, External_Reference__c FROM Form_Template__c LIMIT 1];
        String jsonContent = neuraFormExportController.fetchTemplatesData(new List<String>{template.Id});

        Test.startTest();
        neuraFormExportController.ImportResult result = neuraFormExportController.importTemplates(jsonContent);
        Test.stopTest();

        System.assertNotEquals(null, result, 'ImportResult should be returned');
        System.assertEquals(1, result.templates.size(), 'There should be one template processed');
        System.assertEquals(template.Id, result.templates[0].External_Reference__c, 'The external reference should match the source Id');
        System.assertEquals(0, result.warnings.size(), 'A round-trip of a known-good template should produce no warnings');
        // The original record was inserted without an External_Reference, so
        // the export sets it on the in-memory copy only. Re-importing matches
        // nothing in the DB (existing row still has null External_Reference)
        // and inserts a new record.
        System.assertEquals(1, result.createdCount, 'Round-trip should create a new row when the source had a null External_Reference');
        System.assertEquals(0, result.updatedCount);
    }

    // Test method to cover the exception scenario in importTemplates
    @isTest static void testImportTemplatesExceptionScenario() {
        String badJsonContent = 'not a valid JSON string';
        try {
            Test.startTest();
            neuraFormExportController.importTemplates(badJsonContent);
            Test.stopTest();
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected exception was thrown');
        }
    }

    // Test method to cover the exception scenario in fetchTemplatesData
    @isTest static void testFetchTemplatesDataExceptionScenario() {
        try {
            Test.startTest();
            neuraFormExportController.fetchTemplatesData(null);
            Test.stopTest();
            System.assert(false, 'Exception should have been thrown');
        } catch (AuraHandledException e) {
            System.assert(true, 'Expected exception was thrown');
        }
    }

    // --- Wave 16+ coverage --------------------------------------------------

    @isTest static void testImportTemplatesAsNew() {
        // Existing template is round-tripped with the import-as-new variant.
        // Should always CREATE a fresh row, never UPDATE - the External
        // References are regenerated server-side.
        createTestData();
        Form_Template__c template = [SELECT Id FROM Form_Template__c LIMIT 1];
        String json = neuraFormExportController.fetchTemplatesData(new List<String>{ template.Id });

        Test.startTest();
        neuraFormExportController.ImportResult result = neuraFormExportController.importTemplatesAsNew(json);
        Test.stopTest();

        System.assertEquals(1, result.createdCount, 'import-as-new should always create');
        System.assertEquals(0, result.updatedCount);
        System.assertEquals(2, [SELECT COUNT() FROM Form_Template__c], 'Original + clone should both exist');
        Form_Template__c imported = result.templates[0];
        System.assertNotEquals(template.Id, imported.External_Reference__c,
            'import-as-new should regenerate External_Reference');
    }

    @isTest static void testImportTemplatesRejectsEmpty() {
        Boolean threw = false;
        try { neuraFormExportController.importTemplates(null); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'null payload should be rejected');

        threw = false;
        try { neuraFormExportController.importTemplates('   '); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'blank payload should be rejected');

        threw = false;
        try { neuraFormExportController.importTemplates('[]'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'empty array should be rejected');
    }

    @isTest static void testModifyCriteriaWithResult() {
        // Missing references become warnings, not silent nulls.
        String conditions = '{"conditions":[{"resource":"unknownQ1"},{"resource":"knownQ2"}]}';
        Map<String, Id> questionMap = new Map<String, Id>{
            'knownQ2' => UserInfo.getUserId() // any Id will do as a stand-in
        };
        neuraFormExportController.CriteriaRewriteResult result =
            neuraFormExportController.modifyCriteriaWithResult(
                conditions,
                new Map<String, Id>(),
                new Map<String, Id>(),
                questionMap
            );
        System.assertEquals(true, result.changed, 'known reference should have been rewritten');
        System.assertEquals(1, result.warnings.size(), 'one unknown reference -> one warning');
        System.assert(result.json.contains('unknownQ1'),
            'unknown ref should remain in the JSON so renderer never sees null');
    }

    @isTest static void testModifyCriteriaWithResultNoChange() {
        // No conditions present -> changed stays false so the caller skips DML.
        neuraFormExportController.CriteriaRewriteResult result =
            neuraFormExportController.modifyCriteriaWithResult(
                '{"conditions":[]}',
                new Map<String, Id>(),
                new Map<String, Id>(),
                new Map<String, Id>()
            );
        System.assertEquals(false, result.changed);
        System.assertEquals(0, result.warnings.size());
    }

    @isTest static void testFetchTemplatesDataRespectsLimit() {
        neuraFormExportController.EXPORT_TEMPLATE_LIMIT = 2;
        List<String> ids = new List<String>{ '001000000000001', '001000000000002', '001000000000003' };
        Boolean threw = false;
        try { neuraFormExportController.fetchTemplatesData(ids); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'fetchTemplatesData should reject over-cap requests');
    }

    @isTest static void testFetchTemplatesDataRejectsEmpty() {
        Boolean threw = false;
        try { neuraFormExportController.fetchTemplatesData(new List<String>()); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'empty list should be rejected');
    }

    @isTest static void testListAccessibleTemplates() {
        createTestData();
        Test.startTest();
        List<Form_Template__c> result = neuraFormExportController.listAccessibleTemplates();
        Test.stopTest();
        System.assert(!result.isEmpty(), 'fallback list should return at least one template');
    }

    @isTest static void testGetSampleImportJson() {
        String sample = neuraFormExportController.getSampleImportJson();
        System.assertNotEquals(null, sample);

        Test.startTest();
        neuraFormExportController.PreviewResult preview =
            neuraFormExportController.previewImport(sample);
        Test.stopTest();

        System.assertEquals(1, preview.templateCount, 'sample has one template');
        System.assertEquals(1, preview.pageCount);
        System.assertEquals(1, preview.sectionCount);
        System.assertEquals(1, preview.questionCount);
        System.assertEquals(1, preview.toCreateCount,
            'sample External_Reference does not match anything in the org');
    }

    @isTest static void testPreviewImportNameCollision() {
        insert new Form_Template__c(Name = 'Sample Inspection', External_Reference__c = 'OTHER_REF');
        String sample = neuraFormExportController.getSampleImportJson();
        Test.startTest();
        neuraFormExportController.PreviewResult preview =
            neuraFormExportController.previewImport(sample);
        Test.stopTest();
        System.assert(!preview.nameCollisions.isEmpty(),
            'should warn about existing same-name template with different External_Reference');
    }

    @isTest static void testPreviewImportSurfacesDanglingConditionRefs() {
        Map<String, Object> question = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => 'Form_Question__c' },
            'Name' => 'Q1',
            'External_Reference__c' => 'Q_PRESENT',
            'Form_Template__c' => 'T1',
            'Question__c' => 'Test',
            'Type__c' => 'Text',
            'Conditions__c' => '{"conditions":[{"resource":"Q_MISSING"}]}'
        };
        Map<String, Object> template = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => 'Form_Template__c' },
            'Name' => 'Dangling-ref Template',
            'External_Reference__c' => 'T1'
        };
        String payload = JSON.serialize(new List<Object>{
            new Map<String, Object>{
                'template' => template,
                'pages' => new List<Object>(),
                'sections' => new List<Object>(),
                'questions' => new List<Object>{ question }
            }
        });
        Test.startTest();
        neuraFormExportController.PreviewResult preview =
            neuraFormExportController.previewImport(payload);
        Test.stopTest();
        System.assert(!preview.warnings.isEmpty(),
            'preview should flag the dangling question reference');
    }

    @isTest static void testPreviewImportRejectsInvalidJson() {
        Boolean threw = false;
        try { neuraFormExportController.previewImport('not json'); }
        catch (AuraHandledException e) { threw = true; }
        System.assert(threw, 'preview should reject malformed JSON');
    }

    // -----------------------------------------------------------------------

    // Test method for package-private methods
    @isTest
    static void testPackagePrivateMethods() {
        // Test generateFieldList method
        String fieldList = neuraFormExportController.generateFieldList('Form_Template__c');
        System.assertNotEquals(null, fieldList, 'The field list should not be null');

        // Test addExternalIdValues method
        createTestData();
        List<Form_Template__c> templates = [SELECT Id, External_Reference__c, (SELECT Id, External_Reference__c FROM Form_Pages__r), (SELECT Id, External_Reference__c FROM Form_Sections__r), (SELECT Id, External_Reference__c FROM Form_Questions__r) FROM Form_Template__c];
        templates = neuraFormExportController.addExternalIdValues(templates);
        System.assertEquals(null, templates[0].Id, 'Template ID should be null after method call');
        System.assertNotEquals(null, templates[0].External_Reference__c, 'External reference should not be null');

        // Test removeStrings method
        List<String> listToClean = new List<String>{'ownerid', 'createdbyid', 'isdeleted', 'field1', 'field2'};
        Set<String> removalList = new Set<String>{'ownerid', 'createdbyid', 'isdeleted'};
        List<String> cleanedList = neuraFormExportController.removeStrings(listToClean, removalList);
        System.assertEquals(2, cleanedList.size(), 'Cleaned list should have 2 fields');
    }
}