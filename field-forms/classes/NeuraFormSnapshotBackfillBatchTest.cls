/**
 * Coverage for NeuraFormSnapshotBackfillBatch. Verifies the batch runs
 * end-to-end through NeuraFormLogic.processTemplates and that the v2
 * snapshot is materialized when the feature flag is on.
 */
@isTest
private class NeuraFormSnapshotBackfillBatchTest {

    @isTest
    static void backfill_writesV2ChunksForAllTemplates() {
        // v2 on, snapshot trigger NOT killed.
        FieldForms_Configuration__c cfg = new FieldForms_Configuration__c();
        cfg.Snapshot_V2_Enabled__c = true;
        cfg.Disable_Form_Template_JSON_Trigger__c = false;
        insert cfg;

        Form_Template__c t1 = makeTemplate('Backfill T1');
        Form_Template__c t2 = makeTemplate('Backfill T2');
        makeQuestionTree(t1.Id);
        makeQuestionTree(t2.Id);

        // Delete any existing snapshot rows so we observe the batch repopulating.
        delete [SELECT Id FROM Form_Template_Snapshot__c];

        // Batch size 200 keeps both templates inside one executeBatch
        // invocation — Test methods cap at one executeBatch invocation.
        Test.startTest();
        Database.executeBatch(new NeuraFormSnapshotBackfillBatch(), 200);
        Test.stopTest();

        Integer chunkCount = [
            SELECT COUNT() FROM Form_Template_Snapshot__c
            WHERE Form_Template__c IN (:t1.Id, :t2.Id)
        ];
        // 6 payload types per template × 2 templates
        System.assertEquals(12, chunkCount,
            'Backfill should produce 6 chunk rows per template');
    }

    @isTest
    static void backfill_respectsTemplateIdScope() {
        FieldForms_Configuration__c cfg = new FieldForms_Configuration__c();
        cfg.Snapshot_V2_Enabled__c = true;
        cfg.Disable_Form_Template_JSON_Trigger__c = false;
        insert cfg;

        Form_Template__c t1 = makeTemplate('Scope T1');
        Form_Template__c t2 = makeTemplate('Scope T2');
        makeQuestionTree(t1.Id);
        makeQuestionTree(t2.Id);

        delete [SELECT Id FROM Form_Template_Snapshot__c];

        Test.startTest();
        Database.executeBatch(
            new NeuraFormSnapshotBackfillBatch(new Set<Id>{t1.Id}),
            1
        );
        Test.stopTest();

        Integer t1Chunks = [
            SELECT COUNT() FROM Form_Template_Snapshot__c
            WHERE Form_Template__c = :t1.Id
        ];
        Integer t2Chunks = [
            SELECT COUNT() FROM Form_Template_Snapshot__c
            WHERE Form_Template__c = :t2.Id
        ];
        System.assertEquals(6, t1Chunks, 'Scoped template should be rebuilt');
        System.assertEquals(0, t2Chunks, 'Out-of-scope template should be untouched');
    }

    @isTest
    static void backfill_emptyOrgRunsCleanly() {
        FieldForms_Configuration__c cfg = new FieldForms_Configuration__c();
        cfg.Snapshot_V2_Enabled__c = true;
        cfg.Disable_Form_Template_JSON_Trigger__c = false;
        insert cfg;

        Test.startTest();
        Database.executeBatch(new NeuraFormSnapshotBackfillBatch(), 1);
        Test.stopTest();

        System.assertEquals(0, [SELECT COUNT() FROM Form_Template_Snapshot__c],
            'No snapshot rows expected when there are no templates');
    }

    // ----- helpers ---------------------------------------------------------

    private static Form_Template__c makeTemplate(String name) {
        Form_Template__c t = new Form_Template__c(Name = name);
        insert t;
        return t;
    }

    private static void makeQuestionTree(Id templateId) {
        Form_Page__c p = new Form_Page__c(
            Form_Template__c = templateId, Order__c = 1, Title__c = 'P'
        );
        insert p;
        Form_Section__c s = new Form_Section__c(
            Form_Template__c = templateId, Form_Page__c = p.Id, Name = 'S'
        );
        insert s;
        Form_Question__c q = new Form_Question__c(
            Form_Template__c = templateId, Form_Section__c = s.Id,
            Question__c = 'Q'
        );
        insert q;
    }
}
