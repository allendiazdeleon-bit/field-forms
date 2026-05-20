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
}