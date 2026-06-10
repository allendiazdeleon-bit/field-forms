/**
 * Tests for NeuraFormMobileController's dictation mapping — specifically the
 * normalization layer that stands behind the LLM: values must satisfy each
 * question's type contract or be dropped (a silently wrong answer is worse
 * than no answer; the tech trusts what appears filled in).
 */
@isTest
private class NeuraFormMobileControllerTest {

    private static NeuraFormMobileController.QuestionDescriptor q(
        String id, String label, String type, List<String> allowed
    ) {
        NeuraFormMobileController.QuestionDescriptor d =
            new NeuraFormMobileController.QuestionDescriptor();
        d.questionId = id;
        d.label = label;
        d.type = type;
        d.allowedValues = allowed;
        return d;
    }

    private static NeuraFormMobileController.MappedAnswer m(String id, String value) {
        NeuraFormMobileController.MappedAnswer ans =
            new NeuraFormMobileController.MappedAnswer();
        ans.questionId = id;
        ans.value = value;
        return ans;
    }

    @isTest
    static void snapsParaphrasedChoiceValuesToCanonical() {
        List<String> allowed = new List<String>{ 'Intact', 'Worn', 'Damaged' };
        System.assertEquals('Worn', NeuraFormMobileController.snapToAllowedValue('worn out', allowed));
        System.assertEquals('Intact', NeuraFormMobileController.snapToAllowedValue('INTACT', allowed));
        System.assertEquals('Damaged', NeuraFormMobileController.snapToAllowedValue('Damaged', allowed));
        System.assertEquals(null, NeuraFormMobileController.snapToAllowedValue('purple', allowed),
            'Unmatchable paraphrases return null so the mapping is dropped.');
    }

    @isTest
    static void normalizeEnforcesTypeContracts() {
        List<NeuraFormMobileController.QuestionDescriptor> questions =
            new List<NeuraFormMobileController.QuestionDescriptor>{
                q('PFN', 'Hinge condition', 'Pass Fail NA', new List<String>{ 'pass', 'fail', 'na' }),
                q('TOG', 'Pest activity observed', 'Toggle', null),
                q('NUM', 'Temperature', 'Number', null),
                q('TXT', 'Notes', 'Text Area', null)
            };
        List<NeuraFormMobileController.MappedAnswer> raw =
            new List<NeuraFormMobileController.MappedAnswer>{
                m('PFN', 'Fail'),              // case snap -> 'fail'
                m('TOG', 'na'),                // invalid boolean -> DROPPED
                m('NUM', '72 degrees'),        // digits extracted -> '72'
                m('TXT', 'condensation seen'), // free text passes through
                m('GHOST', 'anything')         // unknown question -> dropped
            };

        List<NeuraFormMobileController.MappedAnswer> out =
            NeuraFormMobileController.normalizeMappedAnswers(raw, questions);

        Map<String, String> byId = new Map<String, String>();
        for (NeuraFormMobileController.MappedAnswer a : out) byId.put(a.questionId, a.value);

        System.assertEquals('fail', byId.get('PFN'));
        System.assert(!byId.containsKey('TOG'),
            '"na" on a Toggle violates the true/false contract and must be dropped.');
        System.assertEquals('72', byId.get('NUM'));
        System.assertEquals('condensation seen', byId.get('TXT'));
        System.assert(!byId.containsKey('GHOST'));
    }

    @isTest
    static void normalizeCoercesBooleanPhrasings() {
        List<NeuraFormMobileController.QuestionDescriptor> questions =
            new List<NeuraFormMobileController.QuestionDescriptor>{
                q('T1', 'A', 'Toggle', null),
                q('T2', 'B', 'Toggle', null),
                q('T3', 'C', 'Checkbox', null)
            };
        List<NeuraFormMobileController.MappedAnswer> raw =
            new List<NeuraFormMobileController.MappedAnswer>{
                m('T1', 'Yes'), m('T2', 'not observed'), m('T3', 'none')
            };
        List<NeuraFormMobileController.MappedAnswer> out =
            NeuraFormMobileController.normalizeMappedAnswers(raw, questions);
        Map<String, String> byId = new Map<String, String>();
        for (NeuraFormMobileController.MappedAnswer a : out) byId.put(a.questionId, a.value);
        System.assertEquals('true', byId.get('T1'));
        System.assertEquals('false', byId.get('T2'));
        System.assertEquals('false', byId.get('T3'));
    }

    @isTest
    static void mappingEndToEndWithMockedLLM() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        if (cfg == null) cfg = new FieldForms_Configuration__c();
        cfg.Enable_AI_Features__c = true;
        upsert cfg;
        // The model paraphrases and case-mangles; the normalization layer
        // must still deliver canonical values to the LWC.
        NeuraFormLLMService.mockResponse =
            '{"mappings":[{"questionId":"Q1","value":"WORN"},{"questionId":"Q2","value":"about 72"}]}';

        List<NeuraFormMobileController.QuestionDescriptor> questions =
            new List<NeuraFormMobileController.QuestionDescriptor>{
                q('Q1', 'Door seal status', 'Dropdown', new List<String>{ 'Intact', 'Worn', 'Damaged' }),
                q('Q2', 'Temperature', 'Number', null)
            };

        Test.startTest();
        NeuraFormMobileController.MapResult r =
            NeuraFormMobileController.mapTranscriptToQuestions('door seal worn, temp 72', questions);
        Test.stopTest();

        System.assertEquals('agentforce', r.source);
        System.assertEquals(2, r.mappings.size());
        System.assertEquals('Worn', r.mappings[0].value);
        System.assertEquals('72', r.mappings[1].value);
    }

    @isTest
    static void fallsBackToHeuristicWhenLLMUnavailable() {
        // AI gate off -> invokeModelsAPI returns null -> heuristic path,
        // which also flows through normalization.
        List<NeuraFormMobileController.QuestionDescriptor> questions =
            new List<NeuraFormMobileController.QuestionDescriptor>{
                q('Q1', 'Door seal status', 'Dropdown', new List<String>{ 'Intact', 'Worn', 'Damaged' })
            };
        Test.startTest();
        NeuraFormMobileController.MapResult r =
            NeuraFormMobileController.mapTranscriptToQuestions('the door seal is worn', questions);
        Test.stopTest();
        System.assertEquals('heuristic', r.source);
    }
}
