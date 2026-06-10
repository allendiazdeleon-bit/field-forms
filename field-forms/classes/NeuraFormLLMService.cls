/**
 * Single Models API integration point for every Field Forms LLM feature
 * (AI form generation, real-time coaching, anomaly-escalation drafts).
 *
 * This is deliberately the ONLY class that references the aiplatform
 * namespace — the single point of compile-time coupling to the Einstein
 * Generative AI platform. Features carry their own error semantics on top:
 * chat() never throws; it returns null and records the cause in lastError,
 * so best-effort callers (coaching, escalation) fall back silently and
 * interactive callers (AI generation) re-raise lastError as an
 * AuraHandledException the UI can show.
 *
 * Opt-in gate: FieldForms_Configuration__c.Enable_AI_Features__c. Callers
 * check isEnabled() BEFORE invoking chat() — including async paths like the
 * anomaly queueable, so orgs that opted out never hit the Models API.
 */
public with sharing class NeuraFormLLMService {

    public static final String MODEL = 'sfdc_ai__DefaultGPT4Omni';

    // Test hook: when set, chat() returns this without a network call.
    @TestVisible private static String mockResponse = null;

    /** Human-readable cause of the most recent chat() failure; null after a
     *  successful call. Static per-transaction state, same as the hook. */
    public static String lastError = null;

    public static Boolean isEnabled() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        return cfg != null && cfg.Enable_AI_Features__c == true;
    }

    /**
     * One chat round trip through the Einstein Trust Layer. Returns the
     * generation text, or null on ANY failure (timeout, HTTP error, empty
     * response) — callers own the fallback behavior.
     */
    public static String chat(String systemPrompt, String userPrompt) {
        lastError = null;
        if (mockResponse != null) return mockResponse;
        try {
            aiplatform.ModelsAPI.createChatGenerations_Request request =
                new aiplatform.ModelsAPI.createChatGenerations_Request();
            request.modelName = MODEL;

            aiplatform.ModelsAPI_ChatGenerationsRequest body =
                new aiplatform.ModelsAPI_ChatGenerationsRequest();
            request.body = body;

            aiplatform.ModelsAPI_ChatMessageRequest sys =
                new aiplatform.ModelsAPI_ChatMessageRequest();
            sys.role = 'system';
            sys.content = systemPrompt;

            aiplatform.ModelsAPI_ChatMessageRequest usr =
                new aiplatform.ModelsAPI_ChatMessageRequest();
            usr.role = 'user';
            usr.content = userPrompt;

            body.messages = new List<aiplatform.ModelsAPI_ChatMessageRequest>{ sys, usr };

            aiplatform.ModelsAPI api = new aiplatform.ModelsAPI();
            aiplatform.ModelsAPI.createChatGenerations_Response response =
                api.createChatGenerations(request);

            if (response == null
                || response.Code200 == null
                || response.Code200.generationDetails == null
                || response.Code200.generationDetails.generations == null
                || response.Code200.generationDetails.generations.isEmpty()) {
                lastError = 'Einstein returned no generations.';
                return null;
            }
            return response.Code200.generationDetails.generations[0].content;
        } catch (aiplatform.ModelsAPI.createChatGenerations_ResponseException e) {
            // Keep the HTTP status: 403 = missing permission, 429 = usage
            // limit — that's the difference between "fix perms" and "wait".
            lastError = 'Einstein Models API call failed (HTTP ' + e.responseCode + '): ' + e.getMessage();
        } catch (Exception e) {
            lastError = e.getTypeName() + ': ' + e.getMessage();
        }
        System.debug(LoggingLevel.WARN, 'LLM call failed: ' + lastError);
        return null;
    }
}
