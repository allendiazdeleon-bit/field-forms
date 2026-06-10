public with sharing class neuraFormBuilderController {

    /**
     * Question content fields resolved through Form_Question_Catalog__c
     * when Question_Catalog_Enabled__c is on. Same field set as
     * NeuraFormSnapshotV2.CATALOG_RESOLVABLE_FIELDS — both lists must
     * stay in sync when adding/removing catalog content fields.
     */
    private static final List<String> CATALOG_CONTENT_FIELDS = new List<String>{
        'Active_Message__c',
        'Calculation_Formula__c',
        'Calculation_Result_Format__c',
        'Decimal_Places__c',
        'Default_Value_Source__c',
        'Default_Value_Static__c',
        'Display_Rich_Text__c',
        'Font_Color__c',
        'Font_Size__c',
        'Inactive_Message__c',
        'Include_Comment__c',
        'Include_Photo__c',
        'Label_Visible__c',
        'Layout_Item__c',
        'Question__c',
        'Required__c',
        'Text_Alignment__c',
        'Type__c',
        'Value_Set__c'
    };

    /**
     * Wave 35.9: SOSL-backed search for catalog entries whose question
     * text matches the given input. Powers the type-ahead "did you
     * mean..." hint surfaced in the builder when admin types a new
     * question. Closes the drift problem at the boundary where it
     * starts (see docs/phase-2-pillar-2-question-catalog.md
     * "Operating at scale — Drift").
     *
     * Each match carries the catalog text, type, tags, and current
     * usage count (binding count across the org) so the LWC can show
     * "used in N templates" alongside each suggestion.
     *
     * Wave 35.9b: results are filtered by the template's Scope__c so
     * admins only see catalog entries their template can use.
     * Universal (Scope__c = null) entries are always visible. The
     * client further filters out the binding's own catalog row and
     * any byte-identical text matches so the panel never suggests
     * a no-op adoption.
     *
     * Returns an empty list when the input is blank, too short
     * (<3 chars) to be a meaningful search, or when the catalog
     * feature flag is off. Marked cacheable=true so the LWC's wire
     * adapter can debounce naturally — the LDS cache absorbs repeated
     * lookups for the same text. formTemplateId becomes part of the
     * cache key, so two templates with different scopes don't share
     * cached results.
     */
    @AuraEnabled(cacheable=true)
    public static List<CatalogMatch> findSimilarCatalogEntries(String text, Integer limitN, Id formTemplateId) {
        List<CatalogMatch> out = new List<CatalogMatch>();
        if (!isCatalogEnabled()) return out;
        if (String.isBlank(text) || text.trim().length() < 3) return out;
        Integer maxResults = (limitN != null && limitN > 0) ? limitN : 5;

        // Wave 35.9b: resolve the template's scope so SOSL only returns
        // catalog entries the template is allowed to consume. Unscoped
        // (Scope__c = null) entries are universal and always visible;
        // scoped entries match only when the template shares the scope.
        // Templates without a scope still see all unscoped entries.
        String templateScope = null;
        if (formTemplateId != null) {
            List<Form_Template__c> tpls = [
                SELECT Scope__c FROM Form_Template__c
                WHERE Id = :formTemplateId LIMIT 1
            ];
            if (!tpls.isEmpty()) templateScope = tpls[0].Scope__c;
        }

        // SOSL: token search across all fields, ranked by Salesforce's
        // built-in relevance scoring (stemming + token weighting).
        // RETURNING clause limits to catalog with the fields the LWC
        // needs; the LIMIT shape is mandatory in SOSL. The WHERE clause
        // applies the scope filter inside RETURNING.
        List<List<SObject>> raw = [
            FIND :text IN ALL FIELDS
            RETURNING Form_Question_Catalog__c(
                Id, Question__c, Type__c, Tags__c, External_Reference__c, Scope__c
                WHERE Scope__c = null OR Scope__c = :templateScope
                LIMIT :maxResults
            )
        ];
        List<SObject> hits = raw.isEmpty() ? new List<SObject>() : raw[0];
        if (hits.isEmpty()) return out;

        // Compute binding counts for the matched catalog entries so the
        // LWC can show "used in N templates" inline. One GROUP BY query.
        Set<Id> matchIds = new Set<Id>();
        for (SObject s : hits) matchIds.add(s.Id);
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Form_Question_Catalog__c cat, COUNT(Id) cnt
            FROM Form_Question__c
            WHERE Form_Question_Catalog__c IN :matchIds
            GROUP BY Form_Question_Catalog__c
        ]) {
            counts.put((Id) ar.get('cat'), (Integer) ar.get('cnt'));
        }

        for (SObject s : hits) {
            Form_Question_Catalog__c cat = (Form_Question_Catalog__c) s;
            CatalogMatch m = new CatalogMatch();
            m.id = cat.Id;
            m.questionText = cat.Question__c;
            m.type = cat.Type__c;
            m.tags = cat.Tags__c;
            m.externalReference = cat.External_Reference__c;
            m.usageCount = counts.containsKey(cat.Id) ? counts.get(cat.Id) : 0;
            out.add(m);
        }
        return out;
    }

    public class CatalogMatch {
        @AuraEnabled public Id id;
        @AuraEnabled public String questionText;
        @AuraEnabled public String type;
        @AuraEnabled public String tags;
        @AuraEnabled public String externalReference;
        @AuraEnabled public Integer usageCount;
    }

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
            SELECT Id, Name, Indicator_Type__c, Scope__c
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

        // Pillar 2: when Question_Catalog_Enabled__c is on, overlay catalog
        // content (and per-binding overrides) onto each binding in-place
        // before returning. The LWC sees resolved values under the original
        // field names; the Override_*/Form_Question_Catalog__c fields stay
        // on the wire so a future LWC pass can show provenance badges
        // without another Apex roundtrip.
        FormWrapper wrapper = new FormWrapper(ft, pages, formattedSections, formattedQuestions);
        if (isCatalogEnabled()) {
            resolveQuestionContentThroughCatalog(formattedQuestions);
            // Wave 35.8a: also return binding counts per catalog so the LWC
            // knows whether each binding's catalog is exclusive (count == 1)
            // or shared (count > 1). Drives binding-count-aware editing in
            // neuraFormBuilderAttributes.
            wrapper.catalogBindingCounts = computeCatalogBindingCounts(formattedQuestions);
        }
        return wrapper;
    }

    /**
     * Pillar 2 / Wave 35.8a: count how many Form_Question__c bindings
     * reference each catalog entry in the given question set. Used by the
     * LWC to drive the "exclusive vs shared" editing UX. Returns the count
     * across the ENTIRE org (not just this template) — sharing a catalog
     * entry with a binding in another template still counts as shared.
     */
    @TestVisible
    private static Map<Id, Integer> computeCatalogBindingCounts(List<Form_Question__c> bindings) {
        Set<Id> catalogIds = new Set<Id>();
        for (Form_Question__c b : bindings) {
            if (b.Form_Question_Catalog__c != null) catalogIds.add(b.Form_Question_Catalog__c);
        }
        Map<Id, Integer> counts = new Map<Id, Integer>();
        if (catalogIds.isEmpty()) return counts;
        for (AggregateResult ar : [
            SELECT Form_Question_Catalog__c cat, COUNT(Id) cnt
            FROM Form_Question__c
            WHERE Form_Question_Catalog__c IN :catalogIds
            GROUP BY Form_Question_Catalog__c
        ]) {
            counts.put((Id) ar.get('cat'), (Integer) ar.get('cnt'));
        }
        return counts;
    }

    /**
     * True when the builder should overlay catalog content onto bindings.
     * Reads the per-user hierarchy custom setting, matching the lookup
     * pattern used in NeuraFormSnapshotV2.
     */
    @TestVisible
    private static Boolean isCatalogEnabled() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        return cfg != null && cfg.Question_Catalog_Enabled__c == true;
    }

    /**
     * Overlay catalog content + per-binding overrides onto each binding in
     * the input list, mutating in place. No-op when the list is empty or
     * no binding has a catalog reference.
     *
     * Heap-conscious: one SOQL for all catalog entries referenced, in-place
     * mutation (no Map<String, Object> intermediate). At 1300 bindings the
     * baseline getFormDetails sits at ~3.1 MB sync heap; this adds ~2 MB
     * for the catalog query, landing around 5 MB out of the 6 MB cap.
     * Bindings beyond ~2x our test scale will need a chunked approach.
     *
     * Precedence (matches NeuraFormSnapshotV2.resolveQuestionThroughCatalog):
     *   1. Catalog content for each field in CATALOG_CONTENT_FIELDS
     *   2. Binding's Override_Question__c (if set) → Question__c
     *   3. Binding's Override_Required__c (if not 'Inherit') → Required__c
     */
    @TestVisible
    private static void resolveQuestionContentThroughCatalog(List<Form_Question__c> bindings) {
        if (bindings == null || bindings.isEmpty()) return;

        Set<Id> catalogIds = new Set<Id>();
        for (Form_Question__c b : bindings) {
            if (b.Form_Question_Catalog__c != null) catalogIds.add(b.Form_Question_Catalog__c);
        }
        if (catalogIds.isEmpty()) return;

        Map<Id, Form_Question_Catalog__c> catalogById = new Map<Id, Form_Question_Catalog__c>([
            SELECT Id, Active_Message__c, Calculation_Formula__c,
                   Calculation_Result_Format__c, Decimal_Places__c,
                   Default_Value_Source__c, Default_Value_Static__c,
                   Display_Rich_Text__c, Font_Color__c, Font_Size__c,
                   Inactive_Message__c, Include_Comment__c, Include_Photo__c,
                   Label_Visible__c, Layout_Item__c, Question__c,
                   Required__c, Text_Alignment__c, Type__c, Value_Set__c
            FROM Form_Question_Catalog__c
            WHERE Id IN :catalogIds
        ]);

        for (Form_Question__c b : bindings) {
            if (b.Form_Question_Catalog__c == null
                || !catalogById.containsKey(b.Form_Question_Catalog__c)) {
                continue;
            }
            Form_Question_Catalog__c cat = catalogById.get(b.Form_Question_Catalog__c);
            for (String f : CATALOG_CONTENT_FIELDS) {
                Object val = cat.get(f);
                if (val != null) b.put(f, val);
            }
            if (b.Override_Question__c != null) {
                b.Question__c = b.Override_Question__c;
            }
            if (b.Override_Required__c != null && b.Override_Required__c != 'Inherit') {
                b.Required__c = (b.Override_Required__c == 'Yes');
            }
        }
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

    public class ScoringSummary {
        @AuraEnabled public Boolean scoringEnabled = false;
        @AuraEnabled public Decimal weightSum = 0;
        @AuraEnabled public Decimal declaredMaxScore;
        @AuraEnabled public Integer scoredQuestionCount = 0;
        @AuraEnabled public Integer unscoredQuestionCount = 0;
    }

    /**
     * Authoring-time scoring sanity data for the Form settings panel: the
     * sum of catalog Weight__c across this template's bindings vs the
     * declared Max_Score__c. "Weights sum to 85 but Max Score is 100" is
     * the most common scoring misconfiguration and was previously
     * invisible until someone noticed wrong percentages on completed
     * inspections.
     */
    @AuraEnabled(cacheable=false)
    public static ScoringSummary getScoringSummary(Id formTemplateId) {
        ScoringSummary summary = new ScoringSummary();
        if (formTemplateId == null) return summary;

        List<Form_Template__c> tpl = [
            SELECT Scoring_Enabled__c, Max_Score__c
            FROM Form_Template__c WHERE Id = :formTemplateId LIMIT 1
        ];
        if (tpl.isEmpty()) return summary;
        summary.scoringEnabled = tpl[0].Scoring_Enabled__c == true;
        summary.declaredMaxScore = tpl[0].Max_Score__c;

        for (Form_Question__c q : [
            SELECT Form_Question_Catalog__r.Weight__c, Type__c
            FROM Form_Question__c
            WHERE Form_Template__c = :formTemplateId
        ]) {
            if (q.Type__c == 'Display Text') continue;
            Decimal w = q.Form_Question_Catalog__r != null
                ? q.Form_Question_Catalog__r.Weight__c : null;
            if (w != null && w > 0) {
                summary.weightSum += w;
                summary.scoredQuestionCount++;
            } else {
                summary.unscoredQuestionCount++;
            }
        }
        return summary;
    }

    // ----- Template scoring grid -------------------------------------------
    // One screen for the whole template's scoring instead of clicking
    // through forty per-question panels: every binding with inline weight /
    // severity / failure-policy / pass-rule, saved in one pass. Questions
    // without a catalog entry are promoted automatically on save — the
    // catalog stays the source of truth without being a setup chore.

    public class ScoringGridRow {
        @AuraEnabled public Id questionId;
        @AuraEnabled public Id catalogId;
        @AuraEnabled public String questionText;
        @AuraEnabled public String questionType;
        @AuraEnabled public String valueSet;
        @AuraEnabled public Decimal weight;
        @AuraEnabled public String failureSeverity;
        @AuraEnabled public Boolean autoFinding = false;
        @AuraEnabled public Boolean photoRequired = false;
        @AuraEnabled public String passCriteria;
    }

    @AuraEnabled(cacheable=false)
    public static List<ScoringGridRow> getScoringGrid(Id formTemplateId) {
        List<ScoringGridRow> rows = new List<ScoringGridRow>();
        if (formTemplateId == null) return rows;
        for (Form_Question__c q : [
            SELECT Id, Question__c, Type__c, Value_Set__c,
                   Form_Question_Catalog__c,
                   Form_Question_Catalog__r.Question__c,
                   Form_Question_Catalog__r.Value_Set__c,
                   Form_Question_Catalog__r.Weight__c,
                   Form_Question_Catalog__r.Failure_Severity__c,
                   Form_Question_Catalog__r.Failure_Auto_Finding__c,
                   Form_Question_Catalog__r.Failure_Photo_Required__c,
                   Form_Question_Catalog__r.Pass_Criteria__c
            FROM Form_Question__c
            WHERE Form_Template__c = :formTemplateId
              AND Type__c != 'Display Text'
            ORDER BY Form_Page__r.Order__c ASC, Form_Section__r.Order__c ASC, Order__c ASC
        ]) {
            ScoringGridRow row = new ScoringGridRow();
            row.questionId = q.Id;
            row.catalogId = q.Form_Question_Catalog__c;
            row.questionType = q.Type__c;
            Form_Question_Catalog__c cat = q.Form_Question_Catalog__r;
            // Catalog content wins when linked (same precedence as the
            // builder's read-side resolution).
            row.questionText = cat != null && String.isNotBlank(cat.Question__c)
                ? cat.Question__c : q.Question__c;
            row.valueSet = cat != null && String.isNotBlank(cat.Value_Set__c)
                ? cat.Value_Set__c : q.Value_Set__c;
            if (cat != null) {
                row.weight = cat.Weight__c;
                row.failureSeverity = cat.Failure_Severity__c;
                row.autoFinding = cat.Failure_Auto_Finding__c == true;
                row.photoRequired = cat.Failure_Photo_Required__c == true;
                row.passCriteria = cat.Pass_Criteria__c;
            }
            rows.add(row);
        }
        return rows;
    }

    public class ScoringGridSave {
        @AuraEnabled public Id questionId { get; set; }
        @AuraEnabled public Decimal weight { get; set; }
        @AuraEnabled public String failureSeverity { get; set; }
        @AuraEnabled public Boolean autoFinding { get; set; }
        @AuraEnabled public Boolean photoRequired { get; set; }
        @AuraEnabled public String passCriteria { get; set; }
    }

    /**
     * Persist grid edits. Bindings without a catalog entry are promoted
     * first (same content-copy as createCatalogEntryForBinding, bulk), then
     * every edited row's catalog record is updated in one DML.
     */
    @AuraEnabled(cacheable=false)
    public static List<ScoringGridRow> saveScoringGrid(Id formTemplateId, List<ScoringGridSave> rows) {
        if (formTemplateId == null || rows == null || rows.isEmpty()) {
            return getScoringGrid(formTemplateId);
        }
        try {
            Set<Id> questionIds = new Set<Id>();
            for (ScoringGridSave row : rows) {
                if (row.questionId != null) questionIds.add(row.questionId);
            }
            Map<Id, Id> catalogByQuestion = ensureCatalogEntries(questionIds);

            List<Form_Question_Catalog__c> updates = new List<Form_Question_Catalog__c>();
            for (ScoringGridSave row : rows) {
                Id catId = catalogByQuestion.get(row.questionId);
                if (catId == null) continue;
                updates.add(new Form_Question_Catalog__c(
                    Id = catId,
                    Weight__c = row.weight,
                    Failure_Severity__c = row.failureSeverity,
                    Failure_Auto_Finding__c = row.autoFinding == true,
                    Failure_Photo_Required__c = row.photoRequired == true,
                    Pass_Criteria__c = row.passCriteria
                ));
            }
            if (!updates.isEmpty()) {
                SObjectAccessDecision decision = Security.stripInaccessible(
                    AccessType.UPDATABLE, updates
                );
                update decision.getRecords();
            }
            return getScoringGrid(formTemplateId);
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
    }

    /**
     * Bulk version of the promote-to-catalog path: returns the catalog Id
     * for every requested binding, creating entries (content copied via
     * CATALOG_CONTENT_FIELDS, scoped to the template's brand) where none
     * exist yet.
     */
    private static Map<Id, Id> ensureCatalogEntries(Set<Id> questionIds) {
        Map<Id, Id> out = new Map<Id, Id>();
        if (questionIds.isEmpty()) return out;
        String fieldList = String.join(CATALOG_CONTENT_FIELDS, ', ');
        List<Form_Question__c> bindings = Database.query(
            'SELECT Id, Form_Question_Catalog__c, Form_Template__r.Scope__c, '
            + fieldList
            + ' FROM Form_Question__c WHERE Id IN :questionIds'
        );

        List<Form_Question__c> needsCatalog = new List<Form_Question__c>();
        for (Form_Question__c b : bindings) {
            if (b.Form_Question_Catalog__c != null) {
                out.put(b.Id, b.Form_Question_Catalog__c);
            } else {
                needsCatalog.add(b);
            }
        }
        if (needsCatalog.isEmpty()) return out;

        List<Form_Question_Catalog__c> catalogs = new List<Form_Question_Catalog__c>();
        for (Form_Question__c b : needsCatalog) {
            Form_Question_Catalog__c cat = new Form_Question_Catalog__c();
            cat.External_Reference__c = 'builder_' + generateExternalRef();
            cat.Scope__c = b.Form_Template__r != null ? b.Form_Template__r.Scope__c : null;
            for (String f : CATALOG_CONTENT_FIELDS) {
                Object val = b.get(f);
                if (val != null) cat.put(f, val);
            }
            catalogs.add(cat);
        }
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.CREATABLE, catalogs
        );
        List<SObject> created = decision.getRecords();
        insert created;

        List<Form_Question__c> links = new List<Form_Question__c>();
        for (Integer i = 0; i < needsCatalog.size(); i++) {
            out.put(needsCatalog[i].Id, created[i].Id);
            links.add(new Form_Question__c(
                Id = needsCatalog[i].Id,
                Form_Question_Catalog__c = created[i].Id
            ));
        }
        update links;
        return out;
    }

    /**
     * Promote an existing, catalog-less binding into its own catalog entry
     * and link it. The scoring panel needs a catalog record to edit
     * (Weight/Pass_Criteria live there), but bindings that predate the
     * catalog — imports, clones of unmatched questions, AI drafts — have no
     * link and previously no UI path to get one: the panel's directive
     * pointed at a "Create catalog entry" button that didn't exist.
     * Auto-create only covers NEW bindings saved while the flag is on.
     *
     * Content is copied with the same CATALOG_CONTENT_FIELDS list the
     * auto-create and read-side resolution use, so all three stay in sync.
     * Returns the new catalog Id for the panel to adopt immediately.
     */
    @AuraEnabled(cacheable=false)
    public static Id createCatalogEntryForBinding(Id questionId) {
        if (questionId == null) {
            throw new AuraHandledException('A saved question is required.');
        }
        try {
            String fieldList = String.join(CATALOG_CONTENT_FIELDS, ', ');
            Form_Question__c binding = Database.query(
                'SELECT Id, Form_Question_Catalog__c, Form_Template__r.Scope__c, '
                + fieldList
                + ' FROM Form_Question__c WHERE Id = :questionId LIMIT 1'
            );
            if (binding.Form_Question_Catalog__c != null) {
                return binding.Form_Question_Catalog__c;
            }

            Form_Question_Catalog__c cat = new Form_Question_Catalog__c();
            cat.External_Reference__c = 'builder_' + generateExternalRef();
            // Partition the entry to the template's brand so catalog
            // scoping/matching stays consistent with the brand spine.
            cat.Scope__c = binding.Form_Template__r != null
                ? binding.Form_Template__r.Scope__c : null;
            for (String f : CATALOG_CONTENT_FIELDS) {
                Object val = binding.get(f);
                if (val != null) cat.put(f, val);
            }
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.CREATABLE, new List<Form_Question_Catalog__c>{ cat }
            );
            insert decision.getRecords();
            Id catId = decision.getRecords()[0].Id;

            update new Form_Question__c(Id = questionId, Form_Question_Catalog__c = catId);
            return catId;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            AuraHandledException ahe = new AuraHandledException(e.getMessage());
            ahe.setMessage(e.getMessage());
            throw ahe;
        }
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
        // Pillar 2: when the catalog is enabled, every new binding gets a
        // freshly-minted Form_Question_Catalog__c. Inserted BEFORE the
        // binding so the binding can be linked to it.
        if (isCatalogEnabled() && toCreate != null && !toCreate.isEmpty()) {
            autoCreateCatalogForNewBindings(toCreate);
        }
        // Pillar 2 / Wave 35.8a: when admin updates a binding whose
        // catalog is exclusively used (binding count == 1) and no
        // override is active, sync the binding's content fields back to
        // the catalog. Keeps the catalog as "the truth" instead of
        // drifting behind the binding. Without this, edits on
        // freshly-created (bindingCount=1) questions would live only on
        // the binding while the catalog stays empty — if a second
        // template later adopts the catalog entry, there's nothing
        // useful there.
        if (isCatalogEnabled() && toUpdate != null && !toUpdate.isEmpty()) {
            syncExclusiveCatalogContentOnUpdate(toUpdate);
        }
        return (List<Form_Question__c>) processFormUpdate(toCreate, toUpdate, toDelete);
    }

    /**
     * For each new Form_Question__c binding lacking a catalog reference,
     * insert a Form_Question_Catalog__c populated with the binding's
     * content fields and link the binding back to it. Mutates the input
     * list in place so the subsequent processFormUpdate sees the linked
     * binding.
     *
     * Bindings that already have Form_Question_Catalog__c set (e.g.,
     * created via "Pick from catalog" — future wave) are left alone.
     */
    @TestVisible
    private static void autoCreateCatalogForNewBindings(List<Form_Question__c> newBindings) {
        // Filter to bindings without a catalog ref. Pre-linked bindings
        // (e.g. from "Pick from catalog") flow through unchanged.
        List<Form_Question__c> needsCatalog = new List<Form_Question__c>();
        for (Form_Question__c b : newBindings) {
            if (b.Form_Question_Catalog__c == null) needsCatalog.add(b);
        }
        if (needsCatalog.isEmpty()) return;

        // Build catalog entries copying content from each binding. The
        // External_Reference__c gets a synthetic value here because the
        // binding doesn't have an Id yet (it's pre-insert). The backfill
        // batch uses 'cat_<bindingId>'; for net-new builder-created
        // entries we use 'builder_<uuid>' as a distinguishable prefix.
        // Field copy uses the same CATALOG_CONTENT_FIELDS list used by
        // the read-side resolution in resolveQuestionContentThroughCatalog —
        // the two paths stay in sync via that single constant.
        List<Form_Question_Catalog__c> catalogs = new List<Form_Question_Catalog__c>();
        for (Integer i = 0; i < needsCatalog.size(); i++) {
            Form_Question__c b = needsCatalog[i];
            Form_Question_Catalog__c cat = new Form_Question_Catalog__c();
            cat.External_Reference__c = 'builder_' + generateExternalRef();
            for (String f : CATALOG_CONTENT_FIELDS) {
                try {
                    Object val = b.get(f);
                    if (val != null) cat.put(f, val);
                } catch (System.SObjectException e) {
                    // Field wasn't populated on the incoming binding; skip.
                    // Happens for fields the builder didn't set (e.g.
                    // Calculation_Formula__c on a Text question).
                }
            }
            catalogs.add(cat);
        }
        insert catalogs;

        // Link bindings to their newly-created catalog entries.
        for (Integer i = 0; i < needsCatalog.size(); i++) {
            needsCatalog[i].Form_Question_Catalog__c = catalogs[i].Id;
        }
    }

    /**
     * Generate a short, collision-resistant identifier for the catalog
     * entry's External_Reference__c. Using DateTime + a random suffix
     * keeps the value compact and unique-enough for the 80-char field;
     * the unique constraint guards against real collisions.
     */
    @TestVisible
    private static String generateExternalRef() {
        return String.valueOf(Datetime.now().getTime())
            + '_'
            + String.valueOf(Math.abs(Crypto.getRandomLong())).left(8);
    }

    /**
     * Wave 35.8a: for each binding update where the binding's catalog
     * entry has exactly one binding pointing at it (this one) AND no
     * per-template override is active, copy content fields from the
     * binding to the catalog. Skipped silently when the catalog is
     * shared (>1 binding) or when an override exists on this binding
     * (override fields are the explicit "per-template content" channel
     * and should not flow back to the catalog).
     */
    @TestVisible
    private static void syncExclusiveCatalogContentOnUpdate(List<Form_Question__c> updates) {
        // Collect catalog ids referenced by the update set.
        Set<Id> catalogIds = new Set<Id>();
        for (Form_Question__c b : updates) {
            if (b.Form_Question_Catalog__c != null) catalogIds.add(b.Form_Question_Catalog__c);
        }
        if (catalogIds.isEmpty()) return;

        // One SOQL to count bindings per catalog across the org.
        Map<Id, Integer> counts = new Map<Id, Integer>();
        for (AggregateResult ar : [
            SELECT Form_Question_Catalog__c cat, COUNT(Id) cnt
            FROM Form_Question__c
            WHERE Form_Question_Catalog__c IN :catalogIds
            GROUP BY Form_Question_Catalog__c
        ]) {
            counts.put((Id) ar.get('cat'), (Integer) ar.get('cnt'));
        }

        // Build catalog updates for exclusively-bound bindings without
        // overrides. Use the same CATALOG_CONTENT_FIELDS list as the
        // read-side resolver so what flows out matches what flows in.
        List<Form_Question_Catalog__c> toSync = new List<Form_Question_Catalog__c>();
        for (Form_Question__c b : updates) {
            if (b.Form_Question_Catalog__c == null) continue;
            Integer cnt = counts.get(b.Form_Question_Catalog__c);
            if (cnt == null || cnt != 1) continue;
            // If admin explicitly set an override, that's the per-template
            // truth — don't propagate the binding's Question__c back to
            // the catalog. Defensive read via populatedFieldsAsMap because
            // the in-memory SObject may not have these fields queried
            // (e.g. minimal test SObjects). Treating absent-from-map as
            // "no override" is correct: the override fields default null.
            Map<String, Object> populated = b.getPopulatedFieldsAsMap();
            Object overrideQ = populated.get('Override_Question__c');
            String overrideReq = (String) populated.get('Override_Required__c');
            if (overrideQ != null) continue;
            if (overrideReq != null && overrideReq != 'Inherit') continue;

            Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
                Id = b.Form_Question_Catalog__c
            );
            for (String f : CATALOG_CONTENT_FIELDS) {
                if (populated.containsKey(f)) {
                    cat.put(f, populated.get(f));
                }
            }
            toSync.add(cat);
        }
        if (!toSync.isEmpty()) update toSync;
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
        // Pillar 2: catalog binding count keyed by catalog Id. The LWC
        // reads this to decide whether the question editor should be
        // editable (count == 1, exclusive use) or read-only-with-Override
        // (count > 1, shared). Populated only when Question_Catalog_Enabled__c
        // is on; otherwise null.
        @AuraEnabled
        public Map<Id, Integer> catalogBindingCounts;

        public FormWrapper(Form_Template__c formTemplate, List<Form_Page__c> pages, List<Form_Section__c> sections, List<Form_Question__c> questions){
            this.formTemplate = formTemplate;
            this.pages = pages;
            this.sections = sections;
            this.questions = questions;
        }
    }


}