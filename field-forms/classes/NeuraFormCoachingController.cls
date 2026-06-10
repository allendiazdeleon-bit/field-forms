/**
 * Real-time inspector coaching + prior-visit anomaly detection (Vignette 3).
 *
 * As an inspector answers a question in the mobile renderer, the LWC calls
 * getCoaching() with the current Linked Form, the question, and the answer
 * just entered. This class:
 *   1. Loads the last N completed inspections at the SAME location
 *      (Account) for the same template.
 *   2. Detects recurring findings across that history (the "anomaly" -
 *      e.g. condensation on the upper freezer hinge flagged 3 visits running).
 *   3. Asks the LLM for a short, specific coaching nudge that references the
 *      pattern and the inspector's current answer.
 *
 * Coaching is gated behind FieldForms_Configuration__c.Enable_AI_Features__c
 * (same opt-in as AI form generation). With AI off, getCoaching() returns an
 * empty result and the UI shows nothing.
 *
 * The LLM call uses the Salesforce Models API (Trust Layer). Phase C swaps
 * buildCoachingMessage() to invoke an Agentforce prompt template; the prior-
 * visit/anomaly logic here is unchanged by that.
 */
public with sharing class NeuraFormCoachingController {

    @TestVisible private static Integer PRIOR_VISIT_LIMIT = 6;
    // Minimum number of prior visits a finding must recur in to count as a
    // coachable pattern (vs. a one-off).
    @TestVisible private static Integer MIN_RECURRENCE = 2;

    // Test hook: when set, buildCoachingMessage returns this instead of
    // calling the live LLM.
    @TestVisible private static String mockLLMResponse = null;

    public class PriorFinding {
        @AuraEnabled public String questionLabel;
        @AuraEnabled public String notes;
        @AuraEnabled public String severity;
        @AuraEnabled public Date visitDate;
    }

    public class CoachingResult {
        @AuraEnabled public Boolean hasCoaching = false;
        @AuraEnabled public String message;
        @AuraEnabled public String suggestedAction;   // 'photo' | 'review' | null
        @AuraEnabled public Integer priorVisitCount = 0;
        @AuraEnabled public Integer recurrenceCount = 0;
        @AuraEnabled public List<PriorFinding> priorFindings = new List<PriorFinding>();
    }

    /**
     * Entry point for the renderer. Returns an empty (hasCoaching=false)
     * result when there is nothing to coach on, so the UI can call it freely
     * after every answer without special-casing.
     */
    @AuraEnabled
    public static CoachingResult getCoaching(Id linkedFormId, Id questionId, String currentAnswer) {
        // Coaching is best-effort; never break the inspection flow. Any
        // unexpected server-side failure degrades to "no coaching" rather
        // than surfacing an error toast mid-inspection.
        try {
            return computeCoaching(linkedFormId, questionId, currentAnswer);
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'getCoaching failed: ' + e.getMessage());
            return new CoachingResult();
        }
    }

    private static CoachingResult computeCoaching(Id linkedFormId, Id questionId, String currentAnswer) {
        CoachingResult result = new CoachingResult();
        if (linkedFormId == null || !isAIEnabled()) {
            return result;
        }

        List<Linked_Form__c> currentList = [
            SELECT Id, Account__c, Form_Template__c
            FROM Linked_Form__c
            WHERE Id = :linkedFormId
            LIMIT 1
        ];
        if (currentList.isEmpty() || currentList[0].Account__c == null) {
            return result;
        }
        Linked_Form__c current = currentList[0];

        List<Linked_Form__c> prior = [
            SELECT Id, Visit_Date__c
            FROM Linked_Form__c
            WHERE Account__c = :current.Account__c
              AND Form_Template__c = :current.Form_Template__c
              AND Status__c = 'Completed'
              AND Id != :linkedFormId
            ORDER BY Visit_Date__c DESC
            LIMIT :PRIOR_VISIT_LIMIT
        ];
        if (prior.isEmpty()) {
            return result;
        }
        Set<Id> priorIds = (new Map<Id, Linked_Form__c>(prior)).keySet();

        List<Form_Finding__c> findings = [
            SELECT Id, Notes__c, Severity__c, Linked_Form__c,
                   Linked_Form__r.Visit_Date__c,
                   Form_Answer__r.Form_Question__r.Question__c
            FROM Form_Finding__c
            WHERE Linked_Form__c IN :priorIds
            ORDER BY Linked_Form__r.Visit_Date__c DESC
        ];

        // Group recurring findings by a normalized note signature, counting
        // DISTINCT visits (two identical findings on one visit are one
        // occurrence — "recurred in N visits", same contract as escalation).
        Map<String, Set<Id>> visitsByNote = new Map<String, Set<Id>>();
        Map<String, PriorFinding> sample = new Map<String, PriorFinding>();
        for (Form_Finding__c f : findings) {
            String key = f.Notes__c == null ? '' : f.Notes__c.trim().toLowerCase();
            if (String.isBlank(key)) continue;
            Set<Id> noteVisits = visitsByNote.get(key);
            if (noteVisits == null) { noteVisits = new Set<Id>(); visitsByNote.put(key, noteVisits); }
            noteVisits.add(f.Linked_Form__c);
            if (!sample.containsKey(key)) {
                PriorFinding pf = new PriorFinding();
                pf.notes = f.Notes__c;
                pf.severity = f.Severity__c;
                pf.visitDate = f.Linked_Form__r.Visit_Date__c;
                pf.questionLabel = f.Form_Answer__r.Form_Question__r != null
                    ? f.Form_Answer__r.Form_Question__r.Question__c : null;
                sample.put(key, pf);
            }
        }

        // Pick the most-recurring finding.
        String topKey = null;
        Integer topCount = 0;
        for (String k : visitsByNote.keySet()) {
            Integer n = visitsByNote.get(k).size();
            if (n > topCount) {
                topCount = n;
                topKey = k;
            }
        }
        if (topKey == null || topCount < MIN_RECURRENCE) {
            return result;
        }

        PriorFinding top = sample.get(topKey);

        String qLabel = '';
        if (questionId != null) {
            List<Form_Question__c> qs = [
                SELECT Question__c FROM Form_Question__c WHERE Id = :questionId LIMIT 1
            ];
            if (!qs.isEmpty()) qLabel = qs[0].Question__c;
        }

        // Build the message BEFORE flagging hasCoaching: the LWC contract is
        // that hasCoaching=true always carries a displayable message, so an
        // LLM failure falls back to the deterministic nudge instead of
        // shipping a null message.
        String message = buildCoachingMessage(top, topCount, prior.size(), qLabel, currentAnswer);
        if (String.isBlank(message)) {
            message = fallbackCoachingMessage(top, topCount, prior.size());
        }

        result.hasCoaching = true;
        result.message = message;
        result.priorVisitCount = prior.size();
        result.recurrenceCount = topCount;
        result.priorFindings.add(top);
        // Severity drives the CTA: evidence (photo) for the serious patterns,
        // a history review for the rest.
        result.suggestedAction =
            (top.severity == 'Critical' || top.severity == 'High') ? 'photo' : 'review';
        return result;
    }

    /** Deterministic nudge from the already-computed pattern, used when the
     *  LLM is unavailable so coaching still works (and stays consistent with
     *  the escalation draft's fallback approach). */
    @TestVisible
    private static String fallbackCoachingMessage(PriorFinding finding, Integer recurrence, Integer priorVisits) {
        return 'Heads up: "' + finding.notes + '" was flagged on ' + recurrence +
            ' of the last ' + priorVisits + ' visits here. Worth a closer look before you leave?';
    }

    // ------------------------------------------------------------------------
    // Opt-in gate (shared semantics with NeuraFormAIController)
    // ------------------------------------------------------------------------

    @AuraEnabled(cacheable=true)
    public static Boolean isAIEnabled() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        return cfg != null && cfg.Enable_AI_Features__c == true;
    }

    // ------------------------------------------------------------------------
    // LLM coaching message
    // ------------------------------------------------------------------------

    @TestVisible
    private static String buildCoachingMessage(
        PriorFinding finding, Integer recurrence, Integer priorVisits,
        String currentQuestion, String currentAnswer
    ) {
        String systemPrompt =
            'You are a field-inspection coaching assistant embedded in a mobile ' +
            'inspection app. Coach the inspector in the moment, before they leave ' +
            'the site. Rules: at most 2 short sentences; be specific and reference ' +
            'the prior-visit pattern; end with a concrete suggested action phrased ' +
            'as a question. No preamble, no markdown.';

        String context =
            'Prior-visit history at this location:\n' +
            '- A finding "' + finding.notes + '" (severity ' + finding.severity + ') ' +
            'was flagged on ' + recurrence + ' of the last ' + priorVisits + ' visits';
        if (String.isNotBlank(finding.questionLabel)) {
            context += ', tied to the question "' + finding.questionLabel + '"';
        }
        context += '.\n\nRight now the inspector is on the question "' + currentQuestion +
            '" and just answered "' + currentAnswer + '".\n\n' +
            'Write the coaching nudge.';

        return invokeLLM(systemPrompt, context);
    }

    @TestVisible
    private static String invokeLLM(String systemPrompt, String userPrompt) {
        if (mockLLMResponse != null) {
            return mockLLMResponse;
        }
        // Null on any failure (the service catches everything) — the caller
        // substitutes the deterministic fallback message.
        return NeuraFormLLMService.chat(systemPrompt, userPrompt);
    }
}
