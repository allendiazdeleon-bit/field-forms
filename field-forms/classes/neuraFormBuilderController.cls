public with sharing class neuraFormBuilderController {
    @AuraEnabled(cacheable=true)
    public static List<Form_Setting_to_Field__mdt> getAllAttributes() {
        List<Form_Setting_to_Field__mdt> formSettingToField = [SELECT MasterLabel, Form_Setting__r.Label, Form_Setting_Field__r.Label FROM Form_Setting_to_Field__mdt];
        
        // Create a new list to store modified results
        List<Form_Setting_to_Field__mdt> modifiedFormSettingToField = new List<Form_Setting_to_Field__mdt>();
        
        // Get the namespace prefix once
        String namespacePrefix = NeuraFormUtils.getNamespacePrefix();
        
        for (Form_Setting_to_Field__mdt fsf : formSettingToField) {
            // Create a deep copy of the object to modify
            Form_Setting_to_Field__mdt fsfCopy = fsf.clone(false, false, false, false);
            
            // Check if the Label already starts with the namespace prefix
            if (!fsfCopy.Form_Setting_Field__r.Label.startsWith(namespacePrefix)) {
                fsfCopy.Form_Setting_Field__r.Label = namespacePrefix + fsf.Form_Setting_Field__r.Label;
            }
            
            modifiedFormSettingToField.add(fsfCopy);
        }
        
        return modifiedFormSettingToField;
    }

    @AuraEnabled(cacheable=false)
    public static FormWrapper getFormDetails(Id formTemplateId){
        Form_Template__c ft = [SELECT Id, Name, Indicator_Type__c FROM Form_Template__c WHERE Id = :formTemplateId];
        List<Form_Page__c> pages = [SELECT Id, Name, Order__c, Title__c, Form_Template__c, Conditions__c FROM Form_Page__c WHERE Form_Template__c = :ft.Id ORDER BY Order__c ASC];
       // List<Form_Section__c> sections = [SELECT Id, Name, Type__c, Title__c, Order__c, Form_Template__c, Form_Page__c, Columns__c, Sho FROM Form_Section__c WHERE Form_Template__c = :ft.Id ORDER BY Order__c ASC];
        
        SObjectType sectionObjectType = Form_Section__c.SObjectType;
        String sectionWhereClause = 'Form_Template__c = \'' + ft.Id + '\'';
        List<SObject> sections = dynamicQuery(sectionObjectType, sectionWhereClause);

        // Cast the result to the specific SObject type if needed
        List<Form_Section__c> formattedSections = (List<Form_Section__c>) sections;

        SObjectType questionObjectType = Form_Question__c.SObjectType;
        String questionWhereClause = 'Form_Template__c = \'' + ft.Id + '\'';
        List<SObject> questions = dynamicQuery(questionObjectType, questionWhereClause);

        // Cast the result to the specific SObject type if needed
        List<Form_Question__c> formattedQuestions = (List<Form_Question__c>) questions;
        
        //List<Form_Question__c> questions = [SELECT Id, Name, Type__c, Order__c, Question__c, Column__c, Form_Template__c, Form_Section__c, Form_Page__c, Value_Set__c, Required__c, Slider_Size__c, Min__c, Max__c, Slider_Step__c FROM Form_Question__c WHERE Form_Template__c = :ft.Id];

        return new FormWrapper(ft, pages, formattedSections, formattedQuestions);
    }

    private static List<SObject> dynamicQuery(SObjectType sObjectType, String whereClause) {
        // Get the metadata for the given SObjectType
        DescribeSObjectResult describeResult = sObjectType.getDescribe();

        // List to hold field names
        List<String> fieldNames = new List<String>();

        // Iterate over all fields and add them to the fieldNames list, excluding system fields
        for (Schema.SObjectField field : describeResult.fields.getMap().values()) {
            Schema.DescribeFieldResult fieldDescribe = field.getDescribe();

            // Check if the field is not a system field
            if (!fieldDescribe.isCalculated() && !fieldDescribe.isAutoNumber()) {
                // Add field name to the list
                fieldNames.add(fieldDescribe.getName());
            }
        }

        // Construct the dynamic query
        String queryString = 'SELECT ' + String.join(fieldNames, ', ') + ' FROM ' + sObjectType.getDescribe().getName();
        if (String.isNotBlank(whereClause)) {
            queryString += ' WHERE ' + whereClause;
        }

        queryString += ' ORDER BY Order__c ASC';

        // Execute the query and return the result
        return Database.query(queryString);
    }

    @AuraEnabled(cacheable=false)
    public static List<Form_Setting__mdt> getFormMetadata(){
        return [SELECT Id, Label, Icon__c, DeveloperName, MasterLabel, Structure__c, Display_Label__c, Order__c FROM Form_Setting__mdt ORDER BY Order__c ASC];
    }

    @AuraEnabled(cacheable=false)
    public static List<SObject> processFormUpdate(List<SObject> toCreate, List<SObject> toUpdate, List<Id> toDelete){
        
        // check if toDelete is not empty and not null
        if(toDelete != null && toDelete.size() > 0){
            deleteRecordsFromList(toDelete);
        }

        // check if toCreate is not empty and not null
        if(toCreate != null && toCreate.size() > 0){
            insert toCreate;
        }
        // check if toUpdate is not empty and not null
        if(toUpdate != null && toUpdate.size() > 0){
            update toUpdate;
        }
        return toCreate;
    }
    @AuraEnabled(cacheable=false)
    public static Form_Template__c processFormRecord(Form_Template__c toCreate, Form_Template__c toUpdate){
        if (toCreate != null) {
            insert toCreate;
            return toCreate;
        }
        if (toUpdate != null) {
            update toUpdate;
            return toUpdate;
        }
        return null; // In case both inputs are null
    }
    
    @AuraEnabled(cacheable=false)
    public static List<Form_Page__c> processPageRecords(List<Form_Page__c> toCreate, List<Form_Page__c> toUpdate, List<Id> toDelete){
        return (List<Form_Page__c>) processFormUpdate(toCreate, toUpdate, toDelete);
    }

    @AuraEnabled(cacheable=false)
    public static List<Form_Section__c> processSectionRecords(List<Form_Section__c> toCreate, List<Form_Section__c> toUpdate, List<Id> toDelete){
        return (List<Form_Section__c>) processFormUpdate(toCreate, toUpdate, toDelete);
    }

    @AuraEnabled(cacheable=false)
    public static List<Form_Question__c> processQuestionRecords(List<Form_Question__c> toCreate, List<Form_Question__c> toUpdate, List<Id> toDelete){
        return (List<Form_Question__c>) processFormUpdate(toCreate, toUpdate, toDelete);
    }

    public static void deleteRecordsFromList(List<Id> toDeleteIds){
        Database.DeleteResult[] deleteResults = Database.delete(toDeleteIds, true);
        for(Database.DeleteResult dr : deleteResults) {                   
            if (!dr.isSuccess()) {
                for(Database.Error err : dr.getErrors()) {
                    System.debug(LoggingLevel.Error, 'The following error has occurred.'
                        + '\n' + err.getStatusCode() + ': ' + err.getMessage()
                        + '\n fields that affected this error: ' + err.getFields());
                }
            }
        }
    }

    public class FormWrapper{
        @AuraEnabled
        public Form_Template__c formTemplate;
        @AuraEnabled
        public List<Form_Page__c> pages;
        @AuraEnabled
        public List<Form_Section__c> sections;
        @AuraEnabled
        public List<Form_Question__c> questions;

        public FormWrapper(Form_Template__c formTemplate, List<Form_Page__c> pages, List<Form_Section__c> sections, List<Form_Question__c> questions){
            this.formTemplate = formTemplate;
            this.pages = pages;
            this.sections = sections;
            this.questions = questions;
        }
    }


}