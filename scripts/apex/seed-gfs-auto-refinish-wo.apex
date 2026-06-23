/*
 * GFS Auto Refinish PM seed — a NEW Crash Champions account + Work Order +
 * Service Appointment (Alan Reed) + an EMPTY GFS Auto Refinish PM Annual
 * Service Report linked form (no pre-filled answers, filled live on device).
 *
 * Mirrors the BK live-demo seed pattern. Re-runnable (idempotent).
 *
 * Run: sf apex run --file scripts/apex/seed-gfs-auto-refinish-wo.apex
 */

// ---- Knobs ----------------------------------------------------------------
final Id GFS_TPL        = 'a30Hn000003eUT6IAM';   // GFS Auto Refinish PM Annual Service Report
final Id ALAN           = '0HnHn000000QY8VKAW';   // ServiceResource: Alan Reed
final String ACCT_NAME  = 'Crash Champions #1234';
final String WO_SUBJECT = 'Auto Refinish PM — Annual Service (Crash Champions #1234)';

List<String> log = new List<String>();
Datetime startAt = Datetime.newInstance(Date.today().addDays(1), Time.newInstance(9, 0, 0, 0));

// ---- 1. Crash Champions account -------------------------------------------
List<Account> accts = [SELECT Id FROM Account WHERE Name = :ACCT_NAME LIMIT 1];
Account acct = accts.isEmpty() ? new Account(Name = ACCT_NAME) : accts[0];
upsert acct;
log.add('Account: ' + acct.Id + ' (' + ACCT_NAME + ')');

// ---- 2. New Work Order -----------------------------------------------------
List<WorkOrder> wos = [
    SELECT Id FROM WorkOrder WHERE AccountId = :acct.Id AND Subject = :WO_SUBJECT LIMIT 1
];
WorkOrder wo = wos.isEmpty()
    ? new WorkOrder(AccountId = acct.Id, Subject = WO_SUBJECT, Status = 'New')
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

// ---- 4. EMPTY GFS Linked Form (no pre-filled answers) ----------------------
List<Linked_Form__c> oldLfs = [SELECT Id FROM Linked_Form__c WHERE Service_Appointment__c = :sa.Id];
if (!oldLfs.isEmpty()) {
    Set<Id> oldIds = (new Map<Id, Linked_Form__c>(oldLfs)).keySet();
    delete [SELECT Id FROM Form_Finding__c WHERE Linked_Form__c IN :oldIds];
    delete [SELECT Id FROM Form_Answer__c WHERE Linked_Form__c IN :oldIds];
    delete oldLfs;
}
Linked_Form__c lf = new Linked_Form__c(
    Form_Template__c = GFS_TPL, Account__c = acct.Id,
    Work_Order__c = wo.Id, Service_Appointment__c = sa.Id,
    Status__c = 'In Progress', Visit_Date__c = Date.today().addDays(1)
);
insert lf;
log.add('Linked Form (EMPTY): ' + lf.Id + ' (GFS Auto Refinish PM, no answers)');

System.debug('==== GFS AUTO REFINISH SEED ====');
for (String l : log) System.debug('  ✓ ' + l);
System.debug('==== DONE ==== WO=' + wo.Id + ' SA=' + sa.Id + ' LF=' + lf.Id);
