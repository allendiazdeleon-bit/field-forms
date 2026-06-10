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

    // ----- Pillar 2 auto-create-catalog-from-builder tests ------------------

    @isTest
    static void testProcessQuestionRecords_catalogOff_skipsAutoCreate() {
        // Catalog flag NOT set — auto-create should not run, even on a
        // brand-new binding. Backward compat with existing flows.
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];
        List<Form_Question__c> toCreate = new List<Form_Question__c>{
            new Form_Question__c(
                Form_Template__c = ft.Id,
                Question__c = 'Brand new question',
                Type__c = 'Text'
            )
        };

        Test.startTest();
        neuraFormBuilderController.processQuestionRecords(
            toCreate, new List<Form_Question__c>(), new List<Id>()
        );
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Form_Question_Catalog__c],
            'Auto-create should not run when Question_Catalog_Enabled__c is off');
        Form_Question__c saved = [
            SELECT Form_Question_Catalog__c FROM Form_Question__c
            WHERE Id = :toCreate[0].Id
        ];
        System.assertEquals(null, saved.Form_Question_Catalog__c,
            'Binding should not be linked to a catalog when the flag is off');
    }

    @isTest
    static void testProcessQuestionRecords_catalogOn_autoCreatesCatalog() {
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];
        List<Form_Question__c> toCreate = new List<Form_Question__c>{
            new Form_Question__c(
                Form_Template__c = ft.Id,
                Question__c = 'Brand new question',
                Type__c = 'Multiple Choice',
                Value_Set__c = '[{"id":"yes","label":"Yes","value":"yes"}]',
                Required__c = true
            )
        };

        Test.startTest();
        neuraFormBuilderController.processQuestionRecords(
            toCreate, new List<Form_Question__c>(), new List<Id>()
        );
        Test.stopTest();

        // A catalog entry was created.
        List<Form_Question_Catalog__c> catalogs = [
            SELECT Id, External_Reference__c, Question__c, Type__c,
                   Value_Set__c, Required__c
            FROM Form_Question_Catalog__c
        ];
        System.assertEquals(1, catalogs.size(),
            'Auto-create should produce one catalog entry');
        System.assertEquals('Brand new question', catalogs[0].Question__c,
            'Catalog should carry the binding\'s question content');
        System.assertEquals('Multiple Choice', catalogs[0].Type__c);
        System.assert(catalogs[0].Value_Set__c.contains('"yes"'),
            'Value_Set__c should be copied verbatim');
        System.assertEquals(true, catalogs[0].Required__c);
        System.assert(catalogs[0].External_Reference__c.startsWith('builder_'),
            'External ref should use the builder_ prefix');

        // The binding got linked to the new catalog entry.
        Form_Question__c saved = [
            SELECT Form_Question_Catalog__c FROM Form_Question__c
            WHERE Id = :toCreate[0].Id
        ];
        System.assertEquals(catalogs[0].Id, saved.Form_Question_Catalog__c,
            'Binding should be linked to the freshly created catalog entry');
    }

    @isTest
    static void testProcessQuestionRecords_catalogOn_preserveExistingCatalogRef() {
        // If the binding came in already linked to a catalog (e.g. via
        // the future "Pick from catalog" flow), do not create a new
        // catalog entry — respect the existing link.
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];

        Form_Question_Catalog__c existingCat = new Form_Question_Catalog__c(
            External_Reference__c = 'existing-link',
            Question__c = 'Existing catalog question',
            Type__c = 'Text'
        );
        insert existingCat;

        List<Form_Question__c> toCreate = new List<Form_Question__c>{
            new Form_Question__c(
                Form_Template__c = ft.Id,
                Form_Question_Catalog__c = existingCat.Id,
                Type__c = 'Text'
            )
        };

        Test.startTest();
        neuraFormBuilderController.processQuestionRecords(
            toCreate, new List<Form_Question__c>(), new List<Id>()
        );
        Test.stopTest();

        Integer catalogCount = [SELECT COUNT() FROM Form_Question_Catalog__c];
        System.assertEquals(1, catalogCount,
            'Only the existing catalog entry should be present; no new one created');

        Form_Question__c saved = [
            SELECT Form_Question_Catalog__c FROM Form_Question__c
            WHERE Id = :toCreate[0].Id
        ];
        System.assertEquals(existingCat.Id, saved.Form_Question_Catalog__c,
            'Pre-linked binding should keep its catalog reference');
    }

    @isTest
    static void testProcessQuestionRecords_catalogOn_bulkAutoCreate() {
        // Bulk insert path: 3 new bindings → 3 new catalog entries,
        // each binding linked to its own.
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];
        List<Form_Question__c> toCreate = new List<Form_Question__c>{
            new Form_Question__c(Form_Template__c = ft.Id, Question__c = 'Q1', Type__c = 'Text'),
            new Form_Question__c(Form_Template__c = ft.Id, Question__c = 'Q2', Type__c = 'Text'),
            new Form_Question__c(Form_Template__c = ft.Id, Question__c = 'Q3', Type__c = 'Text')
        };

        Test.startTest();
        neuraFormBuilderController.processQuestionRecords(
            toCreate, new List<Form_Question__c>(), new List<Id>()
        );
        Test.stopTest();

        System.assertEquals(3, [SELECT COUNT() FROM Form_Question_Catalog__c],
            'Three new bindings should produce three new catalog entries');

        // Each binding linked to a distinct catalog entry (no shared refs).
        List<Form_Question__c> saved = [
            SELECT Form_Question_Catalog__c FROM Form_Question__c
            WHERE Id IN :toCreate
        ];
        Set<Id> catalogIds = new Set<Id>();
        for (Form_Question__c b : saved) {
            System.assertNotEquals(null, b.Form_Question_Catalog__c,
                'Every new binding should be linked');
            catalogIds.add(b.Form_Question_Catalog__c);
        }
        System.assertEquals(3, catalogIds.size(),
            'Each binding should link to its own (unique) catalog entry');
    }

    // ----- Wave 35.8a: binding-count + sync-on-update tests ----------------

    @isTest
    static void testGetFormDetails_catalogOn_returnsCatalogBindingCounts() {
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];
        Form_Question__c binding = [
            SELECT Id FROM Form_Question__c WHERE Form_Template__c = :ft.Id LIMIT 1
        ];

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-binding-count-1',
            Question__c = 'Catalog text', Type__c = 'Text'
        );
        insert cat;
        binding.Form_Question_Catalog__c = cat.Id;
        update binding;

        Test.startTest();
        neuraFormBuilderController.FormWrapper result =
            neuraFormBuilderController.getFormDetails(ft.Id);
        Test.stopTest();

        System.assertNotEquals(null, result.catalogBindingCounts,
            'catalogBindingCounts should be populated when the flag is on');
        System.assertEquals(1, result.catalogBindingCounts.get(cat.Id),
            'Single binding catalog should report count of 1');
    }

    @isTest
    static void testGetFormDetails_catalogOff_omitsBindingCounts() {
        // Without the flag, no need to compute binding counts.
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];

        Test.startTest();
        neuraFormBuilderController.FormWrapper result =
            neuraFormBuilderController.getFormDetails(ft.Id);
        Test.stopTest();

        System.assertEquals(null, result.catalogBindingCounts,
            'catalogBindingCounts should be null when the catalog flag is off');
    }

    @isTest
    static void testGetFormDetails_catalogOn_sharedCatalogShowsCountAboveOne() {
        // Two bindings pointing to the same catalog entry; the count
        // should reflect both, including ones in other templates.
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];

        Form_Question_Catalog__c sharedCat = new Form_Question_Catalog__c(
            External_Reference__c = 'shared-binding-count',
            Question__c = 'Shared question', Type__c = 'Text'
        );
        insert sharedCat;

        Form_Question__c b1 = [
            SELECT Id FROM Form_Question__c WHERE Form_Template__c = :ft.Id LIMIT 1
        ];
        b1.Form_Question_Catalog__c = sharedCat.Id;
        update b1;

        // Second template + binding referencing the same catalog.
        Form_Template__c ft2 = new Form_Template__c(Name = 'Second template');
        insert ft2;
        Form_Question__c b2 = new Form_Question__c(
            Form_Template__c = ft2.Id,
            Form_Question_Catalog__c = sharedCat.Id,
            Question__c = 'Stale binding text', Type__c = 'Text'
        );
        insert b2;

        Test.startTest();
        neuraFormBuilderController.FormWrapper result =
            neuraFormBuilderController.getFormDetails(ft.Id);
        Test.stopTest();

        System.assertEquals(2, result.catalogBindingCounts.get(sharedCat.Id),
            'Catalog shared by 2 bindings (across templates) should report count of 2');
    }

    @isTest
    static void testProcessQuestionRecords_exclusiveSyncsToCatalogOnUpdate() {
        // Binding has exclusive catalog (count == 1), no override.
        // Updating the binding's Question__c should propagate to catalog.
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];
        Form_Question__c b = [
            SELECT Id FROM Form_Question__c WHERE Form_Template__c = :ft.Id LIMIT 1
        ];

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-exclusive-sync',
            Question__c = 'Original catalog text', Type__c = 'Text'
        );
        insert cat;
        b.Form_Question_Catalog__c = cat.Id;
        update b;

        // Now admin edits the binding's Question__c.
        b.Question__c = 'Edited via builder';

        Test.startTest();
        neuraFormBuilderController.processQuestionRecords(
            new List<Form_Question__c>(),
            new List<Form_Question__c>{b},
            new List<Id>()
        );
        Test.stopTest();

        Form_Question_Catalog__c after = [
            SELECT Question__c FROM Form_Question_Catalog__c WHERE Id = :cat.Id
        ];
        System.assertEquals('Edited via builder', after.Question__c,
            'Edit on exclusive-catalog binding should sync to the catalog');
    }

    @isTest
    static void testProcessQuestionRecords_sharedCatalogDoesNotSync() {
        // Binding is one of two pointing at the same catalog (count == 2).
        // The sync path should leave the catalog untouched.
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-shared-no-sync',
            Question__c = 'Pristine catalog text', Type__c = 'Text'
        );
        insert cat;

        Form_Question__c b1 = [
            SELECT Id FROM Form_Question__c WHERE Form_Template__c = :ft.Id LIMIT 1
        ];
        b1.Form_Question_Catalog__c = cat.Id;
        update b1;

        Form_Template__c ft2 = new Form_Template__c(Name = 'Second template');
        insert ft2;
        Form_Question__c b2 = new Form_Question__c(
            Form_Template__c = ft2.Id,
            Form_Question_Catalog__c = cat.Id,
            Question__c = 'Second binding text', Type__c = 'Text'
        );
        insert b2;

        // Admin updates b1's content.
        b1.Question__c = 'Attempt to mutate shared catalog';

        Test.startTest();
        neuraFormBuilderController.processQuestionRecords(
            new List<Form_Question__c>(),
            new List<Form_Question__c>{b1},
            new List<Id>()
        );
        Test.stopTest();

        Form_Question_Catalog__c after = [
            SELECT Question__c FROM Form_Question_Catalog__c WHERE Id = :cat.Id
        ];
        System.assertEquals('Pristine catalog text', after.Question__c,
            'Shared catalog should not be mutated when admin edits one of many bindings');
    }

    // ----- Wave 35.9: findSimilarCatalogEntries (SOSL) ---------------------

    @isTest
    static void testFindSimilarCatalogEntries_catalogOff_returnsEmpty() {
        // No catalog feature flag → SOSL not even attempted.
        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'sosl-feature-off',
            Question__c = 'Enter the date of last service',
            Type__c = 'Date'
        );
        insert cat;
        Test.setFixedSearchResults(new Id[]{ cat.Id });

        Test.startTest();
        List<neuraFormBuilderController.CatalogMatch> matches =
            neuraFormBuilderController.findSimilarCatalogEntries('Enter the date', 5, null);
        Test.stopTest();

        System.assertEquals(0, matches.size(),
            'No matches expected when catalog feature is off');
    }

    @isTest
    static void testFindSimilarCatalogEntries_shortQuery_returnsEmpty() {
        enableCatalog();
        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'sosl-short-query',
            Question__c = 'Enter the date of last service',
            Type__c = 'Date'
        );
        insert cat;
        Test.setFixedSearchResults(new Id[]{ cat.Id });

        Test.startTest();
        List<neuraFormBuilderController.CatalogMatch> matchesNull =
            neuraFormBuilderController.findSimilarCatalogEntries(null, 5, null);
        List<neuraFormBuilderController.CatalogMatch> matchesEmpty =
            neuraFormBuilderController.findSimilarCatalogEntries('', 5, null);
        List<neuraFormBuilderController.CatalogMatch> matchesShort =
            neuraFormBuilderController.findSimilarCatalogEntries('ab', 5, null);
        Test.stopTest();

        System.assertEquals(0, matchesNull.size());
        System.assertEquals(0, matchesEmpty.size());
        System.assertEquals(0, matchesShort.size(),
            'Queries shorter than 3 chars should short-circuit');
    }

    @isTest
    static void testFindSimilarCatalogEntries_returnsMatches() {
        enableCatalog();
        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'sosl-happy-path',
            Question__c = 'Enter the date of last service',
            Type__c = 'Date',
            Tags__c = 'date, service-history'
        );
        insert cat;
        // Test.setFixedSearchResults stubs SOSL for the next FIND in the
        // test; pass the Ids of records we want returned.
        Test.setFixedSearchResults(new Id[]{ cat.Id });

        Test.startTest();
        List<neuraFormBuilderController.CatalogMatch> matches =
            neuraFormBuilderController.findSimilarCatalogEntries('Enter the date', 5, null);
        Test.stopTest();

        System.assertEquals(1, matches.size(), 'One match expected');
        neuraFormBuilderController.CatalogMatch m = matches[0];
        System.assertEquals(cat.Id, m.id);
        System.assertEquals('Enter the date of last service', m.questionText);
        System.assertEquals('Date', m.type);
        System.assertEquals('date, service-history', m.tags);
        System.assertEquals('sosl-happy-path', m.externalReference);
        System.assertEquals(0, m.usageCount,
            'No bindings reference this catalog yet — usageCount = 0');
    }

    @isTest
    static void testFindSimilarCatalogEntries_reportsUsageCount() {
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'sosl-usage-count',
            Question__c = 'Reused question',
            Type__c = 'Text'
        );
        insert cat;

        // Link the existing binding to this catalog so usage count > 0.
        Form_Question__c existingBinding = [
            SELECT Id FROM Form_Question__c WHERE Form_Template__c = :ft.Id LIMIT 1
        ];
        existingBinding.Form_Question_Catalog__c = cat.Id;
        update existingBinding;

        Test.setFixedSearchResults(new Id[]{ cat.Id });

        Test.startTest();
        List<neuraFormBuilderController.CatalogMatch> matches =
            neuraFormBuilderController.findSimilarCatalogEntries('Reused', 5, null);
        Test.stopTest();

        System.assertEquals(1, matches.size());
        System.assertEquals(1, matches[0].usageCount,
            'usageCount should reflect the number of bindings referencing the catalog');
    }

    // ----- Wave 35.9b: scope filter + pre-linked binding -------------------

    @isTest
    static void testFindSimilarCatalogEntries_scopeFilter() {
        // A template scoped to 'chain-A' should see entries with
        // Scope__c = null AND entries with Scope__c = 'chain-A', but
        // not entries with Scope__c = 'chain-B'.
        enableCatalog();
        Form_Template__c scopedTemplate = new Form_Template__c(
            Name = 'Chain A Template',
            Scope__c = 'chain-A'
        );
        insert scopedTemplate;

        Form_Question_Catalog__c universal = new Form_Question_Catalog__c(
            External_Reference__c = 'scope-test-universal',
            Question__c = 'Universal question about date',
            Type__c = 'Date'
        );
        Form_Question_Catalog__c chainA = new Form_Question_Catalog__c(
            External_Reference__c = 'scope-test-chain-a',
            Question__c = 'Chain-A scoped date question',
            Type__c = 'Date',
            Scope__c = 'chain-A'
        );
        Form_Question_Catalog__c chainB = new Form_Question_Catalog__c(
            External_Reference__c = 'scope-test-chain-b',
            Question__c = 'Chain-B scoped date question',
            Type__c = 'Date',
            Scope__c = 'chain-B'
        );
        insert new List<Form_Question_Catalog__c>{ universal, chainA, chainB };

        // SOSL returns all three; the scope WHERE clause filters chain-B
        // out before results reach the caller.
        Test.setFixedSearchResults(new Id[]{ universal.Id, chainA.Id, chainB.Id });

        Test.startTest();
        List<neuraFormBuilderController.CatalogMatch> matches =
            neuraFormBuilderController.findSimilarCatalogEntries('date question', 5, scopedTemplate.Id);
        Test.stopTest();

        Set<Id> returned = new Set<Id>();
        for (neuraFormBuilderController.CatalogMatch m : matches) returned.add(m.id);
        System.assert(returned.contains(universal.Id),
            'Universal (null-scoped) entry should be visible to scoped template');
        System.assert(returned.contains(chainA.Id),
            'Matching-scope entry should be visible');
        System.assert(!returned.contains(chainB.Id),
            'Out-of-scope entry should be filtered out');
    }

    @isTest
    static void testFindSimilarCatalogEntries_unscopedTemplateSeesUniversalOnly() {
        // A template with Scope__c = null sees only null-scoped entries.
        // Any scoped entry is by definition not "universal" so should
        // not appear when the template has no scope to match.
        enableCatalog();
        Form_Template__c unscoped = [SELECT Id FROM Form_Template__c LIMIT 1];

        Form_Question_Catalog__c universal = new Form_Question_Catalog__c(
            External_Reference__c = 'scope-unscoped-universal',
            Question__c = 'Service universal',
            Type__c = 'Text'
        );
        Form_Question_Catalog__c chainA = new Form_Question_Catalog__c(
            External_Reference__c = 'scope-unscoped-chain-a',
            Question__c = 'Service chain-A',
            Type__c = 'Text',
            Scope__c = 'chain-A'
        );
        insert new List<Form_Question_Catalog__c>{ universal, chainA };

        Test.setFixedSearchResults(new Id[]{ universal.Id, chainA.Id });

        Test.startTest();
        List<neuraFormBuilderController.CatalogMatch> matches =
            neuraFormBuilderController.findSimilarCatalogEntries('Service', 5, unscoped.Id);
        Test.stopTest();

        Set<Id> returned = new Set<Id>();
        for (neuraFormBuilderController.CatalogMatch m : matches) returned.add(m.id);
        System.assert(returned.contains(universal.Id));
        System.assert(!returned.contains(chainA.Id),
            'Unscoped template should not see scoped entries');
    }

    @isTest
    static void testProcessQuestionRecords_preLinkedBindingSkipsAutoCreate() {
        // Wave 35.9b adoption flow: a brand-new Form_Question__c
        // inserted with Form_Question_Catalog__c already set must NOT
        // trigger autoCreateCatalogForNewBindings — otherwise adopting
        // an existing catalog entry would silently spawn a duplicate.
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];
        Form_Page__c page = [SELECT Id FROM Form_Page__c WHERE Form_Template__c = :ft.Id LIMIT 1];
        Form_Section__c section = [SELECT Id FROM Form_Section__c WHERE Form_Template__c = :ft.Id LIMIT 1];

        Form_Question_Catalog__c existing = new Form_Question_Catalog__c(
            External_Reference__c = 'prelink-existing-cat',
            Question__c = 'Existing catalog',
            Type__c = 'Text'
        );
        insert existing;

        Integer catalogCountBefore = [SELECT COUNT() FROM Form_Question_Catalog__c];

        Form_Question__c newBinding = new Form_Question__c(
            Order__c = 99,
            Form_Template__c = ft.Id,
            Form_Section__c = section.Id,
            Form_Page__c = page.Id,
            Form_Question_Catalog__c = existing.Id
        );

        Test.startTest();
        neuraFormBuilderController.processQuestionRecords(
            new List<Form_Question__c>{ newBinding },
            new List<Form_Question__c>(),
            new List<Id>()
        );
        Test.stopTest();

        Integer catalogCountAfter = [SELECT COUNT() FROM Form_Question_Catalog__c];
        System.assertEquals(catalogCountBefore, catalogCountAfter,
            'Pre-linked binding must not spawn a new catalog entry');

        Form_Question__c saved = [
            SELECT Form_Question_Catalog__c FROM Form_Question__c
            WHERE Id = :newBinding.Id
        ];
        System.assertEquals(existing.Id, saved.Form_Question_Catalog__c,
            'Pre-linked binding should retain its catalog reference after insert');
    }

    @isTest
    static void testProcessQuestionRecords_overrideBlocksSync() {
        // Binding has exclusive catalog (count == 1) BUT also has an
        // Override_Question__c set. The sync should NOT happen because
        // the override is the explicit per-template channel.
        enableCatalog();
        Form_Template__c ft = [SELECT Id FROM Form_Template__c LIMIT 1];
        Form_Question__c b = [
            SELECT Id FROM Form_Question__c WHERE Form_Template__c = :ft.Id LIMIT 1
        ];

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'cat-override-blocks-sync',
            Question__c = 'Catalog default', Type__c = 'Text'
        );
        insert cat;
        b.Form_Question_Catalog__c = cat.Id;
        b.Override_Question__c = 'Override text';
        update b;

        // Now admin edits the binding's Question__c (legacy field).
        // Override is set so the sync should be skipped.
        b.Question__c = 'Stale binding edit';

        Test.startTest();
        neuraFormBuilderController.processQuestionRecords(
            new List<Form_Question__c>(),
            new List<Form_Question__c>{b},
            new List<Id>()
        );
        Test.stopTest();

        Form_Question_Catalog__c after = [
            SELECT Question__c FROM Form_Question_Catalog__c WHERE Id = :cat.Id
        ];
        System.assertEquals('Catalog default', after.Question__c,
            'Override on the binding should prevent Question__c from syncing to catalog');
    }

    @isTest
    static void createCatalogEntryForBindingPromotesAndLinks() {
        Form_Question__c q = [SELECT Id FROM Form_Question__c LIMIT 1];

        Test.startTest();
        Id catId = neuraFormBuilderController.createCatalogEntryForBinding(q.Id);
        Test.stopTest();

        System.assertNotEquals(null, catId);
        Form_Question__c after = [
            SELECT Form_Question_Catalog__c FROM Form_Question__c WHERE Id = :q.Id
        ];
        System.assertEquals(catId, after.Form_Question_Catalog__c,
            'The binding must adopt the new catalog entry.');
        Form_Question_Catalog__c cat = [
            SELECT Question__c FROM Form_Question_Catalog__c WHERE Id = :catId
        ];
        System.assertEquals('Test Question?', cat.Question__c,
            'Catalog content is copied from the binding.');
    }

    @isTest
    static void scoringSummarySumsCatalogWeights() {
        Form_Template__c tpl = [SELECT Id FROM Form_Template__c LIMIT 1];
        tpl.Scoring_Enabled__c = true;
        tpl.Max_Score__c = 100;
        update tpl;
        Form_Question__c q = [SELECT Id FROM Form_Question__c LIMIT 1];
        Id catId = neuraFormBuilderController.createCatalogEntryForBinding(q.Id);
        update new Form_Question_Catalog__c(Id = catId, Weight__c = 25);

        Test.startTest();
        neuraFormBuilderController.ScoringSummary s =
            neuraFormBuilderController.getScoringSummary(tpl.Id);
        Test.stopTest();

        System.assertEquals(true, s.scoringEnabled);
        System.assertEquals(25, s.weightSum, 'Weight comes from the linked catalog entry.');
        System.assertEquals(100, s.declaredMaxScore);
        System.assertEquals(1, s.scoredQuestionCount);
        System.assertEquals(0, s.unscoredQuestionCount);
    }

    @isTest
    static void createCatalogEntryForBindingIsIdempotent() {
        Form_Question__c q = [SELECT Id FROM Form_Question__c LIMIT 1];
        Id first = neuraFormBuilderController.createCatalogEntryForBinding(q.Id);
        Id second = neuraFormBuilderController.createCatalogEntryForBinding(q.Id);
        System.assertEquals(first, second,
            'Already-linked bindings return the existing entry instead of duplicating.');
    }
}