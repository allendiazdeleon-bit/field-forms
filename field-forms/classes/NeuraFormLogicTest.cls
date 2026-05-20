@isTest
public class NeuraFormLogicTest {
    @isTest
    static void testProcessTemplates() {
        Form_Template__c template = createFormTempData();
        
        createTestData(template.Id);
        
        Test.startTest();
        NeuraFormLogic.processTemplates(new Set<Id>{template.Id});
        Test.stopTest();
    }
    
    @isTest
    static void testUpdateJSON() {
        Form_Template__c template = createFormTempData();
        
        createTestData(template.Id);
        
        Test.startTest();
        NeuraFormLogic.updateJSON(new Map<Id, Form_Template__c>{template.Id => template});
        Test.stopTest();
    }
    
    @isTest
    static void testUploadFilesForAnswerRecord() {
        Form_Template__c template = createFormTempData();
        
        Map<Object, Object> file = new Map<Object, Object>{
            'data' => 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD/4QAYRXhpZgAATU0AKgAAAAgAAgESAAMAAAABAAEAAIdpAAQAAAABAAAAJgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAMKADAAQAAAABAAAAIgAAAAD/2wBDAAYEBQYFBAcGBQYIBwcIChELCgkJChUPEAwRGBUaGRgVGBcbHichGx0lHRcYIi4iJSgpKywrGiAvMy',
            'fileName' => 'Test_file.png',
            'description' => 'Completed'
        };
                    
        NeuraFileWrapper wrapper = new NeuraFileWrapper();
        
        wrapper.linkedEntityId = template.Id;
        wrapper.filesData = new List<Object>{file};
        
        Test.startTest();
        NeuraFormLogic.uploadFilesForAnswerRecords(new List<NeuraFileWrapper>{wrapper});
        Test.stopTest();
    }
    
    static Form_Template__c createFormTempData() {
        Form_Template__c temp = new Form_Template__c(
            Name='Test Temp'
        );
        insert temp;
        
        return temp;
    }
    
    static void createTestData(Id formTemplateId) {
        Form_Page__c page = new Form_Page__c(
            Form_Template__c=formTemplateId,
            Order__c=1,
            Title__c='Test Page'
        );
        insert page;
        
        Form_Section__c section = new Form_Section__c(
            Form_Template__c=formTemplateId,
            Form_Page__c=page.Id,
            Name='Test Section'
        );
        insert section;
        
        Form_Question__c question = new Form_Question__c(
            Form_Template__c=formTemplateId,
            Form_Page__c=page.Id,
            Form_Section__c=section.Id,
            Question__c='Test Question'
        );
        insert question;
    }
}