/*
 * BK live demo seed — a NEW Work Order + Service Appointment (Alan Reed) +
 * an EMPTY BK Food Safety Inspection (no pre-filled answers, so the form is
 * filled live on stage), plus the recurring prior-visit finding the real-time
 * coaching engine needs to fire.
 *
 * Why the coaching seed is needed: the existing BK#4421 history has findings
 * that are thematically about seal #3 condensation but each worded
 * differently. NeuraFormCoachingController groups by EXACT normalized note
 * text, so it would count each as one and never reach the recurrence
 * threshold. We plant one identical note across the recent completed visits
 * so coaching detects "flagged on N of the last visits" and nudges.
 *
 * Re-runnable (idempotent).
 *
 * Run: sf apex run --file scripts/apex/seed-bk-live-demo.apex
 */

// ---- Knobs ----------------------------------------------------------------
final Id BK4421     = '001Hn00002FHyXUIA1';   // Burger King #4421
final Id BK_TPL     = 'a30Hn000003eRuFIAU';   // BK Food Safety Inspection
final Id ALAN       = '0HnHn000000QY8VKAW';   // ServiceResource: Alan Reed
final String WO_SUBJECT  = 'Food Safety Inspection — BK #4421 (Live demo)';
final String COACH_NOTE  = 'Condensation observed on upper freezer hinge (seal #3).';
final Integer RECUR_OVER = 4;                 // plant the note on the last N completed visits

List<String> log = new List<String>();
Datetime startAt = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(9, 0, 0, 0));

// ---- 1. Coaching anomaly: identical recurring note on recent visits --------
List<Linked_Form__c> priors = [
    SELECT Id FROM Linked_Form__c
    WHERE Account__c = :BK4421 AND Form_Template__c = :BK_TPL AND Status__c = 'Completed'
    ORDER BY Visit_Date__c DESC NULLS LAST
    LIMIT :RECUR_OVER
];
Set<Id> priorIds = (new Map<Id, Linked_Form__c>(priors)).keySet();

// Which of those already carry the exact note? (idempotency)
Set<Id> alreadyHas = new Set<Id>();
String wantNorm = COACH_NOTE.trim().toLowerCase();
for (Form_Finding__c f : [SELECT Linked_Form__c, Notes__c FROM Form_Finding__c WHERE Linked_Form__c IN :priorIds]) {
    if (f.Notes__c != null && f.Notes__c.trim().toLowerCase() == wantNorm) alreadyHas.add(f.Linked_Form__c);
}
List<Form_Finding__c> newFindings = new List<Form_Finding__c>();
for (Id pid : priorIds) {
    if (alreadyHas.contains(pid)) continue;
    newFindings.add(new Form_Finding__c(
        Linked_Form__c = pid, Notes__c = COACH_NOTE, Severity__c = 'High', Status__c = 'Open'
    ));
}
if (!newFindings.isEmpty()) insert newFindings;
log.add('Coaching: recurring note now on ' + priorIds.size() + ' of the last ' +
        RECUR_OVER + ' completed visits (added ' + newFindings.size() + ')');

// ---- 2. New Work Order -----------------------------------------------------
List<WorkOrder> wos = [
    SELECT Id FROM WorkOrder WHERE AccountId = :BK4421 AND Subject = :WO_SUBJECT LIMIT 1
];
WorkOrder wo = wos.isEmpty()
    ? new WorkOrder(AccountId = BK4421, Subject = WO_SUBJECT, Status = 'New')
    : wos[0];
upsert wo;
log.add('Work Order: ' + wo.Id);

// ---- 3. Service Appointment assigned to Alan Reed --------------------------
List<ServiceAppointment> sas = [
    SELECT Id FROM ServiceAppointment WHERE ParentRecordId = :wo.Id AND Subject = :WO_SUBJECT LIMIT 1
];
ServiceAppointment sa = sas.isEmpty() ? new ServiceAppointment(
        ParentRecordId = wo.Id, Subject = WO_SUBJECT, Status = 'Scheduled',
        EarliestStartTime = startAt.addHours(-1), DueDate = startAt.addHours(8),
        SchedStartTime = startAt, SchedEndTime = startAt.addHours(1)
    ) : sas[0];
upsert sa;
log.add('Service Appointment: ' + sa.Id + ' @ ' + startAt.format());

List<AssignedResource> ars = [
    SELECT Id FROM AssignedResource WHERE ServiceAppointmentId = :sa.Id AND ServiceResourceId = :ALAN LIMIT 1
];
if (ars.isEmpty()) {
    insert new AssignedResource(ServiceAppointmentId = sa.Id, ServiceResourceId = ALAN);
    log.add('AssignedResource: Alan Reed -> SA');
} else {
    log.add('AssignedResource: already assigned to Alan Reed');
}

// ---- 4. EMPTY BK Linked Form (no pre-filled answers) -----------------------
List<Linked_Form__c> oldLfs = [SELECT Id FROM Linked_Form__c WHERE Service_Appointment__c = :sa.Id];
if (!oldLfs.isEmpty()) {
    Set<Id> oldIds = (new Map<Id, Linked_Form__c>(oldLfs)).keySet();
    delete [SELECT Id FROM Form_Finding__c WHERE Linked_Form__c IN :oldIds];
    delete [SELECT Id FROM Form_Answer__c WHERE Linked_Form__c IN :oldIds];
    delete oldLfs;
}
Linked_Form__c lf = new Linked_Form__c(
    Form_Template__c = BK_TPL, Account__c = BK4421,
    Work_Order__c = wo.Id, Service_Appointment__c = sa.Id,
    Status__c = 'In Progress', Visit_Date__c = Date.today().addDays(1)
);
insert lf;
log.add('Linked Form (EMPTY): ' + lf.Id + ' (BK Food Safety Inspection, no answers)');

System.debug('==== BK LIVE DEMO SEED ====');
for (String l : log) System.debug('  ✓ ' + l);
System.debug('==== DONE ==== SA=' + sa.Id + ' LF=' + lf.Id);
