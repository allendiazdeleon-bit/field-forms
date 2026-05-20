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
        List<Form_Template__c> templates = neuraFormExportController.importTemplates(jsonContent);
        Test.stopTest();
        
        // Asserts
        System.assertEquals(1, templates.size(), 'There should be one template processed');
        System.assertEquals(template.Id, templates[0].External_Reference__c, 'The external reference should match');
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