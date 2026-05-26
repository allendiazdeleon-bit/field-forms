public with sharing class neuraFormExportController {

    //Exclude Fields that are not required
    private static final Set<String> EXCLUDEDFIELDS = new Set<String> {
        'ownerid', 'createdbyid', 'isdeleted', 'lastmodifiedbyid', 'createddate', 'lastmodifieddate', 'systemmodstamp', 'lastvieweddate', 'lastreferenceddate'
    };

    private static final Set<String> EXCLUDEDCUSTOMFIELDS = new Set<String> {
        'pages_json__c', 'sections_json__c', 'questions_json__c', 'page_conditions__c', 'section_conditions__c', 'question_conditions__c'
    };

    // Hard cap on how many templates a single export can include. Larger
    // exports can blow past the SOQL row limit when their children (pages,
    // sections, questions) cascade. Picked conservatively; raise if real
    // customer use cases push past it.
    @TestVisible private static Integer EXPORT_TEMPLATE_LIMIT = 50;

    @AuraEnabled(cacheable=false)
    public static String fetchTemplatesData(List<String> templateIds) {
        try {
            if (templateIds == null || templateIds.isEmpty()) {
                throw new AuraHandledException('No templates selected.');
            }
            if (templateIds.size() > EXPORT_TEMPLATE_LIMIT) {
                throw new AuraHandledException(
                    'Export limit is ' + EXPORT_TEMPLATE_LIMIT + ' templates per file. ' +
                    'Select fewer templates and export in batches.'
                );
            }

            // Fetch each level, then strip any fields the running user can't
            // read (audit item I6). `with sharing` on the class enforces
            // record-level access; stripInaccessible adds field-level
            // enforcement on top.
            List<Form_Template__c> templates = Database.query(
                'SELECT ' + generateFieldList('Form_Template__c') +
                ' FROM Form_Template__c WHERE Id IN :templateIds'
            );
            templates = (List<Form_Template__c>) Security.stripInaccessible(
                AccessType.READABLE, templates
            ).getRecords();

            List<Form_Page__c> pages = Database.query(
                'SELECT ' + generateFieldList('Form_Page__c') +
                ' FROM Form_Page__c WHERE Form_Template__c IN :templateIds'
            );
            pages = (List<Form_Page__c>) Security.stripInaccessible(
                AccessType.READABLE, pages
            ).getRecords();

            List<Form_Section__c> sections = Database.query(
                'SELECT ' + generateFieldList('Form_Section__c') +
                ' FROM Form_Section__c WHERE Form_Template__c IN :templateIds'
            );
            sections = (List<Form_Section__c>) Security.stripInaccessible(
                AccessType.READABLE, sections
            ).getRecords();

            List<Form_Question__c> questions = Database.query(
                'SELECT ' + generateFieldList('Form_Question__c') +
                ' FROM Form_Question__c WHERE Form_Template__c IN :templateIds'
            );
            questions = (List<Form_Question__c>) Security.stripInaccessible(
                AccessType.READABLE, questions
            ).getRecords();

            Map<Id, List<Form_Page__c>> templateIdToPagesMap = new Map<Id, List<Form_Page__c>>();
            Map<Id, List<Form_Section__c>> templateIdToSectionsMap = new Map<Id, List<Form_Section__c>>();
            Map<Id, List<Form_Question__c>> templateIdToQuestionsMap = new Map<Id, List<Form_Question__c>>();

            for (Form_Template__c template : templates) {
                templateIdToPagesMap.put(template.Id, new List<Form_Page__c>());
                templateIdToSectionsMap.put(template.Id, new List<Form_Section__c>());
                templateIdToQuestionsMap.put(template.Id, new List<Form_Question__c>());
            }

            for (Form_Page__c page : pages) {
                templateIdToPagesMap.get(page.Form_Template__c).add(page);
            }
            for (Form_Section__c section : sections) {
                templateIdToSectionsMap.get(section.Form_Template__c).add(section);
            }
            for (Form_Question__c question : questions) {
                templateIdToQuestionsMap.get(question.Form_Template__c).add(question);
            }

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
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * Fallback when the export LWC's getListUi wire errors (e.g. the "All"
     * list view was deleted or restricted). Returns templates the running
     * user can see, capped at 200 to keep response sizes manageable.
     * cacheable=true so repeated calls don't re-hit SOQL.
     */
    @AuraEnabled(cacheable=true)
    public static List<Form_Template__c> listAccessibleTemplates() {
        return [
            SELECT Id, Name, External_Reference__c
            FROM Form_Template__c
            WITH SECURITY_ENFORCED
            ORDER BY Name ASC
            LIMIT 200
        ];
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
     * Returns a minimal valid wrapper JSON so admins can hand-edit a sample
     * to seed a new template instead of staring at a blank file.
     * cacheable=true; pure construction with no SOQL or DML.
     */
    @AuraEnabled(cacheable=true)
    public static String getSampleImportJson() {
        String ns = NeuraFormUtils.getNamespacePrefix();
        String extRef = ns + 'External_Reference__c';
        String fTpl = ns + 'Form_Template__c';
        String fPage = ns + 'Form_Page__c';
        String fSection = ns + 'Form_Section__c';
        String fOrder = ns + 'Order__c';
        String fTitle = ns + 'Title__c';
        String fColumns = ns + 'Columns__c';
        String fQuestion = ns + 'Question__c';
        String fType = ns + 'Type__c';

        Map<String, Object> template = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => ns + 'Form_Template__c' },
            'Name' => 'Sample Inspection',
            extRef => 'SAMPLE_TPL_1'
        };
        Map<String, Object> page = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => ns + 'Form_Page__c' },
            'Name' => 'Page 1',
            extRef => 'SAMPLE_P_1',
            fTpl => 'SAMPLE_TPL_1',
            fOrder => 1,
            fTitle => 'Page 1'
        };
        Map<String, Object> section = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => ns + 'Form_Section__c' },
            'Name' => 'Equipment',
            extRef => 'SAMPLE_S_1',
            fTpl => 'SAMPLE_TPL_1',
            fPage => 'SAMPLE_P_1',
            fOrder => 1,
            fTitle => 'Equipment',
            fColumns => '1'
        };
        Map<String, Object> question = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => ns + 'Form_Question__c' },
            'Name' => 'Serial number',
            extRef => 'SAMPLE_Q_1',
            fTpl => 'SAMPLE_TPL_1',
            fPage => 'SAMPLE_P_1',
            fSection => 'SAMPLE_S_1',
            fOrder => 1,
            fQuestion => 'Serial number',
            fType => 'Text'
        };

        return JSON.serializePretty(new List<Object>{
            new Map<String, Object>{
                'template' => template,
                'pages' => new List<Object>{ page },
                'sections' => new List<Object>{ section },
                'questions' => new List<Object>{ question }
            }
        });
    }

    /**
     * Pre-import dry-run: parses the JSON and reports what the import would
     * do without committing anything. Surfaces:
     *   - record counts (templates / pages / sections / questions)
     *   - how many templates will be CREATED vs UPDATED (by matching
     *     External_Reference__c against the org)
     *   - name collisions (incoming template name matches an existing row
     *     with a different External_Reference - will produce duplicate
     *     display names that confuse field techs)
     *   - condition references that won't resolve in this import payload
     */
    public class PreviewResult {
        @AuraEnabled public Integer templateCount = 0;
        @AuraEnabled public Integer pageCount = 0;
        @AuraEnabled public Integer sectionCount = 0;
        @AuraEnabled public Integer questionCount = 0;
        @AuraEnabled public Integer toCreateCount = 0;
        @AuraEnabled public Integer toUpdateCount = 0;
        @AuraEnabled public List<String> warnings = new List<String>();
        @AuraEnabled public List<String> nameCollisions = new List<String>();
    }

    @AuraEnabled(cacheable=false)
    public static PreviewResult previewImport(String jsonContent) {
        if (String.isBlank(jsonContent)) {
            AuraHandledException e = new AuraHandledException('Empty payload.');
            e.setMessage('Empty payload.');
            throw e;
        }

        List<FormTemplateWrapper> wrappers;
        try {
            wrappers = (List<FormTemplateWrapper>) JSON.deserialize(
                jsonContent, List<FormTemplateWrapper>.class
            );
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException('Invalid JSON: ' + e.getMessage());
            ahe.setMessage('Invalid JSON: ' + e.getMessage());
            throw ahe;
        }

        PreviewResult preview = new PreviewResult();
        if (wrappers == null) return preview;

        String externalRefField = NeuraFormUtils.getNamespacePrefix() + 'External_Reference__c';

        // Build sets of all incoming refs so we can:
        //   1. Query existing rows by External_Reference (create vs update)
        //   2. Resolve condition references later (warnings)
        Set<String> incomingTemplateRefs = new Set<String>();
        Set<String> incomingNames = new Set<String>();
        Set<String> incomingPageRefs = new Set<String>();
        Set<String> incomingSectionRefs = new Set<String>();
        Set<String> incomingQuestionRefs = new Set<String>();

        for (FormTemplateWrapper wrapper : wrappers) {
            preview.templateCount++;
            if (wrapper.template != null) {
                String ref = (String) wrapper.template.get(externalRefField);
                if (String.isNotBlank(ref)) incomingTemplateRefs.add(ref);
                if (String.isNotBlank(wrapper.template.Name)) incomingNames.add(wrapper.template.Name);
            }
            if (wrapper.pages != null) {
                for (Form_Page__c p : wrapper.pages) {
                    preview.pageCount++;
                    String ref = (String) p.get(externalRefField);
                    if (String.isNotBlank(ref)) incomingPageRefs.add(ref);
                }
            }
            if (wrapper.sections != null) {
                for (Form_Section__c s : wrapper.sections) {
                    preview.sectionCount++;
                    String ref = (String) s.get(externalRefField);
                    if (String.isNotBlank(ref)) incomingSectionRefs.add(ref);
                }
            }
            if (wrapper.questions != null) {
                for (Form_Question__c q : wrapper.questions) {
                    preview.questionCount++;
                    String ref = (String) q.get(externalRefField);
                    if (String.isNotBlank(ref)) incomingQuestionRefs.add(ref);
                }
            }
        }

        // Create vs Update: match incoming External_Reference values against
        // the org. Anything not found is a CREATE.
        Map<String, Form_Template__c> existingByRef = new Map<String, Form_Template__c>();
        if (!incomingTemplateRefs.isEmpty()) {
            for (Form_Template__c t : [
                SELECT Id, Name, External_Reference__c
                FROM Form_Template__c
                WHERE External_Reference__c IN :incomingTemplateRefs
                WITH SECURITY_ENFORCED
            ]) {
                existingByRef.put(t.External_Reference__c, t);
            }
        }
        for (FormTemplateWrapper wrapper : wrappers) {
            if (wrapper.template == null) continue;
            String ref = (String) wrapper.template.get(externalRefField);
            if (String.isNotBlank(ref) && existingByRef.containsKey(ref)) {
                preview.toUpdateCount++;
            } else {
                preview.toCreateCount++;
            }
        }

        // Name collision check: an existing template that shares a display
        // name but has a different External_Reference. The import will
        // create a second template with the same name, which confuses field
        // techs at runtime.
        if (!incomingNames.isEmpty()) {
            for (Form_Template__c t : [
                SELECT Id, Name, External_Reference__c
                FROM Form_Template__c
                WHERE Name IN :incomingNames
                WITH SECURITY_ENFORCED
                LIMIT 200
            ]) {
                // Skip if this existing row IS one of the incoming templates
                // (same External_Reference - it's an update, not a duplicate).
                if (String.isNotBlank(t.External_Reference__c)
                    && incomingTemplateRefs.contains(t.External_Reference__c)) {
                    continue;
                }
                preview.nameCollisions.add(
                    'A template named "' + t.Name + '" already exists with a different External Reference. ' +
                    'Importing will create a second template with the same display name.'
                );
            }
        }

        // Condition-reference warnings: any condition that points at a
        // page/section/question outside the import will not resolve.
        // Pages and sections are easier: just check the ref set membership.
        // Questions: we don't have the question Id map here, but we have
        // their external refs. Same idea - if a condition references a
        // questionRef that isn't in incomingQuestionRefs, warn.
        for (FormTemplateWrapper wrapper : wrappers) {
            if (wrapper.pages != null) for (Form_Page__c p : wrapper.pages) {
                preview.warnings.addAll(scanConditionForMissing(p.Conditions__c, incomingPageRefs, incomingSectionRefs, incomingQuestionRefs));
            }
            if (wrapper.sections != null) for (Form_Section__c s : wrapper.sections) {
                preview.warnings.addAll(scanConditionForMissing(s.Conditions__c, incomingPageRefs, incomingSectionRefs, incomingQuestionRefs));
            }
            if (wrapper.questions != null) for (Form_Question__c q : wrapper.questions) {
                preview.warnings.addAll(scanConditionForMissing(q.Conditions__c, incomingPageRefs, incomingSectionRefs, incomingQuestionRefs));
            }
        }
        return preview;
    }

    private static List<String> scanConditionForMissing(
        String jsonString,
        Set<String> pageRefs,
        Set<String> sectionRefs,
        Set<String> questionRefs
    ) {
        List<String> out = new List<String>();
        if (String.isBlank(jsonString)) return out;
        Object parsed;
        try { parsed = JSON.deserializeUntyped(jsonString); } catch (Exception e) { return out; }
        if (!(parsed instanceof Map<String, Object>)) return out;
        List<Object> conditions = (List<Object>) ((Map<String, Object>) parsed).get('conditions');
        if (conditions == null) return out;
        for (Object c : conditions) {
            Map<String, Object> cm = (Map<String, Object>) c;
            Object r = cm.get('resource');
            Object p = cm.get('page');
            Object s = cm.get('section');
            if (r instanceof String && String.isNotBlank((String) r) && !questionRefs.contains((String) r)) {
                out.add('Condition references question ' + r + ' which is not in the import.');
            }
            if (p instanceof String && String.isNotBlank((String) p) && !pageRefs.contains((String) p)) {
                out.add('Condition references page ' + p + ' which is not in the import.');
            }
            if (s instanceof String && String.isNotBlank((String) s) && !sectionRefs.contains((String) s)) {
                out.add('Condition references section ' + s + ' which is not in the import.');
            }
        }
        return out;
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
     *
     * As of Pillar 3 (Wave 36), this method delegates to
     * NeuraFormImportPipeline by default. The pipeline runs the Field
     * Forms adapter (NeuraFormFieldFormsAdapter) → NeuraFormImporter,
     * which produces catalog-of-one entries for every imported question
     * so subsequent edits go through the catalog. The legacy direct
     * path remains available via importTemplatesLegacy() and is the
     * implementation behind importTemplatesAsNew (which still needs
     * the regenerate-external-refs hook the pipeline doesn't yet have).
     */
    @AuraEnabled(cacheable=false)
    public static ImportResult importTemplates(String jsonContent) {
        if (String.isBlank(jsonContent)) {
            AuraHandledException e = new AuraHandledException('Import payload was empty.');
            e.setMessage('Import payload was empty.');
            throw e;
        }
        try {
            NeuraFormImportPipeline.PipelineResult pr =
                NeuraFormImportPipeline.importSource(jsonContent, null, null);
            ImportResult r = new ImportResult();
            r.templates = pr.templates;
            r.createdCount = pr.createdCount;
            r.updatedCount = pr.updatedCount;
            r.warnings = pr.warnings != null ? pr.warnings : new List<String>();
            return r;
        } catch (NeuraFormImporter.AdapterException ae) {
            // Adapter / IR validation failure. Surface the message
            // verbatim so admins see "Template is missing
            // External_Reference__c" rather than a generic exception.
            AuraHandledException ahe = new AuraHandledException(ae.getMessage());
            ahe.setMessage(ae.getMessage());
            throw ahe;
        } catch (AuraHandledException ahe) {
            throw ahe;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(
                'Import failed and was rolled back: ' + e.getMessage()
            );
            ahe.setMessage('Import failed and was rolled back: ' + e.getMessage());
            throw ahe;
        }
    }

    /**
     * Legacy direct importer kept as a fallback for the "import as new"
     * variant (regenerates External_Reference__c on every record so the
     * upsert creates fresh rows). The adapter pipeline doesn't yet
     * implement that mode; once it does, this can be deprecated.
     */
    @TestVisible
    private static ImportResult importTemplatesLegacy(String jsonContent) {
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
            // any existing rows that share the source-org Id. The FK fields
            // on child rows still hold the OLD external-ref strings (we can't
            // safely rewrite them to synthetic placeholders because Apex
            // validates Reference-field assignments at runtime), so we build
            // an inverse map and key the lookups by the OLD ref below.
            Map<String, String> newToOldRef = null;
            if (importAsNew) {
                Map<String, String> oldToNew = regenerateExternalReferences(
                    templates, pages, sections, questions, externalReferenceField
                );
                newToOldRef = new Map<String, String>();
                for (String oldR : oldToNew.keySet()) {
                    newToOldRef.put(oldToNew.get(oldR), oldR);
                }
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
            // In importAsNew mode we want the map keyed by the OLD external
            // ref (because that's still what's sitting on child FK fields).
            // In normal mode the OLD and current refs are identical.
            Map<String, Id> templateIdMap = buildIdMap(templates, externalReferenceField, newToOldRef);

            for (Form_Page__c page : pages) {
                page.Form_Template__c = templateIdMap.get((String) page.Form_Template__c);
            }
            Schema.SObjectField pageExt = Form_Page__c.SObjectType
                .getDescribe().fields.getMap().get(externalReferenceField);
            Database.UpsertResult[] pageResults = Database.upsert(pages, pageExt, false);
            throwOnFailures(pageResults, 'Form Page');
            Map<String, Id> pageIdMap = buildIdMap(pages, externalReferenceField, newToOldRef);

            for (Form_Section__c section : sections) {
                section.Form_Template__c = templateIdMap.get((String) section.Form_Template__c);
                section.Form_Page__c = pageIdMap.get((String) section.Form_Page__c);
            }
            Schema.SObjectField sectionExt = Form_Section__c.SObjectType
                .getDescribe().fields.getMap().get(externalReferenceField);
            Database.UpsertResult[] sectionResults = Database.upsert(sections, sectionExt, false);
            throwOnFailures(sectionResults, 'Form Section');
            Map<String, Id> sectionIdMap = buildIdMap(sections, externalReferenceField, newToOldRef);

            for (Form_Question__c question : questions) {
                question.Form_Template__c = templateIdMap.get((String) question.Form_Template__c);
                question.Form_Section__c = sectionIdMap.get((String) question.Form_Section__c);
                question.Form_Page__c = pageIdMap.get((String) question.Form_Page__c);
            }
            Schema.SObjectField questionExt = Form_Question__c.SObjectType
                .getDescribe().fields.getMap().get(externalReferenceField);
            Database.UpsertResult[] questionResults = Database.upsert(questions, questionExt, false);
            throwOnFailures(questionResults, 'Form Question');
            Map<String, Id> questionIdMap = buildIdMap(questions, externalReferenceField, newToOldRef);

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

    /**
     * Regenerates External_Reference__c on every record so the upsert creates
     * fresh rows. Returns a remap of old External_Reference -> new External_Reference
     * so the caller can translate the original FK strings (still sitting in
     * Form_Template__c / Form_Page__c / Form_Section__c on child rows) into
     * the new external refs once the parents have been upserted.
     *
     * Important: we deliberately do NOT mutate the FK fields here. Reference
     * fields in Apex validate their assigned value as a real Salesforce Id at
     * assignment time, so writing a synthetic "IMP_t_..." string into them
     * throws System.StringException: Invalid id. The FK fields keep the old
     * external-ref strings that JSON.deserialize put there, and the caller
     * uses the returned remap to translate them after upsert.
     */
    private static Map<String, String> regenerateExternalReferences(
        List<Form_Template__c> templates,
        List<Form_Page__c> pages,
        List<Form_Section__c> sections,
        List<Form_Question__c> questions,
        String externalReferenceField
    ) {
        Map<String, String> remap = new Map<String, String>();
        for (SObject record : (List<SObject>) templates) remap.put((String) record.get(externalReferenceField), freshRef('t'));
        for (SObject record : (List<SObject>) pages)     remap.put((String) record.get(externalReferenceField), freshRef('p'));
        for (SObject record : (List<SObject>) sections)  remap.put((String) record.get(externalReferenceField), freshRef('s'));
        for (SObject record : (List<SObject>) questions) remap.put((String) record.get(externalReferenceField), freshRef('q'));

        // Only the text External_Reference__c field is mutated. FK fields stay
        // pointing at the OLD external refs; caller resolves them via remap.
        for (Form_Template__c t : templates) t.put(externalReferenceField, remap.get((String) t.get(externalReferenceField)));
        for (Form_Page__c p : pages)         p.put(externalReferenceField, remap.get((String) p.get(externalReferenceField)));
        for (Form_Section__c s : sections)   s.put(externalReferenceField, remap.get((String) s.get(externalReferenceField)));
        for (Form_Question__c q : questions) q.put(externalReferenceField, remap.get((String) q.get(externalReferenceField)));

        return remap;
    }

    private static String freshRef(String prefix) {
        // Keep under 80 chars (current External_Reference__c length). Hex of
        // a 16-byte AES key is 32 chars; combined with the prefix and "IMP_"
        // we land around 40 chars total — plenty of headroom and short
        // enough that collisions across imports are astronomically unlikely.
        String randHex = EncodingUtil.convertToHex(Crypto.generateAesKey(128));
        return 'IMP_' + prefix + '_' + randHex;
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

    /**
     * Like createIdMap, but when newToOldRef is non-null (importAsNew mode) the
     * map is keyed by the ORIGINAL external reference instead of the current
     * one. Used by the importAsNew path so the FK strings still sitting on
     * child rows (which were never rewritten — see regenerateExternalReferences
     * for why) resolve to the right Ids.
     */
    private static Map<String, Id> buildIdMap(
        List<SObject> records,
        String externalRefField,
        Map<String, String> newToOldRef
    ) {
        Map<String, Id> idMap = new Map<String, Id>();
        for (SObject record : records) {
            String currentRef = (String) record.get(externalRefField);
            String keyRef = (newToOldRef != null && newToOldRef.containsKey(currentRef))
                ? newToOldRef.get(currentRef)
                : currentRef;
            if (keyRef != null) {
                idMap.put(keyRef, record.Id);
            }
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