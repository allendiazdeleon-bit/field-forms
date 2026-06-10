/**
 * Stamps Linked_Form__c.Visit_Date__c when an inspection completes.
 *
 * Coaching (NeuraFormCoachingController) and anomaly escalation
 * (NeuraFormAnomalyEscalation) both ORDER BY Visit_Date__c to build the
 * prior-visit window — before this trigger, only demo/test data populated
 * the field, so real completions sorted arbitrarily (NULLS LAST) and the
 * window was wrong. Before-context so the stamp rides the same DML, and
 * null-guarded so an explicitly set date (backfill, import) is preserved.
 */
trigger LinkedFormTrigger on Linked_Form__c (before insert, before update) {
    for (Linked_Form__c lf : Trigger.new) {
        if (lf.Visit_Date__c != null || lf.Status__c != 'Completed') continue;
        Boolean justCompleted = Trigger.isInsert
            || Trigger.oldMap.get(lf.Id).Status__c != 'Completed';
        if (justCompleted) {
            lf.Visit_Date__c = Date.today();
        }
    }
}
