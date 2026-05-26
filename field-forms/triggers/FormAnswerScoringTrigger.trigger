/**
 * Pillar 5 — scoring + findings runtime entry point.
 *
 * Fires on after-insert / after-update of Form_Answer__c. Delegates to
 * NeuraFormScoringEngine.handle which:
 *   - bails when org-level FieldForms_Configuration__c.Scoring_Enabled__c
 *     is false (the cheap short-circuit on every save),
 *   - filters to answers whose template has Scoring_Enabled__c on,
 *   - evaluates Pass_Criteria__c, updates Passed__c / Points_Earned__c,
 *   - upserts / auto-resolves Form_Finding__c rows,
 *   - rolls up Linked_Form__c.Score__c + Findings_*_Count__c.
 *
 * Recursion guard lives in the engine (isProcessing flag), not here, so a
 * synchronous DML on Form_Answer__c from inside .handle does not re-enter
 * scoring. Bulk-threshold bifurcation also lives in the engine — this
 * trigger stays small on purpose, matching FormQuestionTrigger.
 */
trigger FormAnswerScoringTrigger on Form_Answer__c (after insert, after update) {
    if (Trigger.isAfter && (Trigger.isInsert || Trigger.isUpdate)) {
        NeuraFormScoringEngine.handle(Trigger.new);
    }
}
