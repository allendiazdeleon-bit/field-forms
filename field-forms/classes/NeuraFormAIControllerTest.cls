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

        // Guard the spec->import contract: the question text, type, and page FK
        // must actually land. (A prior bug routed this through the adapter
        // pipeline, which dropped Question__c/Type__c/Form_Page__c.) Question__c
        // is a long-text field and can't be filtered in SOQL, so order by
        // Order__c and assert on the first question ("Serial Number", Text, required).
        List<Form_Question__c> qs = [
            SELECT Question__c, Type__c, Required__c, Form_Page__c, Form_Section__c
            FROM Form_Question__c
            WHERE Form_Template__c = :result.formTemplateId
            ORDER BY Order__c
        ];
        Form_Question__c serial = qs[0];
        System.assertEquals('Serial Number', serial.Question__c, 'Question text should persist.');
        System.assertEquals('Text', serial.Type__c, 'Question type should persist.');
        System.assertEquals(true, serial.Required__c, 'Required flag should persist.');
        System.assertNotEquals(null, serial.Form_Page__c, 'Question should be linked to a page.');
        System.assertNotEquals(null, serial.Form_Section__c, 'Question should be linked to a section.');
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
        // Note: do NOT name the local "json" - Apex is case-insensitive,
        // so the local would shadow the System.JSON class and the
        // deserializeUntyped call on the next line would target String.
        String jsonStr = NeuraFormAIController.buildValueSetJson(
            new List<Object>{ 'New', 'Used', 'Damaged' }
        );
        List<Object> parsed = (List<Object>) JSON.deserializeUntyped(jsonStr);
        System.assertEquals(3, parsed.size());
        Map<String, Object> first = (Map<String, Object>) parsed[0];
        System.assertEquals('New', first.get('label'));
        System.assertEquals('New', first.get('value'));
        System.assert(((String) first.get('id')).startsWith('AIGEN_opt_'));
    }

    @isTest
    static void promptsAreNonEmpty() {
        // "system" is a reserved identifier (collides with the System class);
        // use a different name for the local.
        String systemPrompt = NeuraFormAIController.buildSystemPrompt();
        String userPrompt = NeuraFormAIController.buildUserPrompt('test', 'industry');
        System.assert(systemPrompt.contains('JSON'));
        System.assert(userPrompt.contains('test'));
        System.assert(userPrompt.contains('industry'));
    }

    @isTest
    static void generatesFromDocumentAndStampsScope() {
        enableAI();
        NeuraFormAIController.mockLLMResponse = validSpecJson();

        Test.startTest();
        NeuraFormAIController.GenerationResult result =
            NeuraFormAIController.generateTemplateFromDocument(
                'BURGER KING FOOD SAFETY AUDIT\nSection 1: Refrigeration\n1. Hardware Seal #3 (Intact/Damaged/Missing)',
                'BURGER_KING', null);
        Test.stopTest();

        System.assertNotEquals(null, result.formTemplateId, 'Template should be created from the document.');
        Form_Template__c tpl = [SELECT Scope__c FROM Form_Template__c WHERE Id = :result.formTemplateId];
        System.assertEquals('BURGER_KING', tpl.Scope__c,
            'Document import should land in the brand scope partition.');
    }

    @isTest
    static void adoptsCatalogTypeOverLlmGuess() {
        enableAI();
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        cfg.Question_Catalog_Enabled__c = true;
        upsert cfg;

        // Curated catalog entry: canonical type is Radio Buttons (the LLM will guess Dropdown).
        Form_Question_Catalog__c cat = new Form_Question_Catalog__c(
            Question__c = 'Hardware Seal #3', Type__c = 'Radio Buttons', Scope__c = 'ACME_CAT'
        );
        insert cat;

        NeuraFormAIController.mockLLMResponse = JSON.serialize(new Map<String, Object>{
            'name' => 'Audit',
            'pages' => new List<Object>{ new Map<String, Object>{
                'title' => 'P1', 'sections' => new List<Object>{ new Map<String, Object>{
                    'title' => 'S1', 'columns' => 1, 'questions' => new List<Object>{
                        new Map<String, Object>{
                            'label' => 'Hardware Seal #3', 'type' => 'Dropdown', 'required' => true,
                            'valueSet' => new List<Object>{ 'Intact', 'Damaged' }
                        }
                    }
                }}
            }}
        });

        Test.startTest();
        NeuraFormAIController.GenerationResult r =
            NeuraFormAIController.generateTemplateFromDocument('A document long enough to pass.', 'ACME_CAT', null);
        Test.stopTest();

        Form_Question__c q = [
            SELECT Type__c, Form_Question_Catalog__c
            FROM Form_Question__c WHERE Form_Template__c = :r.formTemplateId LIMIT 1
        ];
        System.assertEquals('Radio Buttons', q.Type__c,
            'Catalog canonical type should override the LLM guess.');
        System.assertEquals(cat.Id, q.Form_Question_Catalog__c,
            'Matched question should be bound to the catalog entry.');
    }

    @isTest
    static void normalizeLabelMatchesIgnoringCaseAndPunctuation() {
        System.assertEquals('hardware seal #3', NeuraFormAIController.normalizeLabel('  Hardware   Seal #3?  '));
        System.assertEquals('prep surfaces sanitized', NeuraFormAIController.normalizeLabel('Prep surfaces sanitized?'));
    }

    @isTest
    static void blocksOnEmptyDocument() {
        enableAI();
        Boolean threw = false;
        try {
            NeuraFormAIController.generateTemplateFromDocument('   ', 'BURGER_KING', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should reject an empty document.');
    }

    @isTest
    static void draftsOutputTemplateAndStoresOnTheme() {
        enableAI();
        NeuraFormAIController.mockLLMResponse =
            '```html\n<div style="border-top:6px solid {{brand.primaryColor}}">' +
            '{{brand.headerText}}{{answers}}{{findings}}{{signature}}</div>\n```';

        Test.startTest();
        NeuraFormAIController.OutputTemplateResult r =
            NeuraFormAIController.draftOutputTemplateFromDocument(
                'ACME AUDIT\nSection 1: Safety\n1. Extinguisher present? Yes/No', 'ACME_OUT', null);
        Test.stopTest();

        System.assertNotEquals(null, r.brandThemeId, 'A brand theme should be created/updated.');
        System.assert(r.htmlLength > 0);
        Brand_Theme__c bt = [
            SELECT Scope__c, Output_Template_Html__c FROM Brand_Theme__c WHERE Id = :r.brandThemeId
        ];
        System.assertEquals('ACME_OUT', bt.Scope__c);
        System.assert(bt.Output_Template_Html__c.contains('{{answers}}'),
            'Template should be stored with merge tokens.');
        System.assert(!bt.Output_Template_Html__c.startsWith('```'),
            'Code fence should be stripped.');
    }

    @isTest
    static void draftOutputTemplateUpdatesExistingActiveTheme() {
        enableAI();
        Brand_Theme__c existing = new Brand_Theme__c(
            Scope__c = 'ACME_OUT', Active__c = true, Primary_Color__c = '#E4002B'
        );
        insert existing;
        NeuraFormAIController.mockLLMResponse = '<div>{{answers}}</div>';

        Test.startTest();
        NeuraFormAIController.OutputTemplateResult r =
            NeuraFormAIController.draftOutputTemplateFromDocument('doc text here', 'ACME_OUT', null);
        Test.stopTest();

        System.assertEquals(existing.Id, r.brandThemeId,
            'An existing active brand-level theme must be updated, not duplicated.');
        System.assertEquals(1, [SELECT COUNT() FROM Brand_Theme__c WHERE Scope__c = 'ACME_OUT']);
    }

    @isTest
    static void draftOutputTemplateRejectsTokenlessHtml() {
        enableAI();
        NeuraFormAIController.mockLLMResponse = '<div>no merge tokens at all</div>';
        Boolean threw = false;
        try {
            NeuraFormAIController.draftOutputTemplateFromDocument('doc text here', 'ACME_OUT', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'HTML without merge tokens is not a usable template.');
        System.assertEquals(0, [SELECT COUNT() FROM Brand_Theme__c WHERE Scope__c = 'ACME_OUT'],
            'A rejected draft must not create a theme.');
    }

    @isTest
    static void draftOutputTemplateRequiresScope() {
        enableAI();
        NeuraFormAIController.mockLLMResponse = '<div>{{answers}}</div>';
        Boolean threw = false;
        try {
            NeuraFormAIController.draftOutputTemplateFromDocument('some doc', '  ', null);
        } catch (AuraHandledException e) {
            threw = true;
        }
        System.assert(threw, 'Should require a brand scope to attach the template.');
    }

    @isTest
    static void stripCodeFenceUnwrapsFencedHtml() {
        System.assertEquals('<div></div>',
            NeuraFormAIController.stripCodeFence('```html\n<div></div>\n```'));
        System.assertEquals('<p>x</p>',
            NeuraFormAIController.stripCodeFence('<p>x</p>'));
    }

    @isTest
    static void documentPromptCarriesFidelityRules() {
        String sys = NeuraFormAIController.buildDocumentSystemPrompt();
        System.assert(sys.contains('DOCUMENT-CONVERSION'), 'Doc system prompt should set conversion mode.');
        System.assert(sys.contains('faithfully'), 'Doc system prompt should stress fidelity.');
        String usr = NeuraFormAIController.buildDocumentUserPrompt('MY AUDIT DOC', 'pest control');
        System.assert(usr.contains('MY AUDIT DOC'));
        System.assert(usr.contains('pest control'));
    }
}
