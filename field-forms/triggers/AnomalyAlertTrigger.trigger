/**
 * Frees an alert's dedupe slot when it leaves the open statuses.
 *
 * Dedupe_Key__c is unique (account + pattern hash) so the database blocks a
 * second OPEN alert for the same pattern even when two escalation queueables
 * race. But the same pattern recurring AFTER an alert was handled
 * (Sent/Dismissed) is a legitimate new alert — so on close, suffix the key
 * with the record Id. The closed row keeps a unique value while the bare
 * key becomes available for the next occurrence.
 */
trigger AnomalyAlertTrigger on Anomaly_Alert__c (before update) {
    for (Anomaly_Alert__c alert : Trigger.new) {
        Boolean closing = (alert.Status__c == 'Sent' || alert.Status__c == 'Dismissed')
            && Trigger.oldMap.get(alert.Id).Status__c != alert.Status__c;
        if (closing
            && String.isNotBlank(alert.Dedupe_Key__c)
            && !alert.Dedupe_Key__c.endsWith(':' + alert.Id)) {
            alert.Dedupe_Key__c = (alert.Dedupe_Key__c + ':' + alert.Id).left(255);
        }
    }
}
