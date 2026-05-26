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

        // Pillar 2: when Question_Catalog_Enabled__c is on, overlay catalog
        // content (and per-binding overrides) onto each binding in-place
        // before returning. The LWC sees resolved values under the original
        // field names; the Override_*/Form_Question_Catalog__c fields stay
        // on the wire so a future LWC pass can show provenance badges
        // without another Apex roundtrip.
        if (isCatalogEnabled()) {
            resolveQuestionContentThroughCatalog(formattedQuestions);
        }

        return new FormWrapper(ft, pages, formattedSections, formattedQuestions);
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
        // binding so the binding can be linked to it. Without this, new
        // questions created in the builder silently bypass the catalog
        // model — a real workflow gap surfaced after Wave 35.7. See
        // docs/phase-2-pillar-2-question-catalog.md "Builder UI impact".
        if (isCatalogEnabled() && toCreate != null && !toCreate.isEmpty()) {
            autoCreateCatalogForNewBindings(toCreate);
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