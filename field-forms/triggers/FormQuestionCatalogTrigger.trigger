/**
 * Guards the catalog's sharing model against its own scoring feature.
 *
 * Cross-question Pass_Criteria__c (leaves with resource != 'self') are
 * inherently template-specific — they reference sibling questions by
 * external ref, which only resolve inside one template's graph. A SHARED
 * entry (more than one binding) carrying such criteria silently
 * mis-scores every other adopting template. Block the combination at the
 * point an admin would create it; exclusive (or unbound) entries stay
 * free to use cross-question rules since they belong to exactly one
 * template.
 */
trigger FormQuestionCatalogTrigger on Form_Question_Catalog__c (before insert, before update) {
    Set<Id> needsCount = new Set<Id>();
    for (Form_Question_Catalog__c cat : Trigger.new) {
        // Only when the criteria are CHANGING — an entry that legitimately
        // used cross-refs while exclusive must stay editable on its other
        // fields after becoming shared (otherwise even auto-curation dies).
        Boolean criteriaChanged = Trigger.isUpdate
            && cat.Pass_Criteria__c != Trigger.oldMap.get(cat.Id).Pass_Criteria__c;
        if (criteriaChanged
            && String.isNotBlank(cat.Pass_Criteria__c)
            && NeuraFormScoringEvaluator.referencesNonSelfResources(cat.Pass_Criteria__c)) {
            needsCount.add(cat.Id);
        }
    }
    if (needsCount.isEmpty()) return;

    Map<Id, Integer> bindingCounts = new Map<Id, Integer>();
    for (AggregateResult ar : [
        SELECT Form_Question_Catalog__c cat, COUNT(Id) cnt
        FROM Form_Question__c
        WHERE Form_Question_Catalog__c IN :needsCount
        GROUP BY Form_Question_Catalog__c
    ]) {
        bindingCounts.put((Id) ar.get('cat'), (Integer) ar.get('cnt'));
    }

    for (Form_Question_Catalog__c cat : Trigger.new) {
        if (!needsCount.contains(cat.Id)) continue;
        Integer count = bindingCounts.get(cat.Id);
        if (count != null && count > 1) {
            cat.addError(
                'This entry is shared by ' + count + ' questions across templates, and its ' +
                'pass criteria reference other questions — those references only resolve in ' +
                'one template, so the others would score wrong. Use a self-only rule here, ' +
                'or move the cross-question rule to a template-specific (unshared) entry.'
            );
        }
    }
}
