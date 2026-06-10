/**
 * Tests for NeuraFormLLMService — the gate, the mock hook, and the
 * never-throws error contract.
 */
@isTest
private class NeuraFormLLMServiceTest {

    @isTest
    static void disabledByDefault() {
        System.assertEquals(false, NeuraFormLLMService.isEnabled(),
            'AI features are opt-in; default org state is disabled.');
    }

    @isTest
    static void enabledWhenConfigured() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        if (cfg == null) cfg = new FieldForms_Configuration__c();
        cfg.Enable_AI_Features__c = true;
        upsert cfg;
        System.assertEquals(true, NeuraFormLLMService.isEnabled());
    }

    @isTest
    static void mockHookBypassesCallout() {
        NeuraFormLLMService.mockResponse = 'canned';
        System.assertEquals('canned', NeuraFormLLMService.chat('sys', 'usr'));
        System.assertEquals(null, NeuraFormLLMService.lastError);
    }

    @isTest
    static void failureReturnsNullAndRecordsCause() {
        // No mock and no callout mock: the Models API call fails in test
        // context. The contract is null + lastError, never an exception.
        Test.startTest();
        String result = NeuraFormLLMService.chat('sys', 'usr');
        Test.stopTest();

        System.assertEquals(null, result, 'Failures return null, not throw.');
        System.assert(String.isNotBlank(NeuraFormLLMService.lastError),
            'The failure cause is recorded for interactive callers to surface.');
    }
}
