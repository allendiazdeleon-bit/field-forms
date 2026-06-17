/*
 * Demo seed — a Work Order + Service Appointment (assigned to Alan Reed) +
 * a ready-to-complete BK Food Safety Inspection at Burger King #4421, for the
 * "generate & send a branded signed report" walkthrough.
 *
 * The form is pre-filled so the only thing left at close-out is the manager
 * signature — Alan signs on site, then the branded PDF generates, emails the
 * brand contact + Ops, and attaches to the Work Order.
 *
 * Re-runnable (idempotent): find-or-create the WO/SA/assignment; the Linked
 * Form + its answers are rebuilt deterministically each run (also resets the
 * form after a rehearsal).
 *
 * Run: sf apex run --file scripts/apex/seed-alan-reed-appointment.apex
 */

// ---- Knobs ----------------------------------------------------------------
final Id BK4421_ACCOUNT   = '001Hn00002FHyXUIA1';   // Burger King #4421
final Id BK_TPL           = 'a30Hn000003eRuFIAU';   // BK Food Safety Inspection
final Id ALAN_RESOURCE    = '0HnHn000000QY8VKAW';   // ServiceResource: Alan Reed
final Id CANONICAL_FS_LF  = 'a31Hn000003Jul3IAC';   // older FS visit to restore to Completed
final String WO_SUBJECT   = 'Food Safety Inspection — BK #4421 (Alan Reed)';

List<String> log = new List<String>();
Datetime startAt = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(9, 0, 0, 0));

// ---- 1. Work Order ---------------------------------------------------------
List<WorkOrder> wos = [
    SELECT Id FROM WorkOrder WHERE AccountId = :BK4421_ACCOUNT AND Subject = :WO_SUBJECT LIMIT 1
];
WorkOrder wo = wos.isEmpty()
    ? new WorkOrder(AccountId = BK4421_ACCOUNT, Subject = WO_SUBJECT, Status = 'New')
    : wos[0];
upsert wo;
log.add('Work Order: ' + wo.Id);

// ---- 2. Service Appointment (under the WO, scheduled tomorrow) --------------
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

// ---- 3. Assign to Alan Reed -----------------------------------------------
List<AssignedResource> ars = [
    SELECT Id FROM AssignedResource
    WHERE ServiceAppointmentId = :sa.Id AND ServiceResourceId = :ALAN_RESOURCE LIMIT 1
];
if (ars.isEmpty()) {
    insert new AssignedResource(ServiceAppointmentId = sa.Id, ServiceResourceId = ALAN_RESOURCE);
    log.add('AssignedResource: Alan Reed -> SA');
} else {
    log.add('AssignedResource: already assigned to Alan Reed');
}

// ---- 4. Linked Form (BK template) — rebuilt clean --------------------------
List<Linked_Form__c> oldLfs = [SELECT Id FROM Linked_Form__c WHERE Service_Appointment__c = :sa.Id];
if (!oldLfs.isEmpty()) {
    Set<Id> oldIds = (new Map<Id, Linked_Form__c>(oldLfs)).keySet();
    delete [SELECT Id FROM Form_Finding__c WHERE Linked_Form__c IN :oldIds];
    delete [SELECT Id FROM Form_Answer__c WHERE Linked_Form__c IN :oldIds];
    delete oldLfs;
}
Linked_Form__c lf = new Linked_Form__c(
    Form_Template__c = BK_TPL, Account__c = BK4421_ACCOUNT,
    Work_Order__c = wo.Id, Service_Appointment__c = sa.Id,
    Status__c = 'In Progress', Visit_Date__c = Date.today().addDays(1)
);
insert lf;
log.add('Linked Form: ' + lf.Id + ' (BK Food Safety Inspection, In Progress)');

// ---- 5. Pre-fill the BK answers (everything but the signature) -------------
// Match questions by label so this survives a template re-seed (Ids change).
Map<String, Form_Question__c> q = new Map<String, Form_Question__c>();
for (Form_Question__c fq : [SELECT Id, Question__c, Type__c FROM Form_Question__c WHERE Form_Template__c = :BK_TPL]) {
    q.put(fq.Question__c, fq);
}
// Pass Fail NA stores lowercase pass/fail/na. Seal #3 fails -> ties to the finding.
Map<String, String> vals = new Map<String, String>{
    'Store number confirmed on arrival'                      => '4421',
    'Manager on duty'                                        => 'R. Gomez',
    'Exterior and entry area clean'                          => 'pass',
    'Is the freezer hardware seal #3 intact?'                => 'fail',
    'Describe the seal condition and corrective action taken'=> 'Heavy condensation and a visible frost line at seal #3. Hardware replacement recommended; logged for follow-up.',
    'Freezer temperature reading (°F)'                       => '12',
    'Are cold-holding temperature logs current?'             => 'pass',
    'Is there any evidence of pest activity?'                => 'na',
    'Are floor drains clean and free of residue?'            => 'pass',
    'Are food-contact surfaces sanitized per schedule?'      => 'pass',
    'Are handwash stations stocked and accessible?'          => 'pass',
    'Sanitation observations'                                => 'Lines and prep areas clean; handwash stations stocked and accessible.',
    'Overall comments'                                       => 'Store in good standing overall. One open item: freezer seal #3 condensation — corrective action initiated.'
};
List<Form_Answer__c> seedAnswers = new List<Form_Answer__c>();
for (String label : vals.keySet()) {
    Form_Question__c fq = q.get(label);
    if (fq == null) continue;
    seedAnswers.add(new Form_Answer__c(
        Linked_Form__c = lf.Id, Form_Question__c = fq.Id, Type__c = fq.Type__c, Answer__c = vals.get(label)
    ));
}
insert seedAnswers;
log.add('Answers: seeded ' + seedAnswers.size() + ' (signature left for Alan to sign on site)');

// Finding tied to the seal #3 answer (gives the report a labeled finding row).
Id sealQId = q.containsKey('Is the freezer hardware seal #3 intact?') ? q.get('Is the freezer hardware seal #3 intact?').Id : null;
Id sealAnsId = null;
for (Form_Answer__c a : seedAnswers) if (a.Form_Question__c == sealQId) sealAnsId = a.Id;
insert new Form_Finding__c(
    Linked_Form__c = lf.Id, Form_Answer__c = sealAnsId,
    Notes__c = 'Heavy condensation and visible frost line at seal #3. Hardware replacement recommended.',
    Severity__c = 'High', Status__c = 'Open'
);
log.add('Finding: seal #3 condensation (High) added');

// ---- 6. Restore the older FS visit as a Completed prior visit --------------
update new Linked_Form__c(
    Id = CANONICAL_FS_LF, Status__c = 'Completed',
    Signed_By_Name__c = 'BK Store Manager - R. Gomez', Signature_Captured_At__c = System.now()
);
log.add('Restored ' + CANONICAL_FS_LF + ' to Completed');

System.debug('==== ALAN REED BK APPOINTMENT SEED ====');
for (String l : log) System.debug('  ✓ ' + l);
System.debug('==== DONE ==== SA=' + sa.Id + ' LF=' + lf.Id);
