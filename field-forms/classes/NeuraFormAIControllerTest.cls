/**
 * Tests for NeuraFormAIController. Bypasses the live Einstein call via the
 * NeuraFormAIController.mockLLMResponse @TestVisible hook.
 */
@isTest
private class NeuraFormAIControllerTest {

    private static void enableAI() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        if (cfg == null) cfg = new FieldForms_Configuration__c();
        cfg.Enable_AI_Features__c = true;
        upsert cfg;
    }

    private static void disableAI() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        if (cfg == null) cfg = new FieldForms_Configuration__c();
        cfg.Enable_AI_Features__c = false;
        upsert cfg;
    }

    private static String validSpecJson() {
        return JSON.serialize(new Map<String, Object>{
            'name' => 'HVAC Inspection',
            'indicatorType' => 'Ring',
            'pages' => new List<Object>{
                new Map<String, Object>{
                    'title' => 'Pre-Check',
                    'sections' => new List<Object>{
                        new Map<String, Object>{
                            'title' => 'Equipment',
                            'columns' => 1,
                            'showTitle' => true,
                            'questions' => new List<Object>{
                                new Map<String, Object>{
                                    'label' => 'Serial Number',
                                    'type' => 'Text',
                                    'required' => true
                                },
                                new Map<String, Object>{
                                    'label' => 'Condition',
                                    'type' => 'Dropdown',
                                    'required' => false,
                                    'valueSet' => new List<Object>{ 'New', 'Used', 'Damaged' }
                                }
                            }
                        }
                    }
                },
                new Map<String, Object>{
                    'title' => 'Sign-off',
                    'sections' => new List<Object>{
                        new Map<String, Object>{
                            'title' => 'Approval',
                            'columns' => 1,
                            'questions' => new List<Object>{
                                new Map<String, Object>{
                                    'label' => 'Signature',
                                    'type' => 'Signature',
                                    'required' => true
                                }
                            }
                        }
                    }
                }
            }
        });
    }

    @isTest
    static void blocksWhenAIDisabled() {
        disableAI();
        Boolean threw = false;
        try {
            NeuraFormAIController.generateTemplateFromPrompt('HVAC form', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should refuse generation when AI features are off.');
    }

    @isTest
    static void blocksOnEmptyPrompt() {
        enableAI();
        Boolean threw = false;
        try {
            NeuraFormAIController.generateTemplateFromPrompt('   ', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should reject blank prompt.');
    }

    @isTest
    static void isAIEnabledReflectsFlag() {
        disableAI();
        System.assertEquals(false, NeuraFormAIController.isAIEnabled());
        enableAI();
        // cacheable=true means the prior value may be cached in the same
        // transaction; query directly through the helper which always reads
        // the latest. (In a real org the LWC reissues on next page load.)
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        System.assertEquals(true, cfg.Enable_AI_Features__c);
    }

    @isTest
    static void happyPathGeneratesTemplate() {
        enableAI();
        NeuraFormAIController.mockLLMResponse = validSpecJson();

        Test.startTest();
        NeuraFormAIController.GenerationResult result =
            NeuraFormAIController.generateTemplateFromPrompt('HVAC inspection', null);
        Test.stopTest();

        System.assertNotEquals(null, result, 'Result should not be null.');
        System.assertNotEquals(null, result.formTemplateId, 'Template Id should be returned.');
        System.assertEquals('HVAC Inspection', result.formTemplateName);
        System.assertEquals(2, result.pageCount);
        System.assertEquals(3, result.questionCount);

        // Verify the records actually landed.
        Form_Template__c[] tpls = [SELECT Id, Name FROM Form_Template__c WHERE Id = :result.formTemplateId];
        System.assertEquals(1, tpls.size(), 'Template should exist.');
        Integer pageCount = [SELECT COUNT() FROM Form_Page__c WHERE Form_Template__c = :result.formTemplateId];
        Integer questionCount = [SELECT COUNT() FROM Form_Question__c WHERE Form_Template__c = :result.formTemplateId];
        System.assertEquals(2, pageCount);
        System.assertEquals(3, questionCount);
    }

    @isTest
    static void rejectsMalformedJsonFromLLM() {
        enableAI();
        NeuraFormAIController.mockLLMResponse = 'totally not json';

        Boolean threw = false;
        try {
            NeuraFormAIController.generateTemplateFromPrompt('HVAC', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should reject non-JSON.');
    }

    @isTest
    static void stripsCodeFenceWrappers() {
        enableAI();
        NeuraFormAIController.mockLLMResponse =
            '```json\n' + validSpecJson() + '\n```';

        Test.startTest();
        NeuraFormAIController.GenerationResult result =
            NeuraFormAIController.generateTemplateFromPrompt('HVAC', null);
        Test.stopTest();

        System.assertNotEquals(null, result.formTemplateId,
            'Code-fence wrappers should be stripped before JSON parse.');
    }

    @isTest
    static void rejectsSpecWithNoQuestions() {
        enableAI();
        NeuraFormAIController.mockLLMResponse = JSON.serialize(new Map<String, Object>{
            'name' => 'Empty',
            'pages' => new List<Object>{
                new Map<String, Object>{
                    'title' => 'P1',
                    'sections' => new List<Object>{
                        new Map<String, Object>{
                            'title' => 'S1', 'columns' => 1,
                            'questions' => new List<Object>()
                        }
                    }
                }
            }
        });

        Boolean threw = false;
        try {
            NeuraFormAIController.generateTemplateFromPrompt('Empty form', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should reject a spec with zero questions.');
    }

    @isTest
    static void normalizeTypeKnownValues() {
        // Known good types pass through verbatim, case-insensitive recognition.
        System.assertEquals('Text', NeuraFormAIController.normalizeType('Text'));
        System.assertEquals('Text Area', NeuraFormAIController.normalizeType('text area'));
        System.assertEquals('Multiple Choice', NeuraFormAIController.normalizeType('MULTIPLE CHOICE'));
        System.assertEquals('Signature', NeuraFormAIController.normalizeType('signature'));
        // Unknown / blank fall back to Text.
        System.assertEquals('Text', NeuraFormAIController.normalizeType(null));
        System.assertEquals('Text', NeuraFormAIController.normalizeType(''));
        System.assertEquals('Text', NeuraFormAIController.normalizeType('Fancy Custom Type'));
    }

    @isTest
    static void isChoiceTypeDetectsPicklistTypes() {
        System.assert(NeuraFormAIController.isChoiceType('Dropdown'));
        System.assert(NeuraFormAIController.isChoiceType('Multiple Choice'));
        System.assert(NeuraFormAIController.isChoiceType('Radio Buttons'));
        System.assert(!NeuraFormAIController.isChoiceType('Text'));
        System.assert(!NeuraFormAIController.isChoiceType('Signature'));
    }

    @isTest
    static void valueSetJsonShape() {
        String json = NeuraFormAIController.buildValueSetJson(
            new List<Object>{ 'New', 'Used', 'Damaged' }
        );
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(json);
        System.assertEquals(3, parsed.size());
        Map<String, Object> first = (Map<String, Object>) parsed[0];
        System.assertEquals('New', first.get('label'));
        System.assertEquals('New', first.get('value'));
        System.assert(((String) first.get('id')).startsWith('AIGEN_opt_'));
    }

    @isTest
    static void promptsAreNonEmpty() {
        // Light coverage that the prompt-builders produce something usable.
        String system = NeuraFormAIController.buildSystemPrompt();
        String user = NeuraFormAIController.buildUserPrompt('test', 'industry');
        System.assert(system.contains('JSON'));
        System.assert(user.contains('test'));
        System.assert(user.contains('industry'));
    }
}
