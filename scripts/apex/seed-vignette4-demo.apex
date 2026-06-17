/*
 * Vignette 4 demo seed — "Generates and sends a branded, signed report
 * before she leaves." Re-runnable (idempotent). Prepares BK #4421 so the
 * close-out flow renders a BK-red branded PDF, stamps the on-site signature
 * audit, emails the brand contact + Ops, and attaches the PDF to a Work Order.
 *
 * Run: sf apex run --file scripts/apex/seed-vignette4-demo.apex
 *
 * Email recipients use plus-addressing on the demo operator's own address so
 * the mail lands in one inbox to show live — change BRAND_EMAIL / OPS_EMAIL
 * below to real addresses if you want distinct recipients.
 */

// ---- Knobs ----------------------------------------------------------------
final Id BK4421_ACCOUNT   = '001Hn00002FHyXUIA1';      // Burger King #4421
final Id DEMO_INSPECTION  = 'a31Hn000003Jul3IAC';      // Maya's canonical visit (#000035)
final Id BK_THEME_ID      = 'a36Hn000008AHENIA4';      // BURGER_KING red theme to clone
final String BK4421_SCOPE = 'BURGER_KING_4421';        // this account's Form_Scope__c
final String BRAND_EMAIL  = 'allen.diazdeleon+bkstore@neuraflash.com';
final String OPS_EMAIL    = 'allen.diazdeleon+ops@neuraflash.com';
// Reliable, hotlinkable logo (Google's favicon service — Google-hosted PNG
// that renders in both the server-rendered PDF and external email clients).
// The previously seeded logo.clearbit.com URL was sunset and no longer loads.
final String LOGO_URL     = 'https://www.google.com/s2/favicons?domain=burgerking.com&sz=128';

List<String> log = new List<String>();

// ---- 1. Ops notification email (org-default custom setting) ----------------
FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getOrgDefaults();
if (cfg == null) { cfg = new FieldForms_Configuration__c(); cfg.SetupOwnerId = UserInfo.getOrganizationId(); }
cfg.Report_Notification_Email__c = OPS_EMAIL;
cfg.Enable_AI_Features__c = true;
upsert cfg;
log.add('Config: Report_Notification_Email__c = ' + OPS_EMAIL + ', AI on');

// ---- 2. Brand contact on BK #4421 -----------------------------------------
List<Contact> jens = [SELECT Id FROM Contact WHERE LastName = 'Patel' AND FirstName = 'Jen' LIMIT 1];
Contact jen = jens.isEmpty()
    ? new Contact(FirstName = 'Jen', LastName = 'Patel')
    : jens[0];
jen.AccountId = BK4421_ACCOUNT;
jen.Email = BRAND_EMAIL;
upsert jen;
log.add('Brand contact: Jen Patel @ BK#4421, email ' + BRAND_EMAIL + ' (' + jen.Id + ')');

// ---- 3. BK-red theme scoped to this account's scope ------------------------
List<Brand_Theme__c> existing = [
    SELECT Id FROM Brand_Theme__c WHERE Scope__c = :BK4421_SCOPE AND Form_Template__c = null LIMIT 1
];
if (existing.isEmpty()) {
    Brand_Theme__c src = [
        SELECT Primary_Color__c, Secondary_Color__c, Header_Text__c,
               Section_Order__c, Locale__c, Output_Template_Html__c
        FROM Brand_Theme__c WHERE Id = :BK_THEME_ID LIMIT 1
    ];
    insert new Brand_Theme__c(
        Scope__c = BK4421_SCOPE,
        Active__c = true,
        Primary_Color__c = src.Primary_Color__c,
        Secondary_Color__c = src.Secondary_Color__c,
        Logo_URL__c = LOGO_URL,
        Header_Text__c = src.Header_Text__c,
        Section_Order__c = src.Section_Order__c,
        Locale__c = src.Locale__c,
        Output_Template_Html__c = src.Output_Template_Html__c
    );
    log.add('Theme: cloned BK-red theme to scope ' + BK4421_SCOPE);
} else {
    log.add('Theme: ' + BK4421_SCOPE + ' theme already present (' + existing[0].Id + ')');
}

// Repair the logo on every BK theme (the seeded clearbit URL is dead) so a
// re-run always leaves a working logo on both the brand and per-store themes.
List<Brand_Theme__c> bkThemes = [
    SELECT Id, Logo_URL__c FROM Brand_Theme__c
    WHERE Scope__c = 'BURGER_KING' OR Scope__c = :BK4421_SCOPE
];
for (Brand_Theme__c bt : bkThemes) bt.Logo_URL__c = LOGO_URL;
update bkThemes;
log.add('Logo: set ' + bkThemes.size() + ' BK theme(s) to ' + LOGO_URL);

// ---- 4. Work Order on BK #4421 (find-or-create) ----------------------------
final String WO_SUBJECT = 'Food Safety Inspection — BK #4421 (demo)';
List<WorkOrder> wos = [
    SELECT Id FROM WorkOrder WHERE AccountId = :BK4421_ACCOUNT AND Subject = :WO_SUBJECT LIMIT 1
];
WorkOrder wo = wos.isEmpty() ? new WorkOrder(AccountId = BK4421_ACCOUNT, Subject = WO_SUBJECT) : wos[0];
upsert wo;
log.add('Work Order: ' + wo.Id + ' on BK#4421');

// ---- 5. Reset the canonical inspection to a completable state --------------
Linked_Form__c lf = [
    SELECT Id, Status__c, Work_Order__c, Signed_By_Name__c, Signature_Captured_At__c
    FROM Linked_Form__c WHERE Id = :DEMO_INSPECTION LIMIT 1
];
lf.Status__c = 'In Progress';
lf.Work_Order__c = wo.Id;
lf.Signed_By_Name__c = null;
lf.Signature_Captured_At__c = null;
lf.Signature_Latitude__c = null;
lf.Signature_Longitude__c = null;
lf.Completed_At__c = null;
lf.Completed_By__c = null;
update lf;
log.add('Inspection ' + DEMO_INSPECTION + ' reset to In Progress, linked to WO, signature cleared');

System.debug('==== VIGNETTE 4 DEMO SEED ====');
for (String l : log) System.debug('  ✓ ' + l);
System.debug('==== DONE ====');
