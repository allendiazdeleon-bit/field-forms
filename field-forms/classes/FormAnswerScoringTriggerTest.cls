/**
 * Coverage for FormAnswerScoringTrigger + NeuraFormScoringEngine.
 *
 * Exercises the full data flow: insert / update Form_Answer__c records,
 * assert Passed__c / Points_Earned__c on the answer, Form_Finding__c rows
 * on the linked form, and Linked_Form__c rollup fields. Each test seeds a
 * Form_Template_+_Catalog_+_Question_+_LinkedForm fixture independently
 * to keep failures localized.
 *
 * Test taxonomy:
 *   - Org flag off  -&gt; no work  (1 case)
 *   - Org flag on, template flag off  (1 case)
 *   - Pass + no finding  (1 case)
 *   - Fail + finding created  (1 case)
 *   - Pass -&gt; fail update (re-open finding)  (1 case)
 *   - Fail -&gt; pass update (auto-resolve finding)  (1 case)
 *   - Linked_Form score rollup  (1 case)
 *   - Bulk path  (1 case, &gt; BULK_THRESHOLD)
 *
 * 8 method-level test cases; each asserts 2-5 invariants.
 */
@IsTest
private class FormAnswerScoringTriggerTest {

    // ----- flag-off paths ---------------------------------------------------

    @IsTest
    static void orgFlagOff_noOpOnInsert() {
        Fixture f = makeFixture(false, true /* template on */, '{"resource":"self","operator":"equals","value":"Yes"}');
        Test.startTest();
        Form_Answer__c a = insertAnswer(f, 'Yes');
        Test.stopTest();

        Form_Answer__c reloaded = [SELECT Passed__c, Points_Earned__c FROM Form_Answer__c WHERE Id = :a.Id];
        System.assertEquals(false, reloaded.Passed__c);
        System.assertEquals(null, reloaded.Points_Earned__c,
            'Org flag off should not score the answer');
        System.assertEquals(0, findingsFor(f.linkedFormId).size(),
            'Org flag off should not auto-create findings');
    }

    @IsTest
    static void templateFlagOff_noOpOnInsert() {
        Fixture f = makeFixture(true, false /* template off */, '{"resource":"self","operator":"equals","value":"Yes"}');
        Test.startTest();
        Form_Answer__c a = insertAnswer(f, 'Yes');
        Test.stopTest();

        Form_Answer__c reloaded = [SELECT Passed__c, Points_Earned__c FROM Form_Answer__c WHERE Id = :a.Id];
        System.assertEquals(null, reloaded.Points_Earned__c,
            'Template flag off keeps Points_Earned null');
        System.assertEquals(0, findingsFor(f.linkedFormId).size());
    }

    // ----- pass / fail paths ------------------------------------------------

    @IsTest
    static void passAnswer_marksPassedNoFinding() {
        Fixture f = makeFixture(true, true, '{"resource":"self","operator":"equals","value":"Yes"}');
        Test.startTest();
        Form_Answer__c a = insertAnswer(f, 'Yes');
        Test.stopTest();

        Form_Answer__c reloaded = [SELECT Passed__c, Points_Earned__c FROM Form_Answer__c WHERE Id = :a.Id];
        System.assertEquals(true, reloaded.Passed__c);
        System.assertEquals(2, reloaded.Points_Earned__c,
            'Catalog Weight__c (2.0) should be awarded on pass');
        System.assertEquals(0, findingsFor(f.linkedFormId).size(),
            'Passing answer should not create a finding');
    }

    @IsTest
    static void failAnswer_createsFindingAndZeroesPoints() {
        Fixture f = makeFixture(true, true, '{"resource":"self","operator":"equals","value":"Yes"}');
        Test.startTest();
        Form_Answer__c a = insertAnswer(f, 'No');
        Test.stopTest();

        Form_Answer__c reloaded = [SELECT Passed__c, Points_Earned__c FROM Form_Answer__c WHERE Id = :a.Id];
        System.assertEquals(false, reloaded.Passed__c);
        System.assertEquals(0, reloaded.Points_Earned__c,
            'Failing answer earns zero points');

        List<Form_Finding__c> findings = findingsFor(f.linkedFormId);
        System.assertEquals(1, findings.size(),
            'Failing answer with Failure_Auto_Finding__c=true creates a finding');
        System.assertEquals('Open', findings[0].Status__c);
        System.assertEquals('High', findings[0].Severity__c,
            'Severity copied from catalog');
        System.assertEquals(true, findings[0].Photo_Required__c);
    }

    // ----- update transitions ----------------------------------------------

    @IsTest
    static void passToFailUpdate_reopensFinding() {
        Fixture f = makeFixture(true, true, '{"resource":"self","operator":"equals","value":"Yes"}');
        Form_Answer__c a = insertAnswer(f, 'Yes');
        // Sanity: no finding yet.
        System.assertEquals(0, findingsFor(f.linkedFormId).size());

        a.Answer__c = 'No';
        Test.startTest();
        update a;
        Test.stopTest();

        Form_Answer__c reloaded = [SELECT Passed__c FROM Form_Answer__c WHERE Id = :a.Id];
        System.assertEquals(false, reloaded.Passed__c);

        List<Form_Finding__c> findings = findingsFor(f.linkedFormId);
        System.assertEquals(1, findings.size(),
            'Pass-to-fail update should create the finding');
        System.assertEquals('Open', findings[0].Status__c);
    }

    @IsTest
    static void failToPassUpdate_autoResolvesFinding() {
        Fixture f = makeFixture(true, true, '{"resource":"self","operator":"equals","value":"Yes"}');
        Form_Answer__c a = insertAnswer(f, 'No');
        // Finding exists.
        System.assertEquals(1, findingsFor(f.linkedFormId).size());

        a.Answer__c = 'Yes';
        Test.startTest();
        update a;
        Test.stopTest();

        List<Form_Finding__c> findings = findingsFor(f.linkedFormId);
        System.assertEquals(1, findings.size(),
            'Auto-resolve keeps the finding, just transitions Status__c');
        System.assertEquals('Auto-Resolved', findings[0].Status__c);
    }

    // ----- rollup ----------------------------------------------------------

    @IsTest
    static void scoreRollup_sumsAcrossAnswers() {
        Fixture f = makeFixture(true, true, '{"resource":"self","operator":"equals","value":"Yes"}');
        // Add a second catalog/question pair with weight 3 so we can test
        // the rollup actually sums across answers.
        Form_Question_Catalog__c cat2 = new Form_Question_Catalog__c(
            External_Reference__c = 'Q-CAT-' + makeUniq(),
            Question__c = 'Q2',
            Weight__c = 3,
            Pass_Criteria__c = '{"resource":"self","operator":"equals","value":"Yes"}',
            Failure_Auto_Finding__c = false,
            Failure_Severity__c = 'Low'
        );
        insert cat2;
        Form_Question__c q2 = new Form_Question__c(
            Form_Template__c = f.templateId,
            Form_Section__c = f.sectionId,
            Question__c = 'Q2',
            Form_Question_Catalog__c = cat2.Id
        );
        insert q2;

        Test.startTest();
        Form_Answer__c a1 = insertAnswer(f, 'Yes');
        Form_Answer__c a2 = new Form_Answer__c(
            Linked_Form__c = f.linkedFormId,
            Form_Question__c = q2.Id,
            Answer__c = 'Yes',
            Type__c = 'Text'
        );
        insert a2;
        Test.stopTest();

        Linked_Form__c lf = [
            SELECT Score__c, Max_Score__c, Findings_Open_Count__c, Findings_Blocking_Count__c
            FROM Linked_Form__c WHERE Id = :f.linkedFormId
        ];
        System.assertEquals(5, lf.Score__c,
            'Score__c = 2 (q1 weight) + 3 (q2 weight) when both pass');
        System.assertEquals(0, lf.Findings_Open_Count__c);
        System.assertEquals(0, lf.Findings_Blocking_Count__c);
    }

    // ----- bulk path -------------------------------------------------------

    @IsTest
    static void bulkAnswers_enqueuesQueueable() {
        Fixture f = makeFixture(true, true, '{"resource":"self","operator":"equals","value":"Yes"}');

        // Build many questions sharing the catalog so we can write 60
        // answers in one DML and force the bulk path.
        List<Form_Question__c> questions = new List<Form_Question__c>();
        for (Integer i = 0; i < 60; i++) {
            questions.add(new Form_Question__c(
                Form_Template__c = f.templateId,
                Form_Section__c = f.sectionId,
                Question__c = 'Q-' + i,
                Form_Question_Catalog__c = f.catalogId
            ));
        }
        insert questions;

        List<Form_Answer__c> answers = new List<Form_Answer__c>();
        for (Form_Question__c q : questions) {
            answers.add(new Form_Answer__c(
                Linked_Form__c = f.linkedFormId,
                Form_Question__c = q.Id,
                Answer__c = 'Yes',
                Type__c = 'Text'
            ));
        }

        Test.startTest();
        insert answers;
        // No exception means the queueable enqueue worked. Test.stopTest
        // forces the queueable to execute synchronously, so we can assert
        // outcomes below.
        Test.stopTest();

        Linked_Form__c lf = [
            SELECT Score__c, Findings_Open_Count__c
            FROM Linked_Form__c WHERE Id = :f.linkedFormId
        ];
        System.assertEquals(120, lf.Score__c,
            '60 answers x weight 2 = 120');
        System.assertEquals(0, lf.Findings_Open_Count__c);
    }

    // ----- helpers ---------------------------------------------------------

    /** Internal fixture wrapping seed records used across tests. */
    private class Fixture {
        Id templateId;
        Id pageId;
        Id sectionId;
        Id catalogId;
        Id questionId;
        Id linkedFormId;
    }

    /**
     * Build a complete scoring fixture. orgFlag controls
     * FieldForms_Configuration__c.Scoring_Enabled__c; templateFlag controls
     * Form_Template__c.Scoring_Enabled__c. passCriteria is the catalog
     * Pass_Criteria__c JSON.
     */
    private static Fixture makeFixture(Boolean orgFlag, Boolean templateFlag, String passCriteria) {
        FieldForms_Configuration__c cfg = new FieldForms_Configuration__c();
        cfg.Scoring_Enabled__c = orgFlag;
        cfg.Disable_Form_Template_JSON_Trigger__c = true; // suppress unrelated snapshot work
        insert cfg;

        Form_Template__c t = new Form_Template__c(
            Name = 'Scoring Template',
            Scoring_Enabled__c = templateFlag,
            Pass_Threshold_Percent__c = 80,
            Max_Score__c = 10
        );
        insert t;

        Form_Page__c p = new Form_Page__c(Form_Template__c = t.Id, Order__c = 1, Title__c = 'P1');
        insert p;
        Form_Section__c s = new Form_Section__c(
            Form_Template__c = t.Id, Form_Page__c = p.Id, Name = 'S1');
        insert s;

        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            External_Reference__c = 'Q-CAT-' + makeUniq(),
            Question__c = 'Q1',
            Weight__c = 2,
            Pass_Criteria__c = passCriteria,
            Failure_Auto_Finding__c = true,
            Failure_Photo_Required__c = true,
            Failure_Severity__c = 'High'
        );
        insert cat;
        Form_Question__c q = new Form_Question__c(
            Form_Template__c = t.Id,
            Form_Section__c = s.Id,
            Question__c = 'Q1',
            Form_Question_Catalog__c = cat.Id
        );
        insert q;

        Linked_Form__c lf = new Linked_Form__c(Form_Template__c = t.Id);
        insert lf;

        Fixture f = new Fixture();
        f.templateId = t.Id;
        f.pageId = p.Id;
        f.sectionId = s.Id;
        f.catalogId = cat.Id;
        f.questionId = q.Id;
        f.linkedFormId = lf.Id;
        return f;
    }

    private static Form_Answer__c insertAnswer(Fixture f, String value) {
        Form_Answer__c a = new Form_Answer__c(
            Linked_Form__c = f.linkedFormId,
            Form_Question__c = f.questionId,
            Answer__c = value,
            Type__c = 'Text'
        );
        insert a;
        return a;
    }

    private static List<Form_Finding__c> findingsFor(Id linkedFormId) {
        return [
            SELECT Id, Status__c, Severity__c, Photo_Required__c, Photo_Attached__c,
                Blocks_Submission__c, Form_Answer__c
            FROM Form_Finding__c
            WHERE Linked_Form__c = :linkedFormId
            ORDER BY CreatedDate
        ];
    }

    private static Integer uniq = 0;
    private static String makeUniq() {
        uniq++;
        return String.valueOf(DateTime.now().getTime()) + '-' + uniq;
    }
}
