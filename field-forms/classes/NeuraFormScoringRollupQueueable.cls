/**
 * Asynchronous worker for NeuraFormScoringEngine. Enqueued when a
 * Form_Answer__c trigger scope is larger than BULK_THRESHOLD so the
 * synchronous trigger doesn't blow CPU / DML limits.
 *
 * Mirrors NeuraFormSnapshotQueueable: one instance per transaction, takes a
 * set of seed Form_Answer__c Ids, re-queries the bindings + templates
 * inside the queueable context, and delegates back to
 * NeuraFormScoringEngine.process which de-dupes against any synchronous
 * work that already ran.
 */
public with sharing class NeuraFormScoringRollupQueueable implements Queueable {

    @TestVisible private Set<Id> answerIds;

    public NeuraFormScoringRollupQueueable(Set<Id> answerIds) {
        this.answerIds = answerIds == null ? new Set<Id>() : new Set<Id>(answerIds);
    }

    public void execute(QueueableContext qc) {
        if (answerIds == null || answerIds.isEmpty()) return;
        // Re-load the seed answers; the engine queries the full sibling set
        // from there.
        List<Form_Answer__c> seeds = [
            SELECT Id, Answer__c, Linked_Form__c, Passed__c, Points_Earned__c,
                Form_Question__c
            FROM Form_Answer__c
            WHERE Id IN :answerIds
        ];
        NeuraFormScoringEngine.process(seeds);
    }
}
