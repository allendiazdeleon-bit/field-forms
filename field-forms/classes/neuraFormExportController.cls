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
     * Result of an import. Includes the imported template records plus
     * created/updated counts and any warnings that should be surfaced to the
     * admin (e.g. conditions referencing questions that weren't in the JSON).
     */
    public class ImportResult {
        @AuraEnabled public List<Form_Template__c> templates;
        @AuraEnabled public Integer createdCount = 0;
        @AuraEnabled public Integer updatedCount = 0;
        @AuraEnabled public List<String> warnings = new List<String>();
    }

    /**
     * Imports form templates from a JSON string. Wraps every DML in a single
     * Savepoint so a failure at any step (templates / pages / sections /
     * questions / conditions rewrite) rolls back the whole import - no more
     * orphan half-imported templates.
     *
     * Snapshot rebuild is run synchronously at the end (inside the same
     * transaction) so the LWC doesn't have to issue a second Apex call and
     * the new templates render immediately.
     *
     * Returns an ImportResult (not raw templates) so the LWC can surface
     * created/updated counts and any non-fatal warnings (e.g. condition
     * references that couldn't be resolved).
     */
    @AuraEnabled(cacheable=false)
    public static ImportResult importTemplates(String jsonContent) {
        return importTemplatesInternal(jsonContent, /* importAsNew */ false);
    }

    private static ImportResult importTemplatesInternal(String jsonContent, Boolean importAsNew) {
        if (String.isBlank(jsonContent)) {
            AuraHandledException e = new AuraHandledException('Import payload was empty.');
            e.setMessage('Import payload was empty.');
            throw e;
        }

        List<FormTemplateWrapper> wrappers;
        try {
            wrappers = (List<FormTemplateWrapper>) JSON.deserialize(
                jsonContent, List<FormTemplateWrapper>.class
            );
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(
                'Could not parse import JSON: ' + e.getMessage()
            );
            ahe.setMessage('Could not parse import JSON: ' + e.getMessage());
            throw ahe;
        }
        if (wrappers == null || wrappers.isEmpty()) {
            AuraHandledException e = new AuraHandledException('No templates in payload.');
            e.setMessage('No templates in payload.');
            throw e;
        }

        ImportResult result = new ImportResult();
        String externalReferenceField = NeuraFormUtils.getNamespacePrefix() + 'External_Reference__c';

        // Single Savepoint so a failure at any step rolls back the entire
        // import. Previously a section-upsert failure left templates+pages
        // committed and pointing nowhere.
        Savepoint sp = Database.setSavepoint();
        try {
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

            // "Import as new" regenerates External_Reference__c on every
            // record so the upsert creates fresh rows instead of overwriting
            // any existing rows that share the source-org Id. Caller passes
            // true via importTemplatesAsNew().
            if (importAsNew) {
                regenerateExternalReferences(templates, pages, sections, questions, externalReferenceField);
            }

            // Track created vs. updated by checking Id presence before upsert.
            // upsert with an external key returns Database.UpsertResult[] when
            // the typed wrapper isn't used, so we use the Database.upsert
            // overload to capture per-row outcomes.
            Schema.SObjectField extRefSchema = Form_Template__c.SObjectType
                .getDescribe().fields.getMap().get(externalReferenceField);
            Database.UpsertResult[] tplResults = Database.upsert(templates, extRefSchema, false);
            throwOnFailures(tplResults, 'Form Template');
            for (Database.UpsertResult r : tplResults) {
                if (r.isCreated()) result.createdCount++;
                else result.updatedCount++;
            }
            Map<String, Id> templateIdMap = createIdMap(templates, externalReferenceField);

            for (Form_Page__c page : pages) {
                page.Form_Template__c = templateIdMap.get((String) page.Form_Template__c);
            }
            Schema.SObjectField pageExt = Form_Page__c.SObjectType
                .getDescribe().fields.getMap().get(externalReferenceField);
            Database.UpsertResult[] pageResults = Database.upsert(pages, pageExt, false);
            throwOnFailures(pageResults, 'Form Page');
            Map<String, Id> pageIdMap = createIdMap(pages, externalReferenceField);

            for (Form_Section__c section : sections) {
                section.Form_Template__c = templateIdMap.get((String) section.Form_Template__c);
                section.Form_Page__c = pageIdMap.get((String) section.Form_Page__c);
            }
            Schema.SObjectField sectionExt = Form_Section__c.SObjectType
                .getDescribe().fields.getMap().get(externalReferenceField);
            Database.UpsertResult[] sectionResults = Database.upsert(sections, sectionExt, false);
            throwOnFailures(sectionResults, 'Form Section');
            Map<String, Id> sectionIdMap = createIdMap(sections, externalReferenceField);

            for (Form_Question__c question : questions) {
                question.Form_Template__c = templateIdMap.get((String) question.Form_Template__c);
                question.Form_Section__c = sectionIdMap.get((String) question.Form_Section__c);
                question.Form_Page__c = pageIdMap.get((String) question.Form_Page__c);
            }
            Schema.SObjectField questionExt = Form_Question__c.SObjectType
                .getDescribe().fields.getMap().get(externalReferenceField);
            Database.UpsertResult[] questionResults = Database.upsert(questions, questionExt, false);
            throwOnFailures(questionResults, 'Form Question');
            Map<String, Id> questionIdMap = createIdMap(questions, externalReferenceField);

            // Second pass: rewrite Conditions JSON references from the source
            // org's Ids/UUIDs to the new org's Ids. Track which records
            // actually changed so we don't issue a no-op DML wave.
            List<Form_Page__c> changedPages = new List<Form_Page__c>();
            for (Form_Page__c page : pages) {
                CriteriaRewriteResult r = modifyCriteriaWithResult(
                    page.Conditions__c, pageIdMap, sectionIdMap, questionIdMap
                );
                if (r.changed) {
                    page.Conditions__c = r.json;
                    changedPages.add(page);
                }
                result.warnings.addAll(r.warnings);
            }
            List<Form_Section__c> changedSections = new List<Form_Section__c>();
            for (Form_Section__c section : sections) {
                CriteriaRewriteResult r = modifyCriteriaWithResult(
                    section.Conditions__c, pageIdMap, sectionIdMap, questionIdMap
                );
                if (r.changed) {
                    section.Conditions__c = r.json;
                    changedSections.add(section);
                }
                result.warnings.addAll(r.warnings);
            }
            List<Form_Question__c> changedQuestions = new List<Form_Question__c>();
            for (Form_Question__c question : questions) {
                CriteriaRewriteResult r = modifyCriteriaWithResult(
                    question.Conditions__c, pageIdMap, sectionIdMap, questionIdMap
                );
                if (r.changed) {
                    question.Conditions__c = r.json;
                    changedQuestions.add(question);
                }
                result.warnings.addAll(r.warnings);
            }

            if (!changedPages.isEmpty()) update changedPages;
            if (!changedSections.isEmpty()) update changedSections;
            if (!changedQuestions.isEmpty()) update changedQuestions;

            // Rebuild the JSON snapshot fields synchronously inside the same
            // transaction so the LWC doesn't have to issue a second call and
            // the new templates render immediately. The trigger pipeline may
            // also enqueue an async snapshot job; that's a harmless duplicate.
            Set<Id> templateIds = new Set<Id>();
            for (Form_Template__c t : templates) templateIds.add(t.Id);
            if (!templateIds.isEmpty()) {
                NeuraFormLogic.processTemplates(templateIds);
            }

            result.templates = templates;
            return result;
        } catch (Exception e) {
            Database.rollback(sp);
            System.debug(LoggingLevel.ERROR, 'Import rolled back: ' + e.getMessage());
            System.debug(LoggingLevel.ERROR, e.getStackTraceString());
            AuraHandledException ahe = new AuraHandledException(
                'Import failed and was rolled back: ' + e.getMessage()
            );
            ahe.setMessage('Import failed and was rolled back: ' + e.getMessage());
            throw ahe;
        }
    }

    /**
     * Import variant that creates new templates instead of overwriting any
     * existing ones that share the source-org Id via External_Reference__c.
     * Each record's external reference is regenerated to a UUID-like value
     * before the upsert.
     */
    @AuraEnabled(cacheable=false)
    public static ImportResult importTemplatesAsNew(String jsonContent) {
        return importTemplatesInternal(jsonContent, /* importAsNew */ true);
    }

    private static void regenerateExternalReferences(
        List<Form_Template__c> templates,
        List<Form_Page__c> pages,
        List<Form_Section__c> sections,
        List<Form_Question__c> questions,
        String externalReferenceField
    ) {
        // Map old reference -> new reference so we can rewrite FK strings on
        // children before upsert.
        Map<String, String> remap = new Map<String, String>();
        for (SObject record : (List<SObject>) templates) remap.put((String) record.get(externalReferenceField), freshRef('t'));
        for (SObject record : (List<SObject>) pages)     remap.put((String) record.get(externalReferenceField), freshRef('p'));
        for (SObject record : (List<SObject>) sections)  remap.put((String) record.get(externalReferenceField), freshRef('s'));
        for (SObject record : (List<SObject>) questions) remap.put((String) record.get(externalReferenceField), freshRef('q'));

        for (Form_Template__c t : templates) t.put(externalReferenceField, remap.get((String) t.get(externalReferenceField)));
        for (Form_Page__c p : pages) {
            p.put(externalReferenceField, remap.get((String) p.get(externalReferenceField)));
            p.Form_Template__c = remap.get((String) p.Form_Template__c);
        }
        for (Form_Section__c s : sections) {
            s.put(externalReferenceField, remap.get((String) s.get(externalReferenceField)));
            s.Form_Template__c = remap.get((String) s.Form_Template__c);
            s.Form_Page__c = remap.get((String) s.Form_Page__c);
        }
        for (Form_Question__c q : questions) {
            q.put(externalReferenceField, remap.get((String) q.get(externalReferenceField)));
            q.Form_Template__c = remap.get((String) q.Form_Template__c);
            q.Form_Section__c = remap.get((String) q.Form_Section__c);
            q.Form_Page__c = remap.get((String) q.Form_Page__c);
        }
    }

    private static String freshRef(String prefix) {
        return 'IMP_' + prefix + '_' + Crypto.getRandomLong() + '_' + System.currentTimeMillis();
    }

    private static void throwOnFailures(Database.UpsertResult[] results, String label) {
        List<String> errors = new List<String>();
        for (Database.UpsertResult r : results) {
            if (!r.isSuccess()) {
                for (Database.Error err : r.getErrors()) {
                    errors.add(label + ': ' + err.getStatusCode() + ' - ' + err.getMessage());
                }
            }
        }
        if (!errors.isEmpty()) {
            throw new DmlException(String.join(errors, '; '));
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

    /**
     * Carries the result of a single condition-string rewrite: the new JSON,
     * a flag for whether anything actually changed (so callers can skip the
     * DML when it didn't), and any warnings (e.g. references that couldn't
     * be resolved).
     */
    public class CriteriaRewriteResult {
        public String json;
        public Boolean changed = false;
        public List<String> warnings = new List<String>();
    }

    /**
     * Backwards-compat shim. The original modifyCriteria silently put null
     * for missing references, which produced runtime-broken conditions.
     * Prefer modifyCriteriaWithResult, which surfaces those misses to the
     * caller and only flags the row as changed when at least one rewrite
     * succeeded.
     */
    public static String modifyCriteria(String jsonString, Map<String, Id> pageMap, Map<String,Id> sectionMap, Map<String,Id> questionMap) {
        return modifyCriteriaWithResult(jsonString, pageMap, sectionMap, questionMap).json;
    }

    public static CriteriaRewriteResult modifyCriteriaWithResult(
        String jsonString,
        Map<String, Id> pageMap,
        Map<String, Id> sectionMap,
        Map<String, Id> questionMap
    ) {
        CriteriaRewriteResult result = new CriteriaRewriteResult();
        result.json = jsonString;
        if (String.isBlank(jsonString)) return result;

        Map<String, Object> logicMap;
        try {
            logicMap = (Map<String, Object>) JSON.deserializeUntyped(jsonString);
        } catch (Exception e) {
            result.warnings.add('Could not parse condition JSON; left unchanged: ' + e.getMessage());
            return result;
        }

        List<Object> conditions = (List<Object>) logicMap.get('conditions');
        if (conditions == null) return result;

        for (Object conditionObj : conditions) {
            Map<String, Object> conditionMap = (Map<String, Object>) conditionObj;

            if (conditionMap.containsKey('resource') && conditionMap.get('resource') instanceof String) {
                String oldRef = (String) conditionMap.get('resource');
                Id newId = questionMap.get(oldRef);
                if (newId != null) {
                    conditionMap.put('resource', newId);
                    result.changed = true;
                } else if (String.isNotBlank(oldRef)) {
                    // Leave the old value in place so we don't write null into
                    // a condition that the renderer will try to evaluate.
                    result.warnings.add(
                        'Condition references a question (' + oldRef + ') that was not in the import. ' +
                        'The condition will not evaluate correctly until the missing record is added.'
                    );
                }
            }

            if (conditionMap.containsKey('page') && conditionMap.get('page') instanceof String) {
                String oldRef = (String) conditionMap.get('page');
                Id newId = pageMap.get(oldRef);
                if (newId != null) {
                    conditionMap.put('page', newId);
                    result.changed = true;
                } else if (String.isNotBlank(oldRef)) {
                    result.warnings.add(
                        'Condition references a page (' + oldRef + ') that was not in the import.'
                    );
                }
            }

            if (conditionMap.containsKey('section') && conditionMap.get('section') instanceof String) {
                String oldRef = (String) conditionMap.get('section');
                Id newId = sectionMap.get(oldRef);
                if (newId != null) {
                    conditionMap.put('section', newId);
                    result.changed = true;
                } else if (String.isNotBlank(oldRef)) {
                    result.warnings.add(
                        'Condition references a section (' + oldRef + ') that was not in the import.'
                    );
                }
            }
        }

        if (result.changed) {
            result.json = JSON.serialize(logicMap);
        }
        return result;
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

}