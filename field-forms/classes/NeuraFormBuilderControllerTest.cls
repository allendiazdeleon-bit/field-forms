@isTest
private class NeuraFormBuilderControllerTest {
    @testSetup
    static void setup() {
        // Create test data for Form_Template__c, Form_Page__c, Form_Section__c, and Form_Question__c
        Form_Template__c formTemplate = new Form_Template__c(
            Name = 'Test Template',
            Indicator_Type__c = 'Ring'
        );
        insert formTemplate;

        Form_Page__c formPage = new Form_Page__c(
            Name = 'Test Page',
            Order__c = 1,
            Title__c = 'Test Title',
            Form_Template__c = formTemplate.Id
        );
        insert formPage;

        Form_Section__c formSection = new Form_Section__c(
            Name = 'Test Section',
            Order__c = 1,
            Title__c = 'Test Title',
            Form_Template__c = formTemplate.Id,
            Form_Page__c = formPage.Id
        );
        insert formSection;

        Form_Question__c formQuestion = new Form_Question__c(
            Order__c = 1,
            Question__c = 'Test Question?',
            Form_Template__c = formTemplate.Id,
            Form_Section__c = formSection.Id,
            Form_Page__c = formPage.Id
        );
        insert formQuestion;
    }

    @isTest
    static void testGetAllAttributes() {
        Test.startTest();
        List<Form_Setting_to_Field__mdt> result = neuraFormBuilderController.getAllAttributes();
        Test.stopTest();

        // Verify the result
        System.assertNotEquals(0, result.size(), 'Expected non-zero size of results');
        System.assert(result[0].Form_Setting_Field__r.Label.startsWith(NeuraFormUtils.getNamespacePrefix()), 'Expected the label to start with the namespace prefix');
    }

    @isTest
    static void testGetFormDetails() {
        Form_Template__c formTemplate = [SELECT Id FROM Form_Template__c LIMIT 1];

        Test.startTest();
        neuraFormBuilderController.FormWrapper result = neuraFormBuilderController.getFormDetails(formTemplate.Id);
        Test.stopTest();

        // Verify the result
        System.assertNotEquals(null, result, 'Expected non-null result');
        System.assertEquals(formTemplate.Id, result.formTemplate.Id, 'Expected matching template Id');
        System.assert(result.pages.size() > 0, 'Expected non-zero pages size');
        System.assert(result.sections.size() > 0, 'Expected non-zero sections size');
        System.assert(result.questions.size() > 0, 'Expected non-zero questions size');
    }

    @isTest
    static void testGetFormMetadata() {
        Test.startTest();
        List<Form_Setting__mdt> result = neuraFormBuilderController.getFormMetadata();
        Test.stopTest();

        // Verify the result
        System.assertNotEquals(0, result.size(), 'Expected non-zero size of results');
    }

    @isTest
    static void testProcessFormUpdate() {
        // Create SObjects to insert, update, and delete
        Form_Template__c formTemplate = new Form_Template__c(Name = 'New Template');
        insert formTemplate;
        // remove the Id from the formTemplate to simulate an update
        formTemplate.Id = null;

        Form_Template__c formTemplateToUpdate = [SELECT Id FROM Form_Template__c LIMIT 1];
        List<Id> toDeleteIds = new List<Id>();
        toDeleteIds.add(formTemplateToUpdate.Id);

        Test.startTest();
        List<SObject> result = neuraFormBuilderController.processFormUpdate(
            new List<SObject> { formTemplate },
            new List<SObject>(),
            toDeleteIds
        );
        Test.stopTest();

        // Verify the result
        System.assertNotEquals(0, result.size(), 'Expected non-zero size of results');
        System.assert(result[0] instanceof Form_Template__c, 'Expected result instance of Form_Template__c');
    }

    @isTest
    static void testProcessFormRecord() {
        Form_Template__c formTemplate = new Form_Template__c(Name = 'New Template');
        Form_Template__c formTemplateToUpdate = [SELECT Id FROM Form_Template__c LIMIT 1];

        Test.startTest();
        Form_Template__c resultCreate = neuraFormBuilderController.processFormRecord(formTemplate, null);
        Form_Template__c resultUpdate = neuraFormBuilderController.processFormRecord(null, formTemplateToUpdate);
        Test.stopTest();

        // Verify the result
        System.assertNotEquals(null, resultCreate, 'Expected non-null result for create');
        System.assertNotEquals(null, resultUpdate, 'Expected non-null result for update');
    }

    @isTest
    static void testProcessPageRecords() {
        List<Form_Page__c> pagesToCreate = new List<Form_Page__c> {
            new Form_Page__c(Name = 'New Page', Order__c = 2, Title__c = 'New Title', Form_Template__c = [SELECT Id FROM Form_Template__c LIMIT 1].Id)
        };
        insert pagesToCreate;

        // Remove the Id from the pagesToCreate to simulate an update
        pagesToCreate[0].Id = null;

        List<Form_Page__c> pagesToUpdate = [SELECT Id, Name FROM Form_Page__c LIMIT 1];
        List<Id> pagesToDelete = new List<Id> { pagesToUpdate[0].Id };

        Test.startTest();
        List<Form_Page__c> result = neuraFormBuilderController.processPageRecords(pagesToCreate, new List<Form_Page__c>(), pagesToDelete);
        Test.stopTest();

        // Verify the result
        System.assertNotEquals(0, result.size(), 'Expected non-zero size of results');
    }

    @isTest
    static void testProcessSectionRecords() {
        List<Form_Section__c> sectionsToCreate = new List<Form_Section__c> {
            new Form_Section__c(Name = 'New Section', Order__c = 2, Title__c = 'New Title', Form_Template__c = [SELECT Id FROM Form_Template__c LIMIT 1].Id)
        };
        insert sectionsToCreate;

        // Remove the Id from the sectionsToCreate to simulate an update
        sectionsToCreate[0].Id = null;

        List<Form_Section__c> sectionsToUpdate = [SELECT Id, Name FROM Form_Section__c LIMIT 1];
        List<Id> sectionsToDelete = new List<Id> { sectionsToUpdate[0].Id };

        Test.startTest();
        List<Form_Section__c> result = neuraFormBuilderController.processSectionRecords(sectionsToCreate, new List<Form_Section__c>(), sectionsToDelete);
        Test.stopTest();

        // Verify the result
        System.assertNotEquals(0, result.size(), 'Expected non-zero size of results');
    }

    @isTest
    static void testProcessQuestionRecords() {
        List<Form_Question__c> questionsToCreate = new List<Form_Question__c> {
            new Form_Question__c(Order__c = 2, Question__c = 'New Question?', Form_Template__c = [SELECT Id FROM Form_Template__c LIMIT 1].Id)
        };
        insert questionsToCreate;

        // Remove the Id from the questionsToCreate to simulate an update
        questionsToCreate[0].Id = null;

        List<Form_Question__c> questionsToUpdate = [SELECT Id, Name FROM Form_Question__c LIMIT 1];
        List<Id> questionsToDelete = new List<Id> { questionsToUpdate[0].Id };

        Test.startTest();
        List<Form_Question__c> result = neuraFormBuilderController.processQuestionRecords(questionsToCreate, new List<Form_Question__c>(), questionsToDelete);
        Test.stopTest();

        // Verify the result
        System.assertNotEquals(0, result.size(), 'Expected non-zero size of results');
    }

    // ----- Pillar 2 catalog resolution tests --------------------------------

    @isTest
    static void testGetFormDetails_catalogOff_returnsBindingFields() {
        // No FieldForms_Configuration__c.Question_Catalog_Enabled__c set —
        // catalog resolution is a no-op and the LWC sees the binding's
        // own field values as before. Important backward-compat guarantee.
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];
        Form_Question__c binding = [
            SELECT Id, Question__c FROM Form_Question__c
            WHERE Form_Template__c = :ft.Id LIMIT 1
        ];

        // Link to a catalog entry with different content; verify the
        // catalog content does NOT bleed into the response.
        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-builder-off',
            Question__c = 'Catalog truth (should not appear)',
            Type__c = 'Text'
        );
        insert cat;
        binding.Form_Question_Catalog__c = cat.Id;
        update binding;

        Test.startTest();
        neuraFormBuilderController.FormWrapper result =
            neuraFormBuilderController.getFormDetails(ft.Id);
        Test.stopTest();

        System.assertEquals('Test Question?', result.questions[0].Question__c,
            'Catalog off → returned binding should keep its own Question__c');
    }

    @isTest
    static void testGetFormDetails_catalogOn_returnsResolvedFields() {
        // Catalog enabled → resolved values flow back to the LWC as if
        // they were the binding's own fields.
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];
        Form_Question__c binding = [
            SELECT Id FROM Form_Question__c WHERE Form_Template__c = :ft.Id LIMIT 1
        ];

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-builder-on',
            Question__c = 'Catalog-resolved text',
            Type__c = 'Multiple Choice',
            Required__c = true
        );
        insert cat;
        binding.Form_Question_Catalog__c = cat.Id;
        update binding;

        Test.startTest();
        neuraFormBuilderController.FormWrapper result =
            neuraFormBuilderController.getFormDetails(ft.Id);
        Test.stopTest();

        Form_Question__c resolved = result.questions[0];
        System.assertEquals('Catalog-resolved text', resolved.Question__c,
            'Catalog on → Question__c resolves through catalog');
        System.assertEquals('Multiple Choice', resolved.Type__c,
            'Catalog on → Type__c resolves through catalog');
        System.assertEquals(true, resolved.Required__c,
            'Catalog on → Required__c resolves through catalog');
        // Override fields are also returned on the wire so the LWC can show
        // "inherited" vs "overridden" badges without another roundtrip.
        System.assertEquals(cat.Id, resolved.Form_Question_Catalog__c,
            'Catalog ref stays on the binding for the LWC to read provenance');
    }

    @isTest
    static void testGetFormDetails_catalogOn_overridesWin() {
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];
        Form_Question__c binding = [
            SELECT Id FROM Form_Question__c WHERE Form_Template__c = :ft.Id LIMIT 1
        ];

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-builder-override',
            Question__c = 'Catalog default',
            Type__c = 'Text',
            Required__c = true
        );
        insert cat;
        binding.Form_Question_Catalog__c = cat.Id;
        binding.Override_Question__c = 'Per-binding override wins';
        binding.Override_Required__c = 'No';
        update binding;

        Test.startTest();
        neuraFormBuilderController.FormWrapper result =
            neuraFormBuilderController.getFormDetails(ft.Id);
        Test.stopTest();

        Form_Question__c resolved = result.questions[0];
        System.assertEquals('Per-binding override wins', resolved.Question__c,
            'Override_Question__c should beat catalog Question__c');
        System.assertEquals(false, resolved.Required__c,
            'Override_Required__c=No should flip catalog true to false');
        System.assertEquals('Per-binding override wins', resolved.Override_Question__c,
            'Override field itself stays on the wire for the LWC badge');
    }

    @isTest
    static void testGetFormDetails_catalogOn_nullCatalogRefFallsBackToBinding() {
        // Mid-migration: catalog enabled but a binding hasn't been linked
        // yet (Form_Question_Catalog__c is null). Should not crash and
        // should return the binding's own fields.
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];

        Test.startTest();
        neuraFormBuilderController.FormWrapper result =
            neuraFormBuilderController.getFormDetails(ft.Id);
        Test.stopTest();

        System.assertEquals('Test Question?', result.questions[0].Question__c,
            'Null catalog ref → binding keeps its own Question__c');
    }

    private static void enableCatalog() {
        FieldForms_Configuration__c cfg = new FieldForms_Configuration__c();
        cfg.Question_Catalog_Enabled__c = true;
        insert cfg;
    }
}