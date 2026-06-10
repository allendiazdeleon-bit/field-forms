/**
 * Stamps the analytics lifecycle facts on Linked_Form__c transitions.
 *
 * - Visit_Date__c on completion: coaching and anomaly escalation ORDER BY
 *   it to build prior-visit windows; before this trigger only demo data
 *   populated it.
 * - Started_At__c on the move to In Progress, Completed_At__c /
 *   Completed_By__c / Fill_Duration_Minutes__c on the move to Completed:
 *   the time and inspector dimensions for the Tableau layer. Audit fields
 *   can't serve — LastModifiedDate/By drift with every later automation
 *   touch (PDF generation, alerts).
 *
 * All stamps are null-guarded so explicitly set values (backfills,
 * imports) are preserved.
 */
trigger LinkedFormTrigger on Linked_Form__c (before insert, before update) {
    for (Linked_Form__c lf : Trigger.new) {
        Boolean isInsert = Trigger.isInsert;
        Linked_Form__c old = isInsert ? null : Trigger.oldMap.get(lf.Id);

        Boolean nowInProgress = lf.Status__c == 'In Progress'
            && (isInsert || old.Status__c != 'In Progress');
        if (nowInProgress && lf.Started_At__c == null) {
            lf.Started_At__c = System.now();
        }

        Boolean nowCompleted = lf.Status__c == 'Completed'
            && (isInsert || old.Status__c != 'Completed');
        if (!nowCompleted) continue;

        if (lf.Visit_Date__c == null) lf.Visit_Date__c = Date.today();
        if (lf.Completed_At__c == null) lf.Completed_At__c = System.now();
        if (lf.Completed_By__c == null) lf.Completed_By__c = UserInfo.getUserId();
        if (lf.Fill_Duration_Minutes__c == null && lf.Started_At__c != null) {
            Long millis = lf.Completed_At__c.getTime() - lf.Started_At__c.getTime();
            if (millis >= 0) {
                lf.Fill_Duration_Minutes__c = ((Decimal) millis / 60000).setScale(1);
            }
        }
    }
}
