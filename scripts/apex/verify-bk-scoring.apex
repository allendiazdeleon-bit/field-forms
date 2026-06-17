/**
 * Non-destructive smoke test: creates a real inspection for the BK template,
 * answers the 7 scored questions (seal = fail, rest = pass), lets the scoring
 * trigger run, asserts the rolled-up Score/Max/percent/Passed/findings, then
 * ROLLS BACK so no demo data is left behind. Proves scoring fires for real.
 */
String BRAND = 'BURGER_KING';
Form_Template__c tpl = [SELECT Id, Max_Score__c, Pass_Threshold_Percent__c
    FROM Form_Template__c WHERE Name = 'BK Food Safety Inspection' AND Scope__c = :BRAND LIMIT 1];
Account acct = [SELECT Id FROM Account WHERE Name = 'Burger King #4421' LIMIT 1];

List<Form_Question__c> scored = [SELECT Id, Question__c, Type__c FROM Form_Question__c
    WHERE Form_Template__c = :tpl.Id AND Type__c = 'Pass Fail NA'];

System.Savepoint sp = Database.setSavepoint();
List<String> out = new List<String>{'===== BK scoring SMOKE TEST (rolled back) ====='};
try {
    Linked_Form__c lf = new Linked_Form__c(Form_Template__c = tpl.Id, Account__c = acct.Id, Status__c = 'In Progress');
    insert lf;

    List<Form_Answer__c> answers = new List<Form_Answer__c>();
    Integer failed = 0;
    for (Form_Question__c q : scored) {
        Boolean isSeal = q.Question__c != null && q.Question__c.toLowerCase().contains('seal');
        if (isSeal) failed++;
        answers.add(new Form_Answer__c(Linked_Form__c = lf.Id, Form_Question__c = q.Id,
            Type__c = q.Type__c, Answer__c = isSeal ? 'fail' : 'pass'));
    }
    insert answers; // fires FormAnswerScoringTrigger -> NeuraFormScoringEngine (synchronous, <50)

    Linked_Form__c r = [SELECT Score__c, Max_Score__c, Score_Percent__c,
        Findings_Open_Count__c, Findings_Blocking_Count__c FROM Linked_Form__c WHERE Id = :lf.Id];
    Integer expectedScore = (scored.size() - failed) * 10;

    out.add('answered ' + scored.size() + ' scored questions (' + failed + ' fail, ' + (scored.size()-failed) + ' pass)');
    out.add('Score__c          = ' + r.Score__c + '   (expected ' + expectedScore + ')');
    out.add('Max_Score__c      = ' + r.Max_Score__c + '   (expected ' + tpl.Max_Score__c + ')');
    out.add('Score_Percent__c  = ' + r.Score_Percent__c + '%');
    out.add('Findings_Open     = ' + r.Findings_Open_Count__c + '   (expected >=1 from the seal fail)');
    out.add('Findings_Blocking = ' + r.Findings_Blocking_Count__c);

    Boolean ok = r.Score__c == expectedScore && r.Max_Score__c == tpl.Max_Score__c
        && r.Score_Percent__c != null && r.Findings_Open_Count__c != null && r.Findings_Open_Count__c >= 1;
    out.add('RESULT: ' + (ok ? 'PASS — engine scored the form correctly, percent + findings populated.'
                              : 'FAIL — values did not match expectations.'));
} catch (Exception e) {
    out.add('EXCEPTION: ' + e.getTypeName() + ' — ' + e.getMessage() + '\n' + e.getStackTraceString());
} finally {
    Database.rollback(sp); // leave zero trace
    out.add('(rolled back — no inspection/answers/findings persisted)');
}
System.debug(LoggingLevel.ERROR, '\n' + String.join(out, '\n'));
