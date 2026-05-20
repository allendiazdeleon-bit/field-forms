public with sharing class neuraFormExportController {

    //Exclude Fields that are not required
    private static final Set<String> EXCLUDEDFIELDS = new Set<String> {
        'ownerid', 'createdbyid', 'isdeleted', 'lastmodifiedbyid', 'createddate', 'lastmodifieddate', 'systemmodstamp', 'lastvieweddate', 'lastreferenceddate'
    };

    private static final Set<String> EXCLUDEDCUSTOMFIELDS = new Set<String> {
        'pages_json__c', 'sections_json__c', 'questions_json__c', 'page_conditions__c', 'section_conditions__c', 'question_conditions__c'
    };

    @AuraEnabled(cacheable=false)
    public static String fetchTemplatesData(List<String> templateIds) {
        try{
            // Fetch templates
            List<Form_Template__c> templates = Database.query('SELECT ' + generateFieldList('Form_Template__c') + ' FROM Form_Template__c WHERE Id IN :templateIds');
            
            // Fetch pages
            List<Form_Page__c> pages = Database.query('SELECT ' + generateFieldList('Form_Page__c') + ' FROM Form_Page__c WHERE Form_Template__c IN :templateIds');
            
            // Fetch sections
            List<Form_Section__c> sections = Database.query('SELECT ' + generateFieldList('Form_Section__c') + ' FROM Form_Section__c WHERE Form_Template__c IN :templateIds');
            
            // Fetch questions
            List<Form_Question__c> questions = Database.query('SELECT ' + generateFieldList('Form_Question__c') + ' FROM Form_Question__c WHERE Form_Template__c IN :templateIds'); 
            
            // Create maps to store related objects by template ID
            Map<Id, List<Form_Page__c>> templateIdToPagesMap = new Map<Id, List<Form_Page__c>>();
            Map<Id, List<Form_Section__c>> templateIdToSectionsMap = new Map<Id, List<Form_Section__c>>();
            Map<Id, List<Form_Question__c>> templateIdToQuestionsMap = new Map<Id, List<Form_Question__c>>();
        
            // Initialize maps
            for (Form_Template__c template : templates) {
                templateIdToPagesMap.put(template.Id, new List<Form_Page__c>());
                templateIdToSectionsMap.put(template.Id, new List<Form_Section__c>());
                templateIdToQuestionsMap.put(template.Id, new List<Form_Question__c>());
            }
        
            // Populate the maps with related records
            for (Form_Page__c page : pages) {
                templateIdToPagesMap.get(page.Form_Template__c).add(page);
            }
            for (Form_Section__c section : sections) {
                templateIdToSectionsMap.get(section.Form_Template__c).add(section);
            }
            for (Form_Question__c question : questions) {
                templateIdToQuestionsMap.get(question.Form_Template__c).add(question);
            }
        
            // Create a list of FormTemplateWrapper instances
            List<FormTemplateWrapper> wrappers = new List<FormTemplateWrapper>();
            for (Form_Template__c template : templates) {
                Id tempId = template.Id;
                wrappers.add(new FormTemplateWrapper(
                    (Form_Template__c) addExternalIdValue(template),
                    (List<Form_Page__c>) addExternalIdValues(templateIdToPagesMap.get(tempId)),
                    (List<Form_Section__c>) addExternalIdValues(templateIdToSectionsMap.get(tempId)),
                    (List<Form_Question__c>) addExternalIdValues(templateIdToQuestionsMap.get(tempId))
                ));
            }
        
            return JSON.serialize(wrappers);
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public static SObject addExternalIdValue(SObject record){
        String externalReferenceField = NeuraFormUtils.getNamespacePrefix() + 'External_Reference__c';

        if (record.get(externalReferenceField) == null) {
            record.put(externalReferenceField, record.Id);
        }

        record.put('Id', null);

        return record;
    }

    public static List<SObject> addExternalIdValues(List<SObject> records) {
        List<SObject> newRecords = new List<SObject>();
        for(SObject record : records) {
            newRecords.add(addExternalIdValue(record));
        }
        return newRecords;
    }


    public static List<Form_Template__c> addExternalIdValuesOld(List<Form_Template__c> templates) {
        for (Form_Template__c template : templates) {
            if (template.External_Reference__c == null) {
                template.External_Reference__c = template.Id;
            }
            template.Id = null;
            for (Form_Page__c page : template.Form_Pages__r) {
                if (page.External_Reference__c == null) {
                    page.External_Reference__c = page.Id;
                }
                page.Id = null;
            }
            for (Form_Section__c section : template.Form_Sections__r) {
                if (section.External_Reference__c == null) {
                    section.External_Reference__c = section.Id;
                }
                section.Id = null;
            }
            for(Form_Question__c question : template.Form_Questions__r) {
                if (question.External_Reference__c == null) {
                    question.External_Reference__c = question.Id;
                }
                question.Id = null;
            }
        }
        return templates;
    }


    public static String generateFieldList(String objectName) {
        // add namespace to the objectName
        objectName = NeuraFormUtils.getNamespacePrefix() + objectName;
        Map<String, Schema.SObjectField> fieldMap = Schema.getGlobalDescribe().get(objectName).getDescribe().fields.getMap();
        List<String> fieldList = new List<String>(fieldMap.keySet());

        // add namespace to the excluded custom fields if they exist.
        Set<String> nameSpaceExcludedFields = new Set<String>();
        for (String nsExcludedField : EXCLUDEDCUSTOMFIELDS) {
            nameSpaceExcludedFields.add(NeuraFormUtils.getNamespacePrefix() + nsExcludedField);
        }

        List<String> standardFieldsRemoved = removeStrings(fieldList, EXCLUDEDFIELDS);
        
        // adding this just incase namespace is not needed
        standardFieldsRemoved = removeStrings(standardFieldsRemoved, EXCLUDEDCUSTOMFIELDS);

        List<String> customFieldsRemoved = removeStrings(standardFieldsRemoved, nameSpaceExcludedFields);

        return String.join(customFieldsRemoved, ', ');
    }
    /**
     * Imports form templates from a JSON string.
     * 
     * @param jsonContent The JSON string containing form templates and related objects.
     * @return A list of imported Form_Template__c records.
     * @throws AuraHandledException If any error occurs during the import process.
     */
    @AuraEnabled(cacheable=false)
    public static List<Form_Template__c> importTemplates(String jsonContent){
        try {
            List<FormTemplateWrapper> wrappers = (List<FormTemplateWrapper>) JSON.deserialize(jsonContent, List<FormTemplateWrapper>.class);
            String externalReferenceField = NeuraFormUtils.getNamespacePrefix() + 'External_Reference__c';
            // Build a list of each type of object to upsert
            List<Form_Template__c> templates = new List<Form_Template__c>();
            List<Form_Page__c> pages = new List<Form_Page__c>();
            List<Form_Section__c> sections = new List<Form_Section__c>();
            List<Form_Question__c> questions = new List<Form_Question__c>();

            for (FormTemplateWrapper wrapper : wrappers) {
                templates.add(wrapper.template);
                pages.addAll(wrapper.pages);
                sections.addAll(wrapper.sections);
                questions.addAll(wrapper.questions);
            }

            upsert templates Form_Template__c.External_Reference__c;
            Map<String, Id> templateIdMap = createIdMap(templates, externalReferenceField);


            for (Form_Page__c page : pages) {

                page.Form_Template__c = templateIdMap.get(page.Form_Template__c); // Set the reference to the new template ID
            }

            upsert pages Form_Page__c.External_Reference__c;

            Map<String, Id> pageIdMap = createIdMap(pages, externalReferenceField);


            for (Form_Section__c section : sections) {
                section.Form_Template__c = templateIdMap.get(section.Form_Template__c); // Set the reference to the new template ID
                section.Form_Page__c = pageIdMap.get(section.Form_Page__c); // Set the reference to the new page ID
            }

            upsert sections Form_Section__c.External_Reference__c;
            Map<String, Id> sectionIdMap = createIdMap(sections, externalReferenceField);
            
            for(Form_Question__c question : questions){
                question.Form_Template__c = templateIdMap.get(question.Form_Template__c); // Set the reference to the new template ID
                question.Form_Section__c = sectionIdMap.get(question.Form_Section__c); // Set the reference to the new section ID
                question.Form_Page__c = pageIdMap.get(question.Form_Page__c); // Set the reference to the new page ID

            }

            upsert questions Form_Question__c.External_Reference__c;
            Map<String, Id> questionIdMap = createIdMap(questions, externalReferenceField);

            // TODO: Now we need to go through all the questions, sections, and pages to determine if we need to update the criteria fields.
            for(Form_Page__c page : pages){
                page.Conditions__c = modifyCriteria(page.Conditions__c, pageIdMap, sectionIdMap, questionIdMap);
            }

            for (Form_Section__c section: sections){
                section.Conditions__c = modifyCriteria(section.Conditions__c, pageIdMap, sectionIdMap, questionIdMap);
            }

            for(Form_Question__c question: questions){
                question.Conditions__c = modifyCriteria(question.Conditions__c, pageIdMap, sectionIdMap, questionIdMap);
            }

            update pages;
            update sections;
            update questions;

            return templates;
        } catch (Exception e) {
            System.debug('Error: ' + e.getMessage());
            System.debug('Stack Trace: ' + e.getStackTraceString());
            throw new AuraHandledException(e.getMessage());
        }
    }

    /**
     * Creates a map of external references to record IDs.
     * 
     * @param records The list of records.
     * @param externalRefField The external reference field used for mapping.
     * @return A map of external references to record IDs.
     */
    private static Map<String, Id> createIdMap(List<SObject> records, String externalRefField) {
        Map<String, Id> idMap = new Map<String, Id>();
        for (SObject record : records) {
            idMap.put((String) record.get(externalRefField), record.Id);
        }
        return idMap;
    }

            

    @AuraEnabled(cacheable=false)
    public static Boolean runTemplateRollup(List<String> formTemplateIdsList){
        try {
            // build a list of Ids
            Set<Id> formTemplateIds = new Set<Id>();
            for(String formTemplateId : formTemplateIdsList) {
                formTemplateIds.add((Id) formTemplateId);
            }

            NeuraFormLogic.processTemplates(formTemplateIds);
            return true;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    public static String modifyCriteria(String jsonString, Map<String, Id> pageMap, Map<String,Id> sectionMap, Map<String,Id> questionMap) {

        if(String.isBlank(jsonString) || jsonString == null){
            return jsonString;
        }

        // Deserialize the JSON string into a Map
        Map<String, Object> logicMap = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
        
        // Access the conditions list
        List<Object> conditions = (List<Object>) logicMap.get('conditions');
        
        if (conditions != null) {
            // Iterate over each condition and modify the resource, page, and section values
            for (Object conditionObj : conditions) {
                Map<String, Object> conditionMap = (Map<String, Object>) conditionObj;
                
                if (conditionMap.containsKey('resource') && conditionMap.get('resource') instanceof String) {
                    conditionMap.put('resource', questionMap.get((String) conditionMap.get('resource')));
                }
                
                if (conditionMap.containsKey('page') && conditionMap.get('page') instanceof String) {
                    conditionMap.put('page', pageMap.get((String) conditionMap.get('page')));
                }
                
                if (conditionMap.containsKey('section') && conditionMap.get('section') instanceof String) {
                    conditionMap.put('section', sectionMap.get((String) conditionMap.get('section')));
                }
            }
        }
        
        // Serialize the modified map back to a JSON string
        String modifiedJsonString = JSON.serialize(logicMap);
        
        return modifiedJsonString;
    }

    /**
     * Removes all occurrences of any string in the removalList from the listToClean.
     * 
     * @param listToClean The list of strings to be cleaned.
     * @param removalList The list of strings that should be removed from listToClean.
     * @return List<String> A new list that has been cleaned of all removalList entries.
     */
    public static List<String> removeStrings(List<String> listToClean, Set<String> removalList) {
        List<String> cleanedList = new List<String>();
        for(String item : listToClean) {
            if (!removalList.contains(item)) {
                cleanedList.add(item);
            }
        }

        System.debug('Cleaned List: ' + cleanedList);
        return cleanedList;
    }

    // Create a wrapper class for Form Template with related objects
    public class FormTemplateWrapper {
        @AuraEnabled
        public Form_Template__c template;
        @AuraEnabled
        public List<Form_Page__c> pages;
        @AuraEnabled
        public List<Form_Section__c> sections;
        @AuraEnabled
        public List<Form_Question__c> questions;

        // constructor

        public FormTemplateWrapper(Form_Template__c template, List<Form_Page__c> pages, List<Form_Section__c> sections, List<Form_Question__c> questions) {
            this.template = template;
            this.pages = pages;
            this.sections = sections;
            this.questions = questions;
        }
    }

    public class CriteriaWrapper {

    }
}