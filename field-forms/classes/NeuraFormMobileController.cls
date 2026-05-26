/**
 * Apex fetch path for neuraFormMobile.
 *
 * The original LWC uses lightning/uiGraphQLApi for offline-safety. That works
 * great when the records are primed via Briefcase Builder, but if priming is
 * missing the on-device LDS cache contains zero rows and the wire returns
 * data with no edges — leaving the user staring at a blank selector.
 *
 * These @AuraEnabled(cacheable=true) endpoints execute server-side when the
 * device is online; the @wire framework caches the result in LDS so a
 * subsequent offline visit returns the cached payload. Trade-off: the very
 * first visit must be online. For users without a working Briefcase setup
 * that's the acceptable fallback.
 *
 * with sharing + Security.stripInaccessible enforces both record-level
 * sharing and field-level visibility for the running user.
 */
public with sharing class NeuraFormMobileController {

    // Limit to the lookup fields the mobile LWC actually filters on. Validated
    // against a hard-coded allowlist before being interpolated into SOQL — this
    // is a static set of known field API names, not arbitrary user input.
    private static final Set<String> ALLOWED_PARENT_FIELDS = new Set<String>{
        'Work_Order__c',
        'Work_Order_Line_Item__c',
        'Service_Appointment__c'
    };

    private static final Integer ANSWER_FETCH_LIMIT = 500;
    private static final Integer FINDING_FETCH_LIMIT = 200;

    @AuraEnabled(cacheable=true)
    public static List<LinkedFormListItem> getMobileFormList(Id parentId, String parentField) {
        if (parentId == null || String.isBlank(parentField)) {
            return new List<LinkedFormListItem>();
        }
        if (!ALLOWED_PARENT_FIELDS.contains(parentField)) {
            AuraHandledException ahe = new AuraHandledException(
                'Unsupported parent field: ' + parentField
            );
            ahe.setMessage('Unsupported parent field: ' + parentField);
            throw ahe;
        }

        // Build the dynamic query. parentField is whitelisted above so this is
        // not arbitrary user input. parentId is bound, not interpolated.
        String soql =
            'SELECT Id, Name, Form_Template__c, Current_Page__c, Status__c, ' +
            ' Form_Template__r.Id, Form_Template__r.Name, ' +
            ' Form_Template__r.Selector_Color__c, Form_Template__r.Indicator_Type__c ' +
            'FROM Linked_Form__c ' +
            'WHERE ' + parentField + ' = :parentId';

        List<Linked_Form__c> rows = Database.query(soql);
        rows = (List<Linked_Form__c>) Security.stripInaccessible(
            AccessType.READABLE, rows
        ).getRecords();

        List<LinkedFormListItem> out = new List<LinkedFormListItem>();
        for (Linked_Form__c lf : rows) {
            LinkedFormListItem item = new LinkedFormListItem();
            item.id = lf.Id;
            item.name = lf.Name;
            item.formTemplateId = lf.Form_Template__c;
            item.currentPage = lf.Current_Page__c == null ? 1 : Integer.valueOf(lf.Current_Page__c);
            item.status = lf.Status__c;
            if (lf.Form_Template__r != null) {
                item.formTemplateName = lf.Form_Template__r.Name;
                item.selectorColor = lf.Form_Template__r.Selector_Color__c;
                item.indicatorType = lf.Form_Template__r.Indicator_Type__c;
            }
            out.add(item);
        }
        return out;
    }

    @AuraEnabled(cacheable=true)
    public static FormDetails getMobileFormDetails(Id linkedFormId) {
        if (linkedFormId == null) return null;

        // Pull the Linked_Form first so we know which template to fetch.
        // Score__c / Max_Score__c are written by the scoring rollup queueable;
        // Score_Percent__c / Passed__c are formula fields; Findings_*_Count__c
        // are rollup summaries from Form_Finding__c.
        List<Linked_Form__c> lfs = [
            SELECT Id, Name, Form_Template__c, Current_Page__c, Status__c,
                   Score__c, Max_Score__c, Score_Percent__c, Passed__c,
                   Findings_Open_Count__c, Findings_Blocking_Count__c
            FROM Linked_Form__c
            WHERE Id = :linkedFormId
            LIMIT 1
        ];
        lfs = (List<Linked_Form__c>) Security.stripInaccessible(
            AccessType.READABLE, lfs
        ).getRecords();
        if (lfs.isEmpty()) return null;
        Linked_Form__c lf = lfs[0];

        List<Form_Template__c> tpls = [
            SELECT Id, Name, Indicator_Type__c, Selector_Color__c,
                   Pages_JSON__c, Sections_JSON__c,
                   Questions_JSON__c, Questions_JSON_1__c, Questions_JSON_2__c,
                   Page_Conditions__c, Section_Conditions__c, Question_Conditions__c,
                   Scoring_Enabled__c, Pass_Threshold_Percent__c, Max_Score__c
            FROM Form_Template__c
            WHERE Id = :lf.Form_Template__c
            LIMIT 1
        ];
        tpls = (List<Form_Template__c>) Security.stripInaccessible(
            AccessType.READABLE, tpls
        ).getRecords();
        if (tpls.isEmpty()) return null;

        // v2 snapshot chunks for the template. When present, the LWC
        // assembles them into the legacy-shape JSON strings; when absent,
        // the LWC falls back to the legacy *_JSON__c fields on the template.
        List<Form_Template_Snapshot__c> chunks = [
            SELECT Id, Form_Template__c, Payload_Type__c, Chunk_Index__c,
                   Payload__c, Schema_Version__c
            FROM Form_Template_Snapshot__c
            WHERE Form_Template__c = :lf.Form_Template__c
            ORDER BY Payload_Type__c, Chunk_Index__c
        ];
        chunks = (List<Form_Template_Snapshot__c>) Security.stripInaccessible(
            AccessType.READABLE, chunks
        ).getRecords();

        // Answers are capped to keep the payload bounded; the LWC already has
        // a warning surface for "older answers may be missing" if we hit it.
        List<Form_Answer__c> answers = [
            SELECT Id, Answer__c, Form_Question__c, Linked_Form__c,
                   Related_Comment__c, Type__c
            FROM Form_Answer__c
            WHERE Linked_Form__c = :linkedFormId
            LIMIT :ANSWER_FETCH_LIMIT
        ];
        answers = (List<Form_Answer__c>) Security.stripInaccessible(
            AccessType.READABLE, answers
        ).getRecords();

        // Pillar 5 — open findings for this Linked_Form. Capped so a runaway
        // ruleset doesn't blow the payload; the LWC surfaces a warning if it
        // ever sees the cap hit.
        List<Form_Finding__c> findings = [
            SELECT Id, Name, Status__c, Severity__c, Blocks_Submission__c,
                   Photo_Required__c, Photo_Attached__c,
                   External_Reference__c, Exception_Reason__c, Exception_Detail__c,
                   Notes__c, Form_Question_Catalog__c, Form_Answer__c
            FROM Form_Finding__c
            WHERE Linked_Form__c = :linkedFormId
            LIMIT :FINDING_FETCH_LIMIT
        ];
        findings = (List<Form_Finding__c>) Security.stripInaccessible(
            AccessType.READABLE, findings
        ).getRecords();

        FormDetails details = new FormDetails();
        details.linkedForm = lf;
        details.template = tpls[0];
        details.answers = answers;
        details.answersTruncated = (answers.size() == ANSWER_FETCH_LIMIT);
        details.snapshotChunks = chunks;
        details.findings = findings;
        details.findingsTruncated = (findings.size() == FINDING_FETCH_LIMIT);
        return details;
    }

    public class LinkedFormListItem {
        @AuraEnabled public String id;
        @AuraEnabled public String name;
        @AuraEnabled public String formTemplateId;
        @AuraEnabled public String formTemplateName;
        @AuraEnabled public String selectorColor;
        @AuraEnabled public String indicatorType;
        @AuraEnabled public Integer currentPage;
        @AuraEnabled public String status;
    }

    public class FormDetails {
        @AuraEnabled public Linked_Form__c linkedForm;
        @AuraEnabled public Form_Template__c template;
        @AuraEnabled public List<Form_Answer__c> answers;
        @AuraEnabled public Boolean answersTruncated;
        // v2 snapshot chunks for this template. Empty when the org is still
        // on the legacy single-record snapshot. See docs/snapshot-v2.md.
        @AuraEnabled public List<Form_Template_Snapshot__c> snapshotChunks;
        // Pillar 5 — Form_Finding__c records for this Linked_Form, capped at
        // FINDING_FETCH_LIMIT. findingsTruncated is true when we hit the cap.
        @AuraEnabled public List<Form_Finding__c> findings;
        @AuraEnabled public Boolean findingsTruncated;
    }

    // -----------------------------------------------------------------------
    // AI-mapped dictation
    // -----------------------------------------------------------------------
    //
    // The LWC sends a free-form transcript ("the customer is John Doe and the
    // reason is repair") plus a slim description of each question on the
    // current page. We return a list of {questionId, value} pairs the LWC
    // can apply to its in-memory answer map.
    //
    // Strategy:
    //   1. If Einstein AI is enabled and wired (NeuraFormAIController.invokeLLM
    //      returns a real response), prefer the LLM mapping — better at noisy
    //      transcripts and synonyms.
    //   2. Otherwise fall back to a deterministic heuristic that looks for
    //      each question's keywords in the transcript and grabs the trailing
    //      clause. Works well enough for "the X is Y" patterns even without
    //      any AI provisioning.

    public class QuestionDescriptor {
        @AuraEnabled public String questionId;
        @AuraEnabled public String label;
        @AuraEnabled public String type;
        @AuraEnabled public List<String> allowedValues;
    }

    public class MappedAnswer {
        @AuraEnabled public String questionId;
        @AuraEnabled public String value;
        @AuraEnabled public String reason;
    }

    @AuraEnabled
    public static MapResult mapTranscriptToQuestions(
        String transcript,
        List<QuestionDescriptor> questions
    ) {
        MapResult result = new MapResult();
        result.mappings = new List<MappedAnswer>();
        result.diagnostic = '';

        if (String.isBlank(transcript)) {
            result.diagnostic = 'no_transcript';
            return result;
        }
        if (questions == null || questions.isEmpty()) {
            result.diagnostic = 'no_questions';
            return result;
        }
        result.questionCount = questions.size();

        // Try Agentforce / Models API first; on any failure, fall back to
        // heuristic. We expose the exception type + line + raw message in
        // diagnostic — Apex's bare getMessage() often returns just
        // "Script-thrown exception", which tells us nothing about which
        // permission, model name, or wiring is missing.
        try {
            List<MappedAnswer> llm = mapViaModelsAPI(transcript, questions);
            if (llm != null && !llm.isEmpty()) {
                result.mappings = llm;
                result.source = 'agentforce';
                return result;
            }
        } catch (Exception e) {
            String detail = e.getTypeName() + ' @ line ' + e.getLineNumber()
                + ': ' + e.getMessage();
            // Stack trace is usually more informative than getMessage()
            // for the opaque "Script-thrown exception" case.
            String stack = e.getStackTraceString();
            if (String.isNotBlank(stack)) {
                detail += ' || stack: ' + stack.substring(0, Math.min(stack.length(), 300));
            }
            result.diagnostic = 'agentforce_unavailable: ' + detail;
        }

        result.mappings = mapViaHeuristic(transcript, questions);
        result.source = 'heuristic';
        return result;
    }

    // Custom exception so the outer catch can distinguish "Models API said
    // something we didn't like" from generic platform errors. Plain Exception
    // because AuraHandledException can only be thrown in an Aura/VF context.
    public class ModelsAPIMappingException extends Exception {}

    // -----------------------------------------------------------------------
    // AI summary at completion
    // -----------------------------------------------------------------------
    //
    // Before the tech submits, the renderer shows a review screen with all
    // answers laid out. This endpoint generates a 2-3 sentence summary the
    // tech can use as the customer-facing report. Falls back to a simple
    // bulleted "Findings" list if Agentforce isn't reachable.

    public class SummaryResult {
        @AuraEnabled public String summary;
        @AuraEnabled public String source;     // "agentforce" or "fallback"
        @AuraEnabled public String diagnostic;
    }

    public class AnswerSnapshot {
        @AuraEnabled public String questionLabel;
        @AuraEnabled public String answer;
    }

    @AuraEnabled
    public static SummaryResult summarizeFormCompletion(
        Id linkedFormId,
        List<AnswerSnapshot> snapshots
    ) {
        SummaryResult res = new SummaryResult();
        if (snapshots == null || snapshots.isEmpty()) {
            res.summary = '';
            res.source = 'fallback';
            res.diagnostic = 'no_answers';
            return res;
        }

        try {
            String llm = summarizeViaModelsAPI(snapshots);
            if (String.isNotBlank(llm)) {
                res.summary = llm.trim();
                res.source = 'agentforce';
                return res;
            }
        } catch (Exception e) {
            res.diagnostic = 'agentforce_unavailable: ' + e.getTypeName()
                + ': ' + e.getMessage();
        }

        // Fallback: deterministic bulleted findings list so the tech still
        // gets something useful when the LLM is unreachable.
        String fallback = 'Findings:\n';
        for (AnswerSnapshot a : snapshots) {
            if (String.isBlank(a.answer)) continue;
            fallback += '• ' + a.questionLabel + ': ' + a.answer + '\n';
        }
        res.summary = fallback.trim();
        res.source = 'fallback';
        return res;
    }

    // -----------------------------------------------------------------------
    // Same-as-last-visit prefill
    // -----------------------------------------------------------------------
    //
    // Finds the most recent Completed Linked_Form for the same Form_Template
    // tied to the same host record (WorkOrder, WOLI, or ServiceAppointment),
    // and returns its answers keyed by question Id. The LWC pushes those
    // into the current form via the same setExternalValue chain dictation
    // uses. Routine maintenance visits often repeat 70%+ of the same
    // answers — this saves 5+ minutes per visit.

    public class PrefillAnswer {
        @AuraEnabled public String questionId;
        @AuraEnabled public String value;
    }

    @AuraEnabled(cacheable=true)
    public static List<PrefillAnswer> getLastVisitAnswers(
        Id currentLinkedFormId,
        Id formTemplateId,
        Id parentId,
        String parentField
    ) {
        if (currentLinkedFormId == null || formTemplateId == null
            || parentId == null || String.isBlank(parentField)) {
            return new List<PrefillAnswer>();
        }
        if (!ALLOWED_PARENT_FIELDS.contains(parentField)) {
            return new List<PrefillAnswer>();
        }

        // Find the most-recent completed Linked_Form for the same template
        // tied to the same parent, excluding the current one. Bound params
        // via SOQL :var (parentField is allowlist-checked above).
        String soql =
            'SELECT Id FROM Linked_Form__c ' +
            'WHERE Form_Template__c = :formTemplateId ' +
            '  AND ' + parentField + ' = :parentId ' +
            '  AND Status__c = \'Completed\' ' +
            '  AND Id != :currentLinkedFormId ' +
            'ORDER BY LastModifiedDate DESC LIMIT 1';
        List<Linked_Form__c> prior = Database.query(soql);
        if (prior.isEmpty()) return new List<PrefillAnswer>();

        Id priorId = prior[0].Id;
        List<Form_Answer__c> answers = [
            SELECT Id, Form_Question__c, Answer__c
            FROM Form_Answer__c
            WHERE Linked_Form__c = :priorId
        ];
        answers = (List<Form_Answer__c>) Security.stripInaccessible(
            AccessType.READABLE, answers
        ).getRecords();

        List<PrefillAnswer> out = new List<PrefillAnswer>();
        for (Form_Answer__c a : answers) {
            if (String.isBlank(a.Answer__c)) continue;
            PrefillAnswer p = new PrefillAnswer();
            p.questionId = a.Form_Question__c;
            p.value = a.Answer__c;
            out.add(p);
        }
        return out;
    }

    private static String summarizeViaModelsAPI(List<AnswerSnapshot> snapshots) {
        // Compact serialization so token usage stays low.
        List<String> lines = new List<String>();
        for (AnswerSnapshot a : snapshots) {
            if (String.isBlank(a.answer)) continue;
            lines.add(a.questionLabel + ': ' + a.answer);
        }
        if (lines.isEmpty()) return '';

        String systemPrompt =
            'You are a field service technician writing a customer-facing ' +
            'service report. Given the technician\'s answers from a visit ' +
            'form, write 2-3 plain-English sentences summarizing what was ' +
            'done, what was found, and any follow-up needed. No markdown. ' +
            'No greetings. Keep it factual and concise.';
        String userPrompt = 'Answers:\n' + String.join(lines, '\n');

        return invokeModelsAPI(systemPrompt, userPrompt);
    }

    public class MapResult {
        @AuraEnabled public List<MappedAnswer> mappings;
        @AuraEnabled public String source;       // "agentforce" or "heuristic"
        @AuraEnabled public String diagnostic;   // empty on success, hint on empty
        @AuraEnabled public Integer questionCount;
    }

    /**
     * Agentforce / Models API call. The Salesforce unified Models API lives
     * under the `aiplatform.ModelsAPI` namespace and is available in orgs
     * with Einstein Generative AI / Agentforce provisioned.
     *
     * Org prerequisites:
     *   1. Enable Einstein Generative AI: Setup → Einstein Setup → toggle on.
     *   2. Enable a default model: Setup → Models → enable
     *      "sfdc_ai__DefaultGPT4Omni" (or your org's preferred model).
     *   3. Grant the running user "Use Generative AI" + the per-model perm.
     *
     * If the namespace doesn't exist in your org's release, this method
     * throws at compile or runtime — the caller catches and falls back to
     * the heuristic mapper. Replace this body with your org's specific
     * ModelsAPI shape if the class names have evolved.
     */
    private static List<MappedAnswer> mapViaModelsAPI(
        String transcript, List<QuestionDescriptor> questions
    ) {
        // Compact spec the LLM reasons over. Strip empty allowedValues so
        // free-text questions don't confuse the model.
        List<Map<String, Object>> qSpecs = new List<Map<String, Object>>();
        for (QuestionDescriptor q : questions) {
            Map<String, Object> spec = new Map<String, Object>{
                'id' => q.questionId,
                'label' => q.label,
                'type' => q.type
            };
            if (q.allowedValues != null && !q.allowedValues.isEmpty()) {
                spec.put('allowedValues', q.allowedValues);
            }
            qSpecs.add(spec);
        }

        String systemPrompt =
            'You map a spoken transcript onto form questions. ' +
            'Return ONLY a JSON object with a single key "mappings" whose value ' +
            'is an array of {"questionId":"...","value":"..."}. ' +
            'For questions with "allowedValues", "value" MUST equal one of those ' +
            'values exactly (case-sensitive). Omit any question you cannot ' +
            'confidently answer from the transcript. Do not wrap the JSON in ' +
            'markdown fences.';
        String userPrompt =
            'Transcript:\n' + transcript +
            '\n\nQuestions:\n' + JSON.serialize(qSpecs);

        String llmText = invokeModelsAPI(systemPrompt, userPrompt);
        if (String.isBlank(llmText)) {
            // Plain Exception (not AuraHandledException) because the inner
            // method gets called from anonymous Apex during smoke tests and
            // AuraHandledException can only be thrown from Aura/VF contexts.
            throw new ModelsAPIMappingException('Models API returned blank content.');
        }

        // Local renamed from "json" because Apex is case-insensitive and a
        // local named "json" silently shadows the System.JSON class.
        String jsonStr = stripCodeFences(llmText).trim();
        Map<String, Object> parsed;
        try {
            parsed = (Map<String, Object>) JSON.deserializeUntyped(jsonStr);
        } catch (Exception e) {
            throw new ModelsAPIMappingException('LLM returned non-JSON: ' + e.getMessage());
        }

        Object rawMappingsObj = parsed.get('mappings');
        if (rawMappingsObj == null) {
            throw new ModelsAPIMappingException('LLM response has no "mappings" key.');
        }
        List<Object> rawMappings = (List<Object>) rawMappingsObj;

        List<MappedAnswer> out = new List<MappedAnswer>();
        for (Object o : rawMappings) {
            Map<String, Object> m = (Map<String, Object>) o;
            MappedAnswer a = new MappedAnswer();
            a.questionId = (String) m.get('questionId');
            Object rawVal = m.get('value');
            a.value = rawVal == null ? null : String.valueOf(rawVal);
            a.reason = 'agentforce';
            if (String.isNotBlank(a.questionId) && a.value != null) {
                out.add(a);
            }
        }
        return out;
    }

    /**
     * Invokes the Models API. Wrapped so the class names are isolated in
     * one place — easier to swap if your org is on a different release.
     *
     * Current implementation uses aiplatform.ModelsAPI.createChatGenerations,
     * which is the recommended surface for Agentforce-grade chat completions
     * as of recent Salesforce releases.
     */
    @TestVisible
    private static String invokeModelsAPI(String systemPrompt, String userPrompt) {
        // Build the chat-generations request. The exact class names live in
        // the aiplatform namespace; reflecting via JSON keeps the Apex
        // compilable on older releases that don't expose those classes
        // (the call will fail at runtime there, which our caller catches).
        Map<String, Object> body = new Map<String, Object>{
            'messages' => new List<Object>{
                new Map<String, Object>{ 'role' => 'system', 'content' => systemPrompt },
                new Map<String, Object>{ 'role' => 'user',   'content' => userPrompt }
            }
        };

        // The Models API in this org exposes createChatGenerations as an
        // instance method, with body typed as ModelsAPI_ChatGenerationsRequest.
        // The JSON-serialize round-trip lets us hand a generic Map to the
        // typed body without depending on the (release-specific) builders for
        // every nested message/content class.
        aiplatform.ModelsAPI api = new aiplatform.ModelsAPI();
        aiplatform.ModelsAPI.createChatGenerations_Request req =
            new aiplatform.ModelsAPI.createChatGenerations_Request();
        req.modelName = 'sfdc_ai__DefaultGPT4Omni';
        req.body = (aiplatform.ModelsAPI_ChatGenerationsRequest)
            JSON.deserialize(JSON.serialize(body), aiplatform.ModelsAPI_ChatGenerationsRequest.class);

        aiplatform.ModelsAPI.createChatGenerations_Response res =
            api.createChatGenerations(req);

        if (res == null || res.Code200 == null) {
            throw new AuraHandledException('Models API returned no Code200.');
        }

        // Extract content via string operations rather than the typical
        // JSON deserialize → map walk path. Apex's typed Code200 class
        // (aiplatform.ModelsAPI.createChatGenerations_Response.Code200)
        // only exposes `id` and `generationDetails` as accessible fields,
        // and JSON.deserializeUntyped of the full response drops the
        // `generations` array on the round-trip — even though the
        // serialized string clearly contains it. Net effect: we never
        // managed to read content out of the typed model walking the
        // deserialized map. String extraction is brittle but reliable
        // given the consistent response shape from the Models API.
        String fullJson = JSON.serialize(res);
        String marker = '"content_set":true,"content":"';
        Integer start = fullJson.indexOf(marker);
        if (start < 0) {
            marker = '"content":"';
            start = fullJson.indexOf(marker);
        }
        if (start < 0) return null;
        start += marker.length();

        // Walk forward, respecting escaped quotes, until we hit the
        // terminating unescaped double-quote.
        String contentEscaped = '';
        Integer i = start;
        while (i < fullJson.length()) {
            String ch = fullJson.substring(i, i + 1);
            if (ch == '\\' && i + 1 < fullJson.length()) {
                contentEscaped += fullJson.substring(i, i + 2);
                i += 2;
                continue;
            }
            if (ch == '"') break;
            contentEscaped += ch;
            i++;
        }

        // Unescape JSON string escapes back to the raw content.
        return contentEscaped
            .replace('\\"', '"')
            .replace('\\n', '\n')
            .replace('\\r', '\r')
            .replace('\\t', '\t')
            .replace('\\\\', '\\');
    }

    private static String stripCodeFences(String s) {
        if (String.isBlank(s)) return s;
        String trimmed = s.trim();
        if (trimmed.startsWith('```')) {
            Integer firstNl = trimmed.indexOf('\n');
            if (firstNl > 0) trimmed = trimmed.substring(firstNl + 1);
            if (trimmed.endsWith('```')) trimmed = trimmed.substring(0, trimmed.length() - 3);
        }
        return trimmed.trim();
    }

    private static List<MappedAnswer> mapViaHeuristic(
        String transcript, List<QuestionDescriptor> questions
    ) {
        String lower = transcript.toLowerCase();
        List<MappedAnswer> out = new List<MappedAnswer>();

        for (QuestionDescriptor q : questions) {
            if (String.isBlank(q.label)) continue;
            String labelLower = q.label.toLowerCase();

            // Split label into keywords (drop common stop words and short
            // tokens) so "Customer name" matches "customer" anywhere.
            List<String> keywords = new List<String>();
            for (String tok : labelLower.split('\\s+')) {
                String clean = tok.replaceAll('[^a-z0-9]', '');
                if (clean.length() >= 3 && !STOP_WORDS.contains(clean)) {
                    keywords.add(clean);
                }
            }
            if (keywords.isEmpty()) continue;

            // For choice questions, pick the first allowedValue that appears
            // in the transcript near the question's keyword.
            if (isChoiceLikeType(q.type) && q.allowedValues != null && !q.allowedValues.isEmpty()) {
                for (String allowed : q.allowedValues) {
                    if (String.isBlank(allowed)) continue;
                    if (lower.contains(allowed.toLowerCase())) {
                        MappedAnswer m = new MappedAnswer();
                        m.questionId = q.questionId;
                        m.value = allowed;
                        m.reason = 'matched allowed value "' + allowed + '"';
                        out.add(m);
                        break;
                    }
                }
                continue;
            }

            // Free-text: find first keyword hit, take the phrase after the
            // next "is/are/was" or ":" until the next sentence terminator.
            for (String kw : keywords) {
                Integer idx = lower.indexOf(kw);
                if (idx < 0) continue;
                String rest = transcript.substring(idx + kw.length());
                String value = extractValuePhrase(rest);
                if (String.isNotBlank(value)) {
                    MappedAnswer m = new MappedAnswer();
                    m.questionId = q.questionId;
                    m.value = value.trim();
                    m.reason = 'matched keyword "' + kw + '"';
                    out.add(m);
                    break;
                }
            }
        }
        return out;
    }

    private static Boolean isChoiceLikeType(String type) {
        if (type == null) return false;
        String t = type.toLowerCase();
        return t == 'dropdown' || t == 'multiple choice' || t == 'radio buttons'
            || t == 'checkboxes' || t == 'rating';
    }

    private static String extractValuePhrase(String rest) {
        if (String.isBlank(rest)) return null;
        // Strip a leading connector ("is", "are", "was", ":", ",", "of")
        String trimmed = rest.replaceFirst('(?i)^[\\s,:]*(is|are|was|were|of)?[\\s,:]*', '');
        // Stop at the next sentence terminator or conjunction.
        Matcher m = Pattern.compile('^([^.!?\\n]+?)(?:[.!?\\n]|, and |, the | and the | and )').matcher(trimmed);
        if (m.find()) {
            return m.group(1);
        }
        // No terminator found: take up to first comma or end-of-string.
        Integer comma = trimmed.indexOf(',');
        return comma > 0 ? trimmed.substring(0, comma) : trimmed;
    }

    private static final Set<String> STOP_WORDS = new Set<String>{
        'the', 'and', 'for', 'with', 'this', 'that', 'your', 'please', 'enter'
    };
}
