/**
 * Sets up + audits scoring for the "BK Food Safety Inspection" template so the
 * demo scores cleanly with NO silent failures. Re-runnable / idempotent.
 *
 * Silent-failure surfaces this closes (see NeuraFormScoringEngine/Evaluator):
 *   1. Org    FieldForms_Configuration__c.Scoring_Enabled__c off  -> no scoring
 *   2. Template Scoring_Enabled__c off                            -> form skipped
 *   3. Template Max_Score__c null  -> Linked_Form.Max_Score__c null
 *      -> Score_Percent__c formula blank -> badge shows nothing
 *   4. Template Pass_Threshold_Percent__c null -> badge can't show pass/fail
 *   5. A Pass/Fail/NA question not bound to a catalog entry, or whose catalog
 *      Pass_Criteria__c is blank/malformed -> that answer silently scores 0/none
 *   6. Weight null -> engine defaults to 1, Max_Score (sum of weights) drifts
 *
 * Strategy: every "Pass Fail NA" question on the template MUST be bound to a
 * BURGER_KING catalog entry that has Weight + a valid self pass-rule. Missing
 * pieces are self-healed (bind by question text, create catalog if absent).
 * Max_Score is then the exact sum of those weights.
 */
String BRAND            = 'BURGER_KING';
String TEMPLATE_NAME    = 'BK Food Safety Inspection';
String SCORED_TYPE      = 'Pass Fail NA';
Decimal DEFAULT_WEIGHT  = 10;
Decimal PASS_THRESHOLD  = 80;
String  SELF_PASS_RULE  = '{"all":[{"resource":"self","operator":"equals","value":"pass"}]}';

List<String> log = new List<String>();
List<String> flags = new List<String>();
log.add('===== BK Food Safety Inspection — scoring setup =====');

// ---- 1) Org-level master flag (default org value, what getInstance() reads) ----
FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getOrgDefaults();
Boolean wasOrgOn = (cfg != null && cfg.Scoring_Enabled__c == true);
if (cfg == null) cfg = new FieldForms_Configuration__c();
cfg.SetupOwnerId = UserInfo.getOrganizationId();
cfg.Scoring_Enabled__c = true;
upsert cfg;
log.add('1. Org Scoring_Enabled__c (org default): ' + (wasOrgOn ? 'already ON' : 'SET ON'));

// ---- 2) Template ----
List<Form_Template__c> tpls = [
    SELECT Id, Name, Status__c, Scoring_Enabled__c, Max_Score__c, Pass_Threshold_Percent__c
    FROM Form_Template__c
    WHERE Name = :TEMPLATE_NAME AND Scope__c = :BRAND
    LIMIT 1];
if (tpls.isEmpty()) {
    log.add('ABORT: template "' + TEMPLATE_NAME + '" (scope ' + BRAND + ') not found.');
    log.add('       Run scripts/apex/seed-bk-demo-data.apex first, then re-run this.');
    System.debug(LoggingLevel.ERROR, '\n' + String.join(log, '\n'));
    return;
}
Form_Template__c tpl = tpls[0];
log.add('2. Template ' + tpl.Id + ' (Status=' + tpl.Status__c + ')');

// ---- 3) Load template questions + their catalog binding snapshot ----
List<Form_Question__c> qs = [
    SELECT Id, Question__c, Type__c, Form_Question_Catalog__c
    FROM Form_Question__c
    WHERE Form_Template__c = :tpl.Id
    ORDER BY Form_Page__r.Order__c NULLS FIRST, Order__c NULLS FIRST];

// Catalog lookup by question text (for self-heal binding / creation).
Map<String, Form_Question_Catalog__c> catByText = new Map<String, Form_Question_Catalog__c>();
for (Form_Question_Catalog__c c : [
        SELECT Id, Question__c, Weight__c, Pass_Criteria__c, Failure_Auto_Finding__c, Failure_Severity__c
        FROM Form_Question_Catalog__c WHERE Scope__c = :BRAND]) {
    if (c.Question__c != null) catByText.put(c.Question__c, c);
}

// ---- 4) Pass A: create any missing catalog entries for scored questions ----
List<Form_Question_Catalog__c> catsToInsert = new List<Form_Question_Catalog__c>();
List<Form_Question__c> scored = new List<Form_Question__c>();
for (Form_Question__c q : qs) {
    if (q.Type__c != SCORED_TYPE) continue;
    scored.add(q);
    if (q.Form_Question_Catalog__c == null && !catByText.containsKey(q.Question__c)) {
        Boolean hi = q.Question__c != null && (q.Question__c.toLowerCase().contains('freezer')
            || q.Question__c.toLowerCase().contains('pest'));
        Form_Question_Catalog__c nc = new Form_Question_Catalog__c(
            Question__c = q.Question__c, Scope__c = BRAND, Type__c = 'Pass Fail NA',
            Is_Curated__c = true, Weight__c = DEFAULT_WEIGHT, Failure_Auto_Finding__c = true,
            Failure_Severity__c = hi ? 'High' : 'Medium',
            Failure_Photo_Required__c = (q.Question__c != null && q.Question__c.toLowerCase().contains('freezer')),
            Pass_Criteria__c = SELF_PASS_RULE);
        catsToInsert.add(nc);
        catByText.put(q.Question__c, nc); // placeholder; Id filled after insert
    }
}
if (!catsToInsert.isEmpty()) {
    insert catsToInsert;
    flags.add('Created ' + catsToInsert.size() + ' missing catalog entr(ies) for unbound scored questions.');
}

// ---- 5) Pass B: bind questions + repair catalog weight/criteria ----
List<Form_Question__c> qUpdates = new List<Form_Question__c>();
Map<Id, Form_Question_Catalog__c> catFixById = new Map<Id, Form_Question_Catalog__c>();
Decimal maxScore = 0;
List<String> rows = new List<String>();

for (Form_Question__c q : scored) {
    Form_Question_Catalog__c cat;
    if (q.Form_Question_Catalog__c == null) {
        cat = catByText.get(q.Question__c);          // bound via self-heal
        q.Form_Question_Catalog__c = cat.Id;
        qUpdates.add(q);
    } else {
        // re-fetch the bound entry's scoring fields (snapshot above didn't carry them)
        cat = catByText.get(q.Question__c);
        if (cat == null || cat.Id != q.Form_Question_Catalog__c) {
            cat = [SELECT Id, Question__c, Weight__c, Pass_Criteria__c FROM Form_Question_Catalog__c
                   WHERE Id = :q.Form_Question_Catalog__c LIMIT 1];
        }
    }

    // Repair weight + criteria so nothing scores silently.
    Decimal w = cat.Weight__c;
    String pc = cat.Pass_Criteria__c;
    Boolean needFix = false;
    if (w == null) { w = DEFAULT_WEIGHT; needFix = true; }
    Boolean criteriaValid = false;
    if (String.isBlank(pc)) {
        pc = SELF_PASS_RULE; needFix = true;
    } else {
        try { JSON.deserializeUntyped(pc); criteriaValid = true; }
        catch (Exception e) { pc = SELF_PASS_RULE; needFix = true; }
    }
    if (!criteriaValid) { try { JSON.deserializeUntyped(pc); criteriaValid = true; } catch (Exception e) {} }
    // Flag cross-question refs (would mis-score on shared entries).
    if (criteriaValid && NeuraFormScoringEvaluator.referencesNonSelfResources(pc)) {
        flags.add('Catalog ' + cat.Id + ' ("' + q.Question__c + '") references non-self resources.');
    }
    if (needFix) {
        catFixById.put(cat.Id, new Form_Question_Catalog__c(Id = cat.Id, Weight__c = w, Pass_Criteria__c = pc));
    }
    maxScore += w;
    rows.add('   - "' + q.Question__c + '"  weight=' + w + '  bound=' + (q.Form_Question_Catalog__c != null)
        + '  criteria=' + (criteriaValid ? 'valid' : 'REPAIRED'));
}
if (!qUpdates.isEmpty()) { update qUpdates; flags.add('Bound ' + qUpdates.size() + ' previously-unbound question(s).'); }
if (!catFixById.isEmpty()) { update catFixById.values(); flags.add('Repaired weight/criteria on ' + catFixById.size() + ' catalog entr(ies).'); }

// ---- 6) Template scoring config ----
tpl.Scoring_Enabled__c = true;
tpl.Max_Score__c = maxScore;
tpl.Pass_Threshold_Percent__c = PASS_THRESHOLD;
update tpl;

log.add('3. Scored questions (Type=Pass Fail NA): ' + scored.size());
log.addAll(rows);
log.add('4. Template Scoring_Enabled__c = true');
log.add('5. Template Max_Score__c       = ' + maxScore + '  (sum of scored-question weights)');
log.add('6. Template Pass_Threshold_Percent__c = ' + PASS_THRESHOLD + '%');

// ---- 7) Verify (re-query the saved state) ----
Form_Template__c chk = [SELECT Scoring_Enabled__c, Max_Score__c, Pass_Threshold_Percent__c
    FROM Form_Template__c WHERE Id = :tpl.Id];
Integer unbound = [SELECT COUNT() FROM Form_Question__c
    WHERE Form_Template__c = :tpl.Id AND Type__c = :SCORED_TYPE AND Form_Question_Catalog__c = null];
// Pass_Criteria__c is long-text (not filterable) — count blanks in Apex.
Integer blankCrit = 0;
for (Form_Question__c q : [SELECT Form_Question_Catalog__r.Pass_Criteria__c
        FROM Form_Question__c
        WHERE Form_Template__c = :tpl.Id AND Type__c = :SCORED_TYPE]) {
    if (q.Form_Question_Catalog__c == null
        || q.Form_Question_Catalog__r == null
        || String.isBlank(q.Form_Question_Catalog__r.Pass_Criteria__c)) {
        blankCrit++;
    }
}
FieldForms_Configuration__c chkCfg = FieldForms_Configuration__c.getInstance();

log.add('===== VERIFY =====');
log.add('   org getInstance().Scoring_Enabled__c = ' + (chkCfg != null && chkCfg.Scoring_Enabled__c == true));
log.add('   template Scoring_Enabled = ' + chk.Scoring_Enabled__c
    + ' | Max_Score = ' + chk.Max_Score__c + ' | Threshold = ' + chk.Pass_Threshold_Percent__c + '%');
log.add('   scored questions still UNBOUND     = ' + unbound + (unbound == 0 ? ' (ok)' : ' <-- SILENT FAILURE'));
log.add('   scored questions with BLANK criteria = ' + blankCrit + (blankCrit == 0 ? ' (ok)' : ' <-- SILENT FAILURE'));

Boolean clean = (chkCfg != null && chkCfg.Scoring_Enabled__c == true)
    && chk.Scoring_Enabled__c == true && chk.Max_Score__c != null && chk.Max_Score__c > 0
    && chk.Pass_Threshold_Percent__c != null && unbound == 0 && blankCrit == 0;
log.add('   RESULT: ' + (clean ? 'CLEAN — scoring is demo-ready, no silent failures.'
                                : 'ISSUES REMAIN — see flags above.'));
if (!flags.isEmpty()) { log.add('----- changes/flags this run -----'); log.addAll(flags); }

System.debug(LoggingLevel.ERROR, '\n' + String.join(log, '\n'));
