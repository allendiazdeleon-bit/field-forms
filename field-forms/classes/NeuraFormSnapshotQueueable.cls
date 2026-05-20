/**
 * Queueable that re-serialises the Form_Template JSON snapshot fields
 * (Pages_JSON__c, Sections_JSON__c, Questions_JSON__c[/_1/_2],
 * Page/Section/Question Conditions) for a set of template Ids.
 *
 * Why this exists:
 * The trigger pipeline used to run NeuraFormLogic.processTemplates(...)
 * synchronously on every Form_Page/Section/Question DML. When a field tech
 * sync'd 30 offline answers, that produced 30 full template re-serialisations
 * inside the same transaction, exhausting CPU and DML governor limits at scale.
 *
 * The triggers now enqueue exactly one instance of this Queueable per
 * transaction (deduped via NeuraFormLogic.processedTemplates) so the rebuild
 * happens once asynchronously, regardless of how many child DMLs ran.
 */
public with sharing class NeuraFormSnapshotQueueable implements Queueable {

    @TestVisible private Set<Id> templateIds;

    public NeuraFormSnapshotQueueable(Set<Id> templateIds) {
        this.templateIds = templateIds == null ? new Set<Id>() : new Set<Id>(templateIds);
    }

    public void execute(QueueableContext qc) {
        if (templateIds == null || templateIds.isEmpty()) {
            return;
        }
        // processTemplates already de-dupes against its in-memory set,
        // queries the templates, and updates the JSON snapshots.
        NeuraFormLogic.processTemplates(templateIds);
    }
}
