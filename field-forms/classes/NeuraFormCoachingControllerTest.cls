/**
 * Tests for NeuraFormCoachingController. The live LLM call is bypassed via the
 * mockLLMResponse @TestVisible hook; these tests cover the prior-visit query
 * and anomaly/recurrence detection.
 */
@isTest
private class NeuraFormCoachingControllerTest {

    private static void enableAI() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        if (cfg == null) cfg = new FieldForms_Configuration__c();
        cfg.Enable_AI_Features__c = true;
        upsert cfg;
    }

    private class Fixture {
        Id currentId;
        Id questionId;
    }

    /**
     * Builds a location with `priorVisits` completed inspections, each carrying
     * a finding with `note`, plus one in-progress "current" inspection.
     */
    private static Fixture buildHistory(Integer priorVisits, String note) {
        Form_Template__c tpl = new Form_Template__c(Name = 'Coaching Test Template');
        insert tpl;
        Form_Question__c q = new Form_Question__c(
            Question__c = 'Upper freezer hinge condition',
            Type__c = 'Dropdown', Form_Template__c = tpl.Id
        );
        insert q;
        Account acc = new Account(Name = 'Test Location');
        insert acc;

        List<Linked_Form__c> visits = new List<Linked_Form__c>();
        for (Integer i = 0; i < priorVisits; i++) {
            visits.add(new Linked_Form__c(
                Form_Template__c = tpl.Id, Account__c = acc.Id, Status__c = 'Completed',
                Visit_Date__c = Date.today().addDays(-7 * (priorVisits - i))
            ));
        }
        insert visits;

        List<Form_Answer__c> answers = new List<Form_Answer__c>();
        for (Linked_Form__c v : visits) {
            answers.add(new Form_Answer__c(
                Linked_Form__c = v.Id, Form_Question__c = q.Id,
                Answer__c = 'Condensation present', Type__c = 'Dropdown'
            ));
        }
        insert answers;
        Map<Id, Id> ansByVisit = new Map<Id, Id>();
        for (Form_Answer__c a : answers) ansByVisit.put(a.Linked_Form__c, a.Id);

        List<Form_Finding__c> findings = new List<Form_Finding__c>();
        for (Linked_Form__c v : visits) {
            findings.add(new Form_Finding__c(
                Linked_Form__c = v.Id, Form_Answer__c = ansByVisit.get(v.Id),
                Severity__c = 'Medium', Status__c = 'Open', Notes__c = note
            ));
        }
        insert findings;

        Linked_Form__c current = new Linked_Form__c(
            Form_Template__c = tpl.Id, Account__c = acc.Id, Status__c = 'In Progress'
        );
        insert current;

        Fixture f = new Fixture();
        f.currentId = current.Id;
        f.questionId = q.Id;
        return f;
    }

    @isTest
    static void coachesOnRecurringFinding() {
        enableAI();
        Fixture f = buildHistory(3, 'Condensation observed on upper freezer hinge.');
        NeuraFormCoachingController.mockLLMResponse =
            'The last 3 visits flagged condensation here. Want a closer photo of seal #3?';

        Test.startTest();
        NeuraFormCoachingController.CoachingResult r =
            NeuraFormCoachingController.getCoaching(f.currentId, f.questionId, 'Intact');
        Test.stopTest();

        System.assertEquals(true, r.hasCoaching, 'Recurring finding should produce coaching.');
        System.assertEquals(3, r.recurrenceCount, 'Finding recurred across 3 visits.');
        System.assertEquals(3, r.priorVisitCount);
        System.assertEquals(1, r.priorFindings.size());
        System.assertEquals('review', r.suggestedAction,
            'Medium severity suggests a history review; photo is reserved for High/Critical.');
        System.assert(r.message != null && r.message.contains('seal'), 'Coaching message returned.');
    }

    @isTest
    static void noCoachingWithoutPattern() {
        enableAI();
        // Only one prior visit with the finding -> below MIN_RECURRENCE.
        Fixture f = buildHistory(1, 'One-off issue.');
        NeuraFormCoachingController.mockLLMResponse = 'should not be used';

        Test.startTest();
        NeuraFormCoachingController.CoachingResult r =
            NeuraFormCoachingController.getCoaching(f.currentId, f.questionId, 'Intact');
        Test.stopTest();

        System.assertEquals(false, r.hasCoaching, 'A single occurrence is not a pattern.');
    }

    @isTest
    static void noCoachingWhenAIDisabled() {
        // AI off by default.
        Fixture f = buildHistory(3, 'Condensation observed on upper freezer hinge.');
        Test.startTest();
        NeuraFormCoachingController.CoachingResult r =
            NeuraFormCoachingController.getCoaching(f.currentId, f.questionId, 'Intact');
        Test.stopTest();
        System.assertEquals(false, r.hasCoaching, 'No coaching when AI features are off.');
    }

    @isTest
    static void fallsBackToDeterministicMessageWhenLLMFails() {
        enableAI();
        Fixture f = buildHistory(3, 'Condensation observed on upper freezer hinge.');
        // No mock set: the service's chat() attempts a real callout, which
        // fails in test context and returns null — the controller must
        // substitute the deterministic nudge, never hasCoaching=true with a
        // null message.
        Test.startTest();
        NeuraFormCoachingController.CoachingResult r =
            NeuraFormCoachingController.getCoaching(f.currentId, f.questionId, 'Intact');
        Test.stopTest();

        System.assertEquals(true, r.hasCoaching, 'Pattern exists; coaching should degrade, not vanish.');
        System.assert(String.isNotBlank(r.message),
            'hasCoaching=true must always carry a displayable message.');
        System.assert(r.message.contains('3 of the last 3 visits'),
            'Fallback message should cite the recurrence pattern.');
    }

    @isTest
    static void suggestsPhotoForHighSeverity() {
        enableAI();
        Fixture f = buildHistory(3, 'Exposed wiring near fryer station.');
        // Re-grade the seeded findings to Critical.
        List<Form_Finding__c> findings = [SELECT Id FROM Form_Finding__c];
        for (Form_Finding__c fin : findings) fin.Severity__c = 'Critical';
        update findings;
        NeuraFormCoachingController.mockLLMResponse = 'Check the wiring again?';

        Test.startTest();
        NeuraFormCoachingController.CoachingResult r =
            NeuraFormCoachingController.getCoaching(f.currentId, f.questionId, 'Looks fine');
        Test.stopTest();

        System.assertEquals('photo', r.suggestedAction,
            'Critical severity should ask for photo evidence.');
    }

    @isTest
    static void countsDistinctVisitsNotFindingRows() {
        enableAI();
        // One prior visit carrying the note twice: 2 finding rows, 1 visit —
        // below MIN_RECURRENCE.
        Fixture f = buildHistory(1, 'Duplicate note on same visit.');
        Form_Finding__c extra = [SELECT Id, Linked_Form__c, Form_Answer__c FROM Form_Finding__c LIMIT 1];
        insert new Form_Finding__c(
            Linked_Form__c = extra.Linked_Form__c, Form_Answer__c = extra.Form_Answer__c,
            Severity__c = 'Medium', Status__c = 'Open', Notes__c = 'Duplicate note on same visit.'
        );
        NeuraFormCoachingController.mockLLMResponse = 'should not be used';

        Test.startTest();
        NeuraFormCoachingController.CoachingResult r =
            NeuraFormCoachingController.getCoaching(f.currentId, f.questionId, 'Intact');
        Test.stopTest();

        System.assertEquals(false, r.hasCoaching,
            'Two identical findings on one visit are one occurrence, not a pattern.');
    }
}
