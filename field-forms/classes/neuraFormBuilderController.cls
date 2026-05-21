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
        if (formTemplateId == null) {
            return null;
        }
        // LIMIT 1 + list assignment so an unknown / soft-deleted Id returns
        // null instead of throwing QueryException at the client.
        List<Form_Template__c> templates = [
            SELECT Id, Name, Indicator_Type__c
            FROM Form_Template__c
            WHERE Id = :formTemplateId
            LIMIT 1
        ];
        if (templates.isEmpty()) {
            return null;
        }
        Form_Template__c ft = templates[0];
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
        // Wrap every DML so the actual error message reaches the LWC. Raw
        // DmlException propagates as a generic "Script-thrown exception" /
        // "Unknown error" - useless when an admin is trying to find the bad
        // record. We rethrow as AuraHandledException with .setMessage() so
        // the LWC's catch block sees the real cause.
        try {
            if (toDelete != null && toDelete.size() > 0) {
                deleteRecordsFromList(toDelete);
            }
            if (toCreate != null && toCreate.size() > 0) {
                insert toCreate;
            }
            if (toUpdate != null && toUpdate.size() > 0) {
                update toUpdate;
            }
            return toCreate;
        } catch (DmlException e) {
            String msg = e.getMessage();
            // For each failed row, append the field-level detail. DmlException
            // exposes per-row errors via getDmlMessage / getDmlFields.
            List<String> rowDetails = new List<String>();
            for (Integer i = 0; i < e.getNumDml(); i++) {
                String fields = e.getDmlFields(i) != null
                    ? String.join(e.getDmlFieldNames(i), ', ')
                    : '';
                rowDetails.add(
                    'Row ' + i + ': ' + e.getDmlMessage(i)
                    + (String.isNotBlank(fields) ? ' (fields: ' + fields + ')' : '')
                );
            }
            String full = String.isNotBlank(msg) ? msg : 'DML error';
            if (!rowDetails.isEmpty()) {
                full += ' - ' + String.join(rowDetails, '; ');
            }
            AuraHandledException ahe = new AuraHandledException(full);
            ahe.setMessage(full);
            throw ahe;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }
    @AuraEnabled(cacheable=false)
    public static Form_Template__c processFormRecord(Form_Template__c toCreate, Form_Template__c toUpdate){
        try {
            if (toCreate != null) {
                insert toCreate;
                return toCreate;
            }
            if (toUpdate != null) {
                update toUpdate;
                return toUpdate;
            }
            return null;
        } catch (Exception e) {
            // Same pattern as processFormUpdate - rethrow as AuraHandledException
            // with setMessage so the LWC sees the real error.
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
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
        // allOrNone=false so partial-success reporting actually works; with
        // allOrNone=true, any failure throws DmlException and the per-result
        // error loop below never executes. The first failure is rethrown as
        // an AuraHandledException so the LWC sees a usable error message.
        Database.DeleteResult[] deleteResults = Database.delete(toDeleteIds, false);
        List<String> errorMessages = new List<String>();
        for (Database.DeleteResult dr : deleteResults) {
            if (!dr.isSuccess()) {
                for (Database.Error err : dr.getErrors()) {
                    String msg = err.getStatusCode() + ': ' + err.getMessage()
                        + ' (fields: ' + err.getFields() + ')';
                    System.debug(LoggingLevel.ERROR, msg);
                    errorMessages.add(msg);
                }
            }
        }
        if (!errorMessages.isEmpty()) {
            throw new AuraHandledException(
                'Failed to delete ' + errorMessages.size() + ' record(s): '
                + String.join(errorMessages, '; ')
            );
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