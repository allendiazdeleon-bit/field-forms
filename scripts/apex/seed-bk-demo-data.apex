/**
 * Seeds the Burger King portfolio demo data for Vignette 5 (brand portal).
 * Re-runnable: deletes inspections under the seed template (findings cascade)
 * and SEED-keyed anomaly alerts before recreating.
 *
 * Shape: 1 corporate + 38 stores across 4 regions; 6 monthly visits each
 * (Dec 2025 - May 2026); findings scaled to score; a 3-store Southeast
 * "drift cluster" (incl. #4421) declining over the last 3 months with a
 * recurring freezer-seal pattern; veteran-vs-rookie inspector spread for
 * the tenure/ramp dashboards. #4421 gets NO current-day visit — the live
 * demo creates that one.
 */
String BRAND = 'BURGER_KING';
Id LAUREN_CONTACT = '003Hn00002tb7sZIAQ';
Id ALAN = '005Hn00000JIbzuIAD';   // veteran (~6 yrs)
Id MATT = '005Hn00000JIc0jIAD';   // rookie (~6 months)

// ---- 0. Template (sharing root for the whole portal) + cleanup ----
Form_Template__c tpl;
List<Form_Template__c> tpls = [SELECT Id FROM Form_Template__c
    WHERE Name = 'BK Food Safety Inspection' AND Scope__c = :BRAND LIMIT 1];
if (tpls.isEmpty()) {
    tpl = new Form_Template__c(Name = 'BK Food Safety Inspection', Scope__c = BRAND, Status__c = 'Active');
    insert tpl;
} else {
    tpl = tpls[0];
    delete [SELECT Id FROM Linked_Form__c WHERE Form_Template__c = :tpl.Id]; // findings cascade
}
delete [SELECT Id FROM Anomaly_Alert__c WHERE Dedupe_Key__c LIKE 'SEED:%'];

// ---- 1. Accounts: corporate + 38 stores ----
List<Account> corpQ = [SELECT Id FROM Account WHERE Name = 'Burger King Corporate' LIMIT 1];
Account corp = corpQ.isEmpty()
    ? new Account(Name = 'Burger King Corporate', Form_Scope__c = BRAND)
    : corpQ[0];
upsert corp;

List<String> storeNums = new List<String>{
    '1037','1162','1209','1284','1311','1376','1408','1453','1502','1547',
    '1593','1641','1688','1726','1779','1815','1862','1904','1951','2007',
    '2053','2096','2144','2237','2281','2319','2366','2412','2458','2503',
    '2549','2587','2631','2678','2724','2761'};
List<String> regions = new List<String>();
for (Integer i = 0; i < 8;  i++) regions.add('Southeast');
for (Integer i = 0; i < 9;  i++) regions.add('Northeast');
for (Integer i = 0; i < 9;  i++) regions.add('Midwest');
for (Integer i = 0; i < 10; i++) regions.add('West');

Map<String, Account> byName = new Map<String, Account>();
for (Account a : [SELECT Id, Name FROM Account WHERE Name LIKE 'Burger King #%']) byName.put(a.Name, a);

List<Account> storeUpserts = new List<Account>();
List<Account> stores = new List<Account>();
for (Integer i = 0; i < storeNums.size(); i++) {
    String nm = 'Burger King #' + storeNums[i];
    Account a = byName.containsKey(nm) ? byName.get(nm) : new Account(Name = nm);
    a.ParentId = corp.Id; a.Form_Scope__c = BRAND; a.Region__c = regions[i];
    storeUpserts.add(a); stores.add(a);
}
// Existing demo stores join the portfolio; #4421 keeps its store-specific scope.
Account s4421 = [SELECT Id, Name FROM Account WHERE Name = 'Burger King #4421' LIMIT 1];
s4421.ParentId = corp.Id; s4421.Region__c = 'Southeast';
Account s2188 = [SELECT Id, Name FROM Account WHERE Name = 'Burger King #2188' LIMIT 1];
s2188.ParentId = corp.Id; s2188.Region__c = 'Southeast';
storeUpserts.add(s4421); storeUpserts.add(s2188);
stores.add(s4421); stores.add(s2188);
upsert storeUpserts;

Set<String> driftNames = new Set<String>{'Burger King #4421', 'Burger King #1037', 'Burger King #1162'};

// ---- 2. Catalog entries (the stable question dimension reports group by) ----
List<String> questions = new List<String>{
    'Is the freezer hardware seal #3 intact?',
    'Are floor drains clean and free of residue?',
    'Is there any evidence of pest activity?',
    'Are handwash stations stocked and accessible?',
    'Are cold-holding temperature logs current?',
    'Are food-contact surfaces sanitized per schedule?'};
Map<String, Id> catByQ = new Map<String, Id>();
Set<String> wanted = new Set<String>(questions);
for (Form_Question_Catalog__c c : [SELECT Id, Question__c FROM Form_Question_Catalog__c
        WHERE Scope__c = :BRAND]) {
    if (wanted.contains(c.Question__c)) catByQ.put(c.Question__c, c.Id);
}
List<Form_Question_Catalog__c> newCats = new List<Form_Question_Catalog__c>();
for (String q : questions) {
    if (!catByQ.containsKey(q)) {
        newCats.add(new Form_Question_Catalog__c(
            Question__c = q, Scope__c = BRAND, Type__c = 'Pass Fail NA', Is_Curated__c = true,
            Weight__c = 10, Failure_Auto_Finding__c = true,
            Failure_Severity__c = (q.contains('freezer') || q.contains('pest')) ? 'High' : 'Medium',
            Failure_Photo_Required__c = q.contains('freezer')));
    }
}
insert newCats;
for (Form_Question_Catalog__c c : newCats) catByQ.put(c.Question__c, c.Id);
Id sealCat = catByQ.get(questions[0]);
List<String> rotating = new List<String>{questions[1], questions[2], questions[3], questions[4], questions[5]};

// ---- 3. Inspections ----
List<Date> months = new List<Date>{
    Date.newInstance(2025,12,1), Date.newInstance(2026,1,1), Date.newInstance(2026,2,1),
    Date.newInstance(2026,3,1),  Date.newInstance(2026,4,1), Date.newInstance(2026,5,1)};
List<String> monthLabel = new List<String>{'Dec 2025','Jan 2026','Feb 2026','Mar 2026','Apr 2026','May 2026'};
List<Integer> driftBase = new List<Integer>{93, 92, 90, 87, 83, 79};

List<Linked_Form__c> lfs = new List<Linked_Form__c>();
List<Boolean> lfIsDrift = new List<Boolean>();
List<Integer> lfMonth = new List<Integer>();
for (Integer si = 0; si < stores.size(); si++) {
    Account st = stores[si];
    Boolean drift = driftNames.contains(st.Name);
    Boolean rookie = Math.mod(si, 5) < 2;          // ~40% of stores get the rookie
    Id inspector = rookie ? MATT : ALAN;
    Integer tier = Math.mod(si, 3);                 // store quality tier
    for (Integer m = 0; m < months.size(); m++) {
        Integer score;
        if (drift) {
            score = driftBase[m] + (Integer) Math.round(Math.random() * 2);
        } else {
            score = (tier == 0 ? 96 : (tier == 1 ? 92 : 88))
                + (Integer) Math.round(Math.random() * 4) - 2
                + (rookie ? -4 + (Integer) Math.round(0.6 * m) : 1);
        }
        score = Math.min(99, Math.max(70, score));
        Date visit = months[m].addDays(2 + Math.mod(si * 7, 24));
        Integer dur = rookie
            ? 78 - 4 * m + (Integer) Math.round(Math.random() * 8)
            : 40 - m + (Integer) Math.round(Math.random() * 6);
        Datetime started = Datetime.newInstance(visit, Time.newInstance(8 + Math.mod(si, 6), 15, 0, 0));
        lfs.add(new Linked_Form__c(
            Form_Template__c = tpl.Id, Account__c = st.Id, Status__c = 'Completed',
            Visit_Date__c = visit, Started_At__c = started,
            Completed_At__c = started.addMinutes(dur), Fill_Duration_Minutes__c = dur,
            Completed_By__c = inspector,
            Inspector_Tenure_Months__c = rookie ? 1 + m : 67 + m,
            Score__c = score, Max_Score__c = 100,
            Re_Roll__c = drift && m >= 4,
            Signed_By_Name__c = 'Store Manager on duty',
            Signature_Captured_At__c = started.addMinutes(dur)));
        lfIsDrift.add(drift); lfMonth.add(m);
    }
}
insert lfs;

// ---- 4. Findings ----
List<String> sealNotes = new List<String>{
    'Minor condensation observed near upper hinge of seal #3. Wiped down; monitor next visit.',
    'Condensation recurring on upper hinge of seal #3. Seal compression looks uneven.',
    'Condensation pooling at upper hinge; gasket edge lifting ~2mm. Recommend service.',
    'Heavy condensation and visible frost line at seal #3. Hardware replacement recommended.'};
List<String> sevCycle = new List<String>{'Low', 'Medium', 'Medium', 'High'};
Date staleCutoff = Date.today().addDays(-45);

List<Form_Finding__c> finds = new List<Form_Finding__c>();
Map<Id, Integer> openCount = new Map<Id, Integer>();
Map<Id, Integer> blockCount = new Map<Id, Integer>();
for (Integer i = 0; i < lfs.size(); i++) {
    Linked_Form__c lf = lfs[i];
    openCount.put(lf.Id, 0); blockCount.put(lf.Id, 0);
    Integer m = lfMonth[i];
    Integer score = (Integer) lf.Score__c;
    Integer n = score >= 95 ? (Math.random() < 0.4 ? 1 : 0) : (score >= 90 ? 1 : (score >= 85 ? 2 : 3));
    Boolean isStale = lf.Visit_Date__c < staleCutoff;

    // Recurring freezer-seal pattern at the drift cluster (last 4 months).
    if (lfIsDrift[i] && m >= 2) {
        Boolean recent = m >= 4;
        String status = recent ? 'Open' : 'Resolved';
        if (status == 'Open') openCount.put(lf.Id, openCount.get(lf.Id) + 1);
        finds.add(new Form_Finding__c(
            Linked_Form__c = lf.Id,
            Form_Question_Catalog__c = sealCat,
            Severity__c = recent ? 'High' : 'Medium', Status__c = status,
            Notes__c = sealNotes[m - 2],
            Photo_Required__c = true, Photo_Attached__c = m != 3,
            Due_Date__c = status == 'Open' ? lf.Visit_Date__c.addDays(14) : null));
        n = Math.max(0, n - 1);
    }
    for (Integer k = 0; k < n; k++) {
        String q = rotating[Math.mod(i + k, rotating.size())];
        String sev = sevCycle[Math.mod(i + k, sevCycle.size())];
        Double roll = Math.random();
        String status = isStale
            ? (roll < 0.85 ? 'Resolved' : (roll < 0.95 ? 'Open' : 'Waived'))
            : (roll < 0.45 ? 'Open' : (roll < 0.70 ? 'In Progress' : 'Resolved'));
        if (status == 'Open' || status == 'In Progress') {
            openCount.put(lf.Id, openCount.get(lf.Id) + 1);
            if (sev == 'Critical') blockCount.put(lf.Id, blockCount.get(lf.Id) + 1);
        }
        Boolean photoReq = sev == 'High' || sev == 'Critical';
        finds.add(new Form_Finding__c(
            Linked_Form__c = lf.Id, Form_Question_Catalog__c = catByQ.get(q),
            Severity__c = sev, Status__c = status,
            Photo_Required__c = photoReq,
            Photo_Attached__c = photoReq ? Math.random() < 0.85 : Math.random() < 0.5,
            Due_Date__c = status == 'Open' ? lf.Visit_Date__c.addDays(14) : null));
    }
}
insert finds;

List<Linked_Form__c> countUpdates = new List<Linked_Form__c>();
for (Linked_Form__c lf : lfs) {
    countUpdates.add(new Linked_Form__c(Id = lf.Id,
        Findings_Open_Count__c = openCount.get(lf.Id),
        Findings_Blocking_Count__c = blockCount.get(lf.Id)));
}
update countUpdates;

// ---- 5. Anomaly alerts (the escalation feed) ----
Id latest4421;
for (Integer i = lfs.size() - 1; i >= 0; i--) {
    if (lfs[i].Account__c == s4421.Id) { latest4421 = lfs[i].Id; break; }
}
Map<String, Id> storeIdByName = new Map<String, Id>();
for (Account a : stores) storeIdByName.put(a.Name, a.Id);
insert new List<Anomaly_Alert__c>{
    new Anomaly_Alert__c(
        Account__c = s4421.Id, Linked_Form__c = latest4421, Brand_Contact__c = LAUREN_CONTACT,
        Pattern_Summary__c = 'Freezer hardware seal #3 — condensation recurring on upper hinge',
        Recurrence_Count__c = 4, Status__c = 'New',
        Dedupe_Key__c = 'SEED:' + s4421.Id + ':freezer-seal',
        Draft_Message__c = 'Hi Jen — flagging a pattern our inspections have picked up at store #4421: '
            + 'condensation on the upper hinge of freezer seal #3 has recurred across the last four visits '
            + 'and is now presenting with a frost line. We recommend scheduling hardware replacement before '
            + 'it affects cold-holding compliance. Full inspection history is in your portal. — Steritech'),
    new Anomaly_Alert__c(
        Account__c = storeIdByName.get('Burger King #1037'), Brand_Contact__c = LAUREN_CONTACT,
        Pattern_Summary__c = 'Floor drain residue — sanitation finding repeated 3 consecutive visits',
        Recurrence_Count__c = 3, Status__c = 'Reviewed',
        Dedupe_Key__c = 'SEED:' + storeIdByName.get('Burger King #1037') + ':floor-drains'),
    new Anomaly_Alert__c(
        Account__c = storeIdByName.get('Burger King #1408'), Brand_Contact__c = LAUREN_CONTACT,
        Pattern_Summary__c = 'Cold-holding temperature log gaps on weekend shifts',
        Recurrence_Count__c = 2, Status__c = 'Sent',
        Dedupe_Key__c = 'SEED:' + storeIdByName.get('Burger King #1408') + ':temp-logs')};

System.debug('SEED stores=' + stores.size() + ' inspections=' + lfs.size()
    + ' findings=' + finds.size() + ' template=' + tpl.Id);
