/**
 * One-shot batch to rebuild Form_Template snapshot data across an org.
 *
 * Primary use: after enabling
 * FieldForms_Configuration__c.Snapshot_V2_Enabled__c, run this to populate
 * Form_Template_Snapshot__c chunk rows for every existing template that
 * hasn't been re-saved since the flag flipped. Templates that have been
 * edited since the flip already snapshot to v2 via the trigger pipeline;
 * this batch handles the long tail.
 *
 * Also usable as a general "rebuild all snapshots" maintenance operation
 * regardless of v2 state — the snapshot path branches on the flag at write
 * time, so this batch writes whichever shape the org is configured for.
 *
 * Recommended batch size: 1 (one template per scope). NeuraFormLogic
 * queries every Page/Section/Question for each template in scope, so
 * larger batches can blow async heap with big compliance forms (the
 * Steritech-shape audit at ~858K serialized is the motivating case).
 *
 *   Database.executeBatch(new NeuraFormSnapshotBackfillBatch(), 1);
 *
 * To scope to a specific set of templates, pass their Ids to the
 * constructor:
 *
 *   Set<Id> ids = new Set<Id>{ '...', '...' };
 *   Database.executeBatch(new NeuraFormSnapshotBackfillBatch(ids), 1);
 *
 * See docs/snapshot-v2.md.
 */
public with sharing class NeuraFormSnapshotBackfillBatch
    implements Database.Batchable<SObject> {

    @TestVisible
    private Set<Id> templateIdScope;

    public NeuraFormSnapshotBackfillBatch() {}

    public NeuraFormSnapshotBackfillBatch(Set<Id> templateIdScope) {
        this.templateIdScope = templateIdScope;
    }

    public Database.QueryLocator start(Database.BatchableContext bc) {
        if (templateIdScope != null && !templateIdScope.isEmpty()) {
            Set<Id> scope = templateIdScope;
            return Database.getQueryLocator(
                'SELECT Id FROM Form_Template__c WHERE Id IN :scope'
            );
        }
        return Database.getQueryLocator('SELECT Id FROM Form_Template__c');
    }

    public void execute(Database.BatchableContext bc, List<Form_Template__c> scope) {
        if (scope == null || scope.isEmpty()) return;

        Set<Id> ids = new Set<Id>();
        for (Form_Template__c t : scope) ids.add(t.Id);

        // Goes through the same code path the trigger pipeline uses, so
        // whatever the Snapshot_V2_Enabled__c flag says at this moment is
        // what gets written.
        NeuraFormLogic.processTemplates(ids);
    }

    public void finish(Database.BatchableContext bc) {
        // No post-job hook today. If we ever want to chain a "verify"
        // pass (assert every template ended with at least one snapshot
        // row when v2 is on), this is where it'd live.
    }
}
