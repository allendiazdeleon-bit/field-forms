/**
 * Denormalizes the stable question identity onto each answer for the
 * analytics layer. Form_Question__c is per-template, so answer-grain
 * Tableau trends fragment across form versions; the catalog entry is the
 * identity that survives revisions (Form_Finding__c already carries it —
 * this brings answers to parity). Before-context so the stamp rides the
 * same DML; one bulkified lookup per save.
 */
trigger FormAnswerAnalyticsTrigger on Form_Answer__c (before insert, before update) {
    Set<Id> questionIds = new Set<Id>();
    for (Form_Answer__c a : Trigger.new) {
        Boolean questionChanged = Trigger.isInsert
            || a.Form_Question__c != Trigger.oldMap.get(a.Id).Form_Question__c;
        if (a.Form_Question__c != null && questionChanged) {
            questionIds.add(a.Form_Question__c);
        }
    }
    if (questionIds.isEmpty()) return;

    Map<Id, Form_Question__c> questions = new Map<Id, Form_Question__c>([
        SELECT Form_Question_Catalog__c FROM Form_Question__c WHERE Id IN :questionIds
    ]);
    for (Form_Answer__c a : Trigger.new) {
        Form_Question__c q = questions.get(a.Form_Question__c);
        if (q != null) {
            a.Form_Question_Catalog__c = q.Form_Question_Catalog__c;
        }
    }
}
