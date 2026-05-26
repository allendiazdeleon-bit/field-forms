/**
 * One-shot batch to create catalog-of-one Form_Question_Catalog__c entries
 * for every existing Form_Question__c binding that doesn't already have one.
 *
 * Strategy: for each binding without a catalog reference, insert a new
 * catalog entry copying the content fields verbatim, then update the
 * binding to point at the new entry. Idempotent — bindings that already
 * have a catalog reference are skipped via the start() WHERE clause.
 *
 * Does NOT enable Question_Catalog_Enabled__c. Customers backfill
 * first, then flip the flag. That separation lets a customer validate
 * the backfill ran correctly (`SELECT COUNT() FROM Form_Question_Catalog__c`
 * vs `SELECT COUNT() FROM Form_Question__c`) before changing read-path
 * behavior.
 *
 * Recommended invocation:
 *
 *   // 1. Suppress snapshot regenerations during backfill (one queueable
 *   //    per template per batch otherwise).
 *   FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
 *   cfg.Disable_Form_Template_JSON_Trigger__c = true;
 *   upsert cfg;
 *
 *   // 2. Run the backfill (default batch size 200 is fine — small DML
 *   //    per record, no heavy JSON serialization like snapshot rebuild).
 *   Database.executeBatch(new NeuraFormCatalogBackfillBatch(), 200);
 *
 *   // 3. After the batch completes, restore the snapshot trigger and
 *   //    rebuild snapshots so legacy-shape readers continue to work
 *   //    until Question_Catalog_Enabled__c is flipped on.
 *   cfg.Disable_Form_Template_JSON_Trigger__c = false;
 *   update cfg;
 *   Database.executeBatch(new NeuraFormSnapshotBackfillBatch(), 1);
 *
 * To scope to a specific set of templates, pass their Ids:
 *
 *   Database.executeBatch(
 *     new NeuraFormCatalogBackfillBatch(new Set<Id>{ '...', '...' }),
 *     200
 *   );
 *
 * See docs/phase-2-pillar-2-question-catalog.md.
 */
public with sharing class NeuraFormCatalogBackfillBatch
    implements Database.Batchable<SObject> {

    /**
     * Content fields that move from Form_Question__c (binding) to
     * Form_Question_Catalog__c. Listed once; used to construct the
     * source SOQL and to drive the dynamic field copy. Kept in sync
     * with the catalog schema declared in
     * objects/Form_Question_Catalog__c/fields/.
     */
    @TestVisible
    private static final List<String> CONTENT_FIELDS = new List<String>{
        'Active_Message__c',
        'Calculation_Formula__c',
        'Calculation_Result_Format__c',
        'Date_Time_Save_Format__c',
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
        'Length__c',
        'Lookup_Child_Object__c',
        'Lookup_Display_Field__c',
        'Lookup_Related_List__c',
        'Max__c',
        'Min__c',
        'Question__c',
        'Required__c',
        'Slider_Size__c',
        'Slider_Step__c',
        'Text_Alignment__c',
        'Type__c',
        'Value_Set__c'
    };

    @TestVisible
    private Set<Id> templateIdScope;

    public NeuraFormCatalogBackfillBatch() {}

    public NeuraFormCatalogBackfillBatch(Set<Id> templateIdScope) {
        this.templateIdScope = templateIdScope;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        String fields = 'Id, ' + String.join(CONTENT_FIELDS, ', ');
        String soql = 'SELECT ' + fields +
            ' FROM Form_Question__c WHERE Form_Question_Catalog__c = NULL';
        if (templateIdScope != null && !templateIdScope.isEmpty()) {
            Set<Id> scope = templateIdScope;
            soql += ' AND Form_Template__c IN :scope';
        }
        return Database.getQueryLocator(soql);
    }

    public void execute(Database.BatchableContext bc, List<Form_Question__c> scope) {
        if (scope == null || scope.isEmpty()) return;

        // Build catalog entries — one per binding (catalog-of-one).
        // External_Reference__c is derived from the binding Id so the
        // mapping is traceable post-backfill and the unique constraint
        // never collides.
        List<Form_Question_Catalog__c> catalogs = new List<Form_Question_Catalog__c>();
        for (Form_Question__c q : scope) {
            Form_Question_Catalog__c cat = new Form_Question_Catalog__c();
            cat.External_Reference__c = 'cat_' + q.Id;
            for (String f : CONTENT_FIELDS) {
                cat.put(f, q.get(f));
            }
            catalogs.add(cat);
        }
        insert catalogs;

        // Link each binding to its newly-created catalog entry. Index
        // alignment is safe because catalogs[i] was built from scope[i].
        for (Integer i = 0; i < scope.size(); i++) {
            scope[i].Form_Question_Catalog__c = catalogs[i].Id;
        }
        update scope;
    }

    public void finish(Database.BatchableContext bc) {
        // No post-job hook today. If we ever want to chain a snapshot
        // rebuild automatically, this is where it'd live — but the
        // recommended pattern keeps that as an explicit user step so
        // the customer can validate the backfill counts before
        // committing to a snapshot rewrite.
    }
}
