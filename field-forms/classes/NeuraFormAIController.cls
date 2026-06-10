/**
 * AI-assisted form authoring (v1: generate-from-prompt).
 *
 * Flow:
 *   1. LWC sends a natural-language prompt to generateTemplateFromPrompt().
 *   2. Apex calls the Einstein Models API via ConnectApi.EinsteinLLM.
 *   3. The model is instructed to emit a strict JSON describing a form
 *      (pages -> sections -> questions). Conditional logic is intentionally
 *      out of scope for v1 - models are unreliable at producing valid
 *      condition expressions referencing question Ids that don't yet exist.
 *   4. Apex transforms the simple JSON into the FormTemplateWrapper shape
 *      consumed by the existing neuraFormExportController.importTemplates
 *      pipeline so we reuse all of its FLS/sharing/upsert behavior.
 *   5. Returns the new Form_Template's Id (and Name) to the LWC, which
 *      navigates the admin to the freshly-created template.
 *
 * Opt-in gate: FieldForms_Configuration__c.Enable_AI_Features__c. Orgs
 * without Einstein Generative AI keep the flag off and never see the UI.
 */
public with sharing class NeuraFormAIController {

    @TestVisible private static Integer MAX_PAGES = 10;
    @TestVisible private static Integer MAX_QUESTIONS_PER_FORM = 200;

    // Hook so tests can inject a deterministic LLM response without making
    // a network call. Production code path leaves this null and the real
    // ConnectApi.EinsteinLLM is invoked.
    @TestVisible private static String mockLLMResponse = null;

    public class GenerationResult {
        @AuraEnabled public Id formTemplateId;
        @AuraEnabled public String formTemplateName;
        @AuraEnabled public Integer pageCount;
        @AuraEnabled public Integer questionCount;
    }

    /**
     * Public entry. Validates opt-in, calls the LLM, parses, imports,
     * returns the new template's coordinates.
     */
    @AuraEnabled
    public static GenerationResult generateTemplateFromPrompt(String prompt, String context) {
        if (String.isBlank(prompt)) {
            throw new AuraHandledException('Provide a description of the form you want to generate.');
        }
        ensureAIEnabled();
        return runGeneration(buildSystemPrompt(), buildUserPrompt(prompt, context), null);
    }

    /**
     * Draft a form from a customer-supplied document (Word/PDF) that they've
     * asked us to follow. The binary -> text extraction happens upstream
     * (client-side or a parse service); this takes the extracted text and the
     * brand `scope` so the generated template lands in that brand's partition
     * (Form_Template__c.Scope__c = scope), ready for review in the builder.
     */
    @AuraEnabled
    public static GenerationResult generateTemplateFromDocument(String documentText, String scope, String context) {
        if (String.isBlank(documentText)) {
            throw new AuraHandledException('Provide the extracted text of the document to convert.');
        }
        ensureAIEnabled();
        return runGeneration(
            buildDocumentSystemPrompt(),
            buildDocumentUserPrompt(documentText, context),
            scope
        );
    }

    public class OutputTemplateResult {
        @AuraEnabled public Id brandThemeId;
        @AuraEnabled public Integer htmlLength;
    }

    /**
     * Draft the branded REPORT OUTPUT template (HTML with merge tokens) from the
     * same customer document, mirroring its layout. Stored on the brand-level
     * Brand_Theme__c for the scope (created if absent), where the branded PDF
     * picks it up. This is the presentation half of "follow their template";
     * the result is meant to be reviewed/polished by a human.
     */
    @AuraEnabled
    public static OutputTemplateResult draftOutputTemplateFromDocument(
        String documentText, String scope, String context
    ) {
        if (String.isBlank(documentText)) {
            throw new AuraHandledException('Provide the extracted text of the document.');
        }
        if (String.isBlank(scope)) {
            throw new AuraHandledException('A brand scope is required to attach the template.');
        }
        ensureAIEnabled();
        try {
            String llm = invokeLLM(
                buildOutputTemplateSystemPrompt(),
                buildDocumentUserPrompt(documentText, context)
            );
            String html = stripCodeFence(llm);
            if (String.isBlank(html) || !html.contains('{{')) {
                throw new AuraHandledException(
                    'The model did not return a usable template (no merge tokens found).'
                );
            }
            // Upsert the brand-level theme (Form_Template__c == null) for this
            // scope. Filter to Active + order deterministically: stamping the
            // HTML onto an inactive or arbitrary row is a silent no-op at
            // render time because resolve() only reads active themes.
            List<Brand_Theme__c> existing = [
                SELECT Id FROM Brand_Theme__c
                WHERE Scope__c = :scope AND Form_Template__c = null
                  AND Active__c = true
                ORDER BY LastModifiedDate DESC
                LIMIT 1
            ];
            Brand_Theme__c bt = existing.isEmpty()
                ? new Brand_Theme__c(Scope__c = scope, Active__c = true)
                : existing[0];
            bt.Output_Template_Html__c = html;
            SObjectAccessDecision decision = Security.stripInaccessible(
                bt.Id == null ? AccessType.CREATABLE : AccessType.UPDATABLE,
                new List<Brand_Theme__c>{ bt }
            );
            upsert decision.getRecords();
            bt = (Brand_Theme__c) decision.getRecords()[0];

            OutputTemplateResult r = new OutputTemplateResult();
            r.brandThemeId = bt.Id;
            r.htmlLength = html.length();
            return r;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            AuraHandledException w = new AuraHandledException(
                'Output template drafting failed: ' + e.getMessage()
            );
            w.setMessage('Output template drafting failed: ' + e.getMessage());
            throw w;
        }
    }

    /**
     * Shared LLM -> parse -> validate -> import core. `scope` (nullable) is
     * stamped onto the generated template so document imports land in the
     * brand's partition; freeform prompt generation passes null.
     *
     * Delegates to importTemplatesAsNew(): importTemplates() now routes through
     * the adapter pipeline (expects native export format and silently drops
     * Question__c/Type__c/Form_Page__c from this wrapper shape). importTemplatesAsNew()
     * consumes the FormTemplateWrapper directly, populates every field + FK,
     * regenerates External_Reference__c, and rebuilds the JSON snapshot in-txn.
     */
    private static GenerationResult runGeneration(String systemPrompt, String userPrompt, String scope) {
        try {
            String llmText = invokeLLM(systemPrompt, userPrompt);
            Map<String, Object> spec = extractJsonObject(llmText);
            validateSpec(spec);

            String wrapperJson = transformSpecToImportJson(spec, scope);
            neuraFormExportController.ImportResult imported =
                neuraFormExportController.importTemplatesAsNew(wrapperJson);

            if (imported == null || imported.templates == null || imported.templates.isEmpty()) {
                throw new AuraHandledException('Import succeeded but no template was returned.');
            }

            GenerationResult result = new GenerationResult();
            result.formTemplateId = imported.templates[0].Id;
            result.formTemplateName = (String) spec.get('name');
            result.pageCount = pagesIn(spec).size();
            result.questionCount = countQuestions(spec);
            return result;
        } catch (AuraHandledException e) {
            throw e;
        } catch (Exception e) {
            // Surface the underlying cause in the message so the LWC toast is
            // actually actionable (default AuraHandledException hides it).
            AuraHandledException wrapped = new AuraHandledException(
                'AI form generation failed: ' + e.getMessage()
            );
            wrapped.setMessage('AI form generation failed: ' + e.getMessage());
            throw wrapped;
        }
    }

    // ------------------------------------------------------------------------
    // Opt-in / availability gating
    // ------------------------------------------------------------------------

    @AuraEnabled(cacheable=true)
    public static Boolean isAIEnabled() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        return cfg != null && cfg.Enable_AI_Features__c == true;
    }

    private static void ensureAIEnabled() {
        if (!isAIEnabled()) {
            throw new AuraHandledException(
                'AI features are not enabled for this org. Toggle ' +
                'FieldForms_Configuration__c.Enable_AI_Features__c to enable.'
            );
        }
    }

    // ------------------------------------------------------------------------
    // LLM call (isolated so the API surface can be swapped per Salesforce
    // release without touching the prompt-building or import logic)
    // ------------------------------------------------------------------------

    @TestVisible
    private static String invokeLLM(String systemPrompt, String userPrompt) {
        if (mockLLMResponse != null) {
            return mockLLMResponse;
        }
        // Real call: NeuraFormLLMService (the package's single point of
        // coupling to the Models API / Einstein Trust Layer). The service
        // never throws; for this interactive path a failure must surface to
        // the admin's toast, so re-raise its recorded cause (e.g. HTTP 403 =
        // missing permission, 429 = rate/usage limit).
        String text = NeuraFormLLMService.chat(systemPrompt, userPrompt);
        if (text == null) {
            String cause = String.isNotBlank(NeuraFormLLMService.lastError)
                ? NeuraFormLLMService.lastError
                : 'Einstein returned no generations.';
            AuraHandledException e = new AuraHandledException(cause);
            e.setMessage(cause);
            throw e;
        }
        return text;
    }

    // ------------------------------------------------------------------------
    // Prompt construction
    // ------------------------------------------------------------------------

    @TestVisible
    private static String buildSystemPrompt() {
        return
            'You are a Salesforce Field Forms generator. Output a single JSON object ' +
            'and NOTHING ELSE (no markdown, no commentary). Schema:\n' +
            '{\n' +
            '  "name": "<form name>",\n' +
            '  "indicatorType": "Ring" | "Horizontal" | "Vertical" | "Path" | "Bar" | "VertNav",\n' +
            '  "pages": [\n' +
            '    {\n' +
            '      "title": "<page title>",\n' +
            '      "sections": [\n' +
            '        {\n' +
            '          "title": "<section title>",\n' +
            '          "columns": 1 | 2 | 3,\n' +
            '          "showTitle": true | false,\n' +
            '          "questions": [\n' +
            '            {\n' +
            '              "label": "<question prompt shown to user>",\n' +
            '              "type": "Text" | "Text Area" | "Number" | "Date" | "Time" | "Email" | "Phone" |\n' +
            '                      "Checkbox" | "Toggle" | "Dropdown" | "Multiple Choice" | "Radio Buttons" |\n' +
            '                      "Rating" | "Slider" | "File Upload" | "Geolocation" | "Signature" |\n' +
            '                      "Scan Barcode" | "Display Text",\n' +
            '              "required": true | false,\n' +
            '              "valueSet": ["Option 1", "Option 2"]   // only for Dropdown / Multiple Choice / Radio Buttons\n' +
            '            }\n' +
            '          ]\n' +
            '        }\n' +
            '      ]\n' +
            '    }\n' +
            '  ]\n' +
            '}\n\n' +
            'Rules:\n' +
            '- Output STRICT JSON only.\n' +
            '- "valueSet" must be omitted unless the question type is a choice (Dropdown / Multiple Choice / Radio Buttons).\n' +
            '- Keep total questions under ' + MAX_QUESTIONS_PER_FORM + '. Keep total pages under ' + MAX_PAGES + '.\n' +
            '- Use clear, plain-language question labels. Avoid jargon unless the prompt requests it.\n' +
            '- Prefer multiple short pages over one long page when there are natural step boundaries.';
    }

    @TestVisible
    private static String buildUserPrompt(String prompt, String context) {
        String result = 'Generate a form for the following request:\n\n' + prompt;
        if (String.isNotBlank(context)) {
            result += '\n\nAdditional context: ' + context;
        }
        return result;
    }

    /**
     * Same strict-JSON schema as buildSystemPrompt(), but the task is to
     * FAITHFULLY REPRODUCE a customer-supplied document rather than invent a
     * form. The fidelity rules matter: the customer asked us to follow their
     * template, so preserve their wording, sections, ordering, and options.
     */
    @TestVisible
    private static String buildDocumentSystemPrompt() {
        return buildSystemPrompt() + '\n\n' +
            'DOCUMENT-CONVERSION MODE:\n' +
            '- The user message is the extracted text of a customer-provided inspection ' +
            'document (e.g. a Word/PDF audit form) that we must follow exactly.\n' +
            '- Reproduce the document faithfully: keep the section structure and the ' +
            'order of sections and questions as they appear in the document.\n' +
            '- Preserve the customer\'s question wording verbatim where practical.\n' +
            '- Map each question to the closest field type; when the document lists ' +
            'fixed answer options, use a choice type (Dropdown / Multiple Choice / ' +
            'Radio Buttons) and put the options in "valueSet".\n' +
            '- Use the document\'s own title as "name" when it has one.\n' +
            '- Do NOT invent questions that are not present in the document.';
    }

    @TestVisible
    private static String buildDocumentUserPrompt(String documentText, String context) {
        String result = 'Convert the following customer document into the form JSON. ' +
            'Follow its structure and wording faithfully:\n\n' + documentText;
        if (String.isNotBlank(context)) {
            result += '\n\nAdditional context: ' + context;
        }
        return result;
    }

    /**
     * System prompt for drafting the branded report OUTPUT template: a single
     * HTML fragment with merge tokens, laid out to mirror the customer's
     * document. Rendered by NeuraFormReportPDF via renderAs="pdf".
     */
    @TestVisible
    private static String buildOutputTemplateSystemPrompt() {
        return
            'You produce an HTML REPORT TEMPLATE that mirrors the layout of a ' +
            'customer-provided inspection document, for a PDF generator.\n\n' +
            'Output rules:\n' +
            '- Output ONE HTML fragment only: a single root <div>. No markdown, no ' +
            'commentary, no <html>/<head>/<body> tags.\n' +
            '- Use INLINE styles only (style="..."). No <style> blocks, no external CSS, ' +
            'no <script>, no remote fonts. Use web-safe fonts (Arial, Helvetica).\n' +
            '- Reproduce the document\'s structure: header/title area, the section ' +
            'headings in the same order, a findings/action area, and a sign-off area.\n\n' +
            'Insert these MERGE TOKENS (they are replaced with live data at render time):\n' +
            '  {{brand.logo}}          - brand logo <img>\n' +
            '  {{brand.headerText}}    - report title / brand header\n' +
            '  {{brand.primaryColor}}  - brand hex color (use in inline styles for accents)\n' +
            '  {{report.formName}}     {{report.status}}   {{report.completedDate}}   {{report.workOrder}}\n' +
            '  {{answers}}             - the full pages/sections/questions block\n' +
            '  {{findings}}            - the findings/exceptions table\n' +
            '  {{signature}}           - the on-site signature block\n' +
            '  {{answer:Exact Question Label}} - a single answer value, for precise placement\n\n' +
            '- Put {{answers}} where the body of results belongs, {{findings}} in the ' +
            'findings/action section, and {{signature}} in the sign-off area.\n' +
            '- Style headers/borders with {{brand.primaryColor}} so it looks on-brand.\n' +
            '- Do NOT hardcode answer values you see in the document text; use tokens.';
    }

    /** Strip a leading ```lang fence and trailing ``` if the model wrapped output. */
    @TestVisible
    private static String stripCodeFence(String s) {
        if (String.isBlank(s)) return s;
        String t = s.trim();
        if (t.startsWith('```')) {
            Integer nl = t.indexOf('\n');
            if (nl > 0) t = t.substring(nl + 1);
            if (t.endsWith('```')) t = t.substring(0, t.length() - 3);
        }
        return t.trim();
    }

    // ------------------------------------------------------------------------
    // Response parsing
    // ------------------------------------------------------------------------

    @TestVisible
    private static Map<String, Object> extractJsonObject(String llmText) {
        if (String.isBlank(llmText)) {
            throw new AuraHandledException('Einstein returned an empty response.');
        }
        // Some models wrap JSON in ```json fences despite instructions. Strip
        // anything before the first '{' and after the matching last '}'.
        Integer start = llmText.indexOf('{');
        Integer last = llmText.lastIndexOf('}');
        if (start < 0 || last < 0 || last <= start) {
            throw new AuraHandledException(
                'Einstein response did not contain JSON. Try a clearer prompt.'
            );
        }
        String trimmed = llmText.substring(start, last + 1);
        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(trimmed);
        } catch (Exception e) {
            throw new AuraHandledException(
                'Einstein returned malformed JSON: ' + e.getMessage()
            );
        }
        if (!(parsed instanceof Map<String, Object>)) {
            throw new AuraHandledException('Einstein response was not a JSON object.');
        }
        return (Map<String, Object>) parsed;
    }

    @TestVisible
    private static void validateSpec(Map<String, Object> spec) {
        if (String.isBlank((String) spec.get('name'))) {
            throw new AuraHandledException('AI did not produce a form name.');
        }
        List<Object> pages = pagesIn(spec);
        if (pages.isEmpty()) {
            throw new AuraHandledException('AI did not produce any pages.');
        }
        if (pages.size() > MAX_PAGES) {
            throw new AuraHandledException('Generated form has too many pages (' + pages.size() + ').');
        }
        Integer qCount = countQuestions(spec);
        if (qCount == 0) {
            throw new AuraHandledException('AI did not produce any questions.');
        }
        if (qCount > MAX_QUESTIONS_PER_FORM) {
            throw new AuraHandledException('Generated form has too many questions (' + qCount + ').');
        }
    }

    private static List<Object> pagesIn(Map<String, Object> spec) {
        Object raw = spec.get('pages');
        return raw instanceof List<Object> ? (List<Object>) raw : new List<Object>();
    }

    private static Integer countQuestions(Map<String, Object> spec) {
        Integer total = 0;
        for (Object pObj : pagesIn(spec)) {
            Map<String, Object> page = (Map<String, Object>) pObj;
            List<Object> sections = page.get('sections') instanceof List<Object>
                ? (List<Object>) page.get('sections') : new List<Object>();
            for (Object sObj : sections) {
                Map<String, Object> section = (Map<String, Object>) sObj;
                List<Object> questions = section.get('questions') instanceof List<Object>
                    ? (List<Object>) section.get('questions') : new List<Object>();
                total += questions.size();
            }
        }
        return total;
    }

    // ------------------------------------------------------------------------
    // Transform AI spec -> existing import wrapper JSON
    // ------------------------------------------------------------------------

    @TestVisible
    private static String transformSpecToImportJson(Map<String, Object> spec) {
        return transformSpecToImportJson(spec, null);
    }

    @TestVisible
    private static String transformSpecToImportJson(Map<String, Object> spec, String scope) {
        String ns = NeuraFormUtils.getNamespacePrefix();
        String extRef = ns + 'External_Reference__c';
        String fName = 'Name';
        String fIndicator = ns + 'Indicator_Type__c';
        String fOrder = ns + 'Order__c';
        String fTitle = ns + 'Title__c';
        String fTplLookup = ns + 'Form_Template__c';
        String fPageLookup = ns + 'Form_Page__c';
        String fSectionLookup = ns + 'Form_Section__c';
        String fShowTitle = ns + 'Show_Title__c';
        String fColumns = ns + 'Columns__c';
        String fQuestion = ns + 'Question__c';
        String fType = ns + 'Type__c';
        String fRequired = ns + 'Required__c';
        String fValueSet = ns + 'Value_Set__c';
        String fColumn = ns + 'Column__c';

        String templateRef = newRef('tpl');
        Map<String, Object> templateRec = new Map<String, Object>{
            'attributes' => new Map<String, String>{ 'type' => ns + 'Form_Template__c' },
            fName => (String) spec.get('name'),
            extRef => templateRef
        };
        String indicator = (String) spec.get('indicatorType');
        if (String.isNotBlank(indicator)) templateRec.put(fIndicator, indicator);
        // Stamp the brand partition key so a document import lands in the
        // brand's scope (matches Account.Form_Scope__c), ready in the brand hub.
        if (String.isNotBlank(scope)) templateRec.put(ns + 'Scope__c', scope);

        List<Map<String, Object>> pageRecs = new List<Map<String, Object>>();
        List<Map<String, Object>> sectionRecs = new List<Map<String, Object>>();
        List<Map<String, Object>> questionRecs = new List<Map<String, Object>>();

        // Catalog-match pass: where a generated question matches a curated
        // Question Catalog entry (scope-eligible), adopt its CANONICAL type +
        // value set and bind the catalog lookup, instead of trusting the LLM's
        // guess. One SOQL, bulk-safe. No match -> keep the LLM's type.
        String fCatLookup = ns + 'Form_Question_Catalog__c';
        Map<String, CatalogHit> catalogByLabel = buildCatalogMatchMap(spec, scope);

        Integer pageOrder = 1;
        for (Object pObj : pagesIn(spec)) {
            Map<String, Object> page = (Map<String, Object>) pObj;
            String pageRef = newRef('p');
            Map<String, Object> pageRec = new Map<String, Object>{
                'attributes' => new Map<String, String>{ 'type' => ns + 'Form_Page__c' },
                extRef => pageRef,
                fTplLookup => templateRef,
                fOrder => pageOrder,
                fTitle => stringOr(page.get('title'), 'Page ' + pageOrder),
                fName => stringOr(page.get('title'), 'Page ' + pageOrder)
            };
            pageRecs.add(pageRec);
            pageOrder++;

            Integer sectionOrder = 1;
            List<Object> sections = page.get('sections') instanceof List<Object>
                ? (List<Object>) page.get('sections') : new List<Object>();
            for (Object sObj : sections) {
                Map<String, Object> section = (Map<String, Object>) sObj;
                String sectionRef = newRef('s');
                Integer columns = section.get('columns') instanceof Integer
                    ? (Integer) section.get('columns')
                    : (section.get('columns') instanceof Decimal ? ((Decimal) section.get('columns')).intValue() : 1);
                if (columns < 1 || columns > 4) columns = 1;
                Map<String, Object> sectionRec = new Map<String, Object>{
                    'attributes' => new Map<String, String>{ 'type' => ns + 'Form_Section__c' },
                    extRef => sectionRef,
                    fTplLookup => templateRef,
                    fPageLookup => pageRef,
                    fOrder => sectionOrder,
                    fTitle => stringOr(section.get('title'), 'Section ' + sectionOrder),
                    fName => stringOr(section.get('title'), 'Section ' + sectionOrder),
                    fShowTitle => section.get('showTitle') == true,
                    fColumns => String.valueOf(columns)
                };
                sectionRecs.add(sectionRec);
                sectionOrder++;

                Integer qOrder = 1;
                List<Object> questions = section.get('questions') instanceof List<Object>
                    ? (List<Object>) section.get('questions') : new List<Object>();
                for (Object qObj : questions) {
                    Map<String, Object> question = (Map<String, Object>) qObj;
                    String qRef = newRef('q');
                    String label = stringOr(question.get('label'), 'Question ' + qOrder);
                    String type = normalizeType((String) question.get('type'));

                    // Adopt the catalog entry's canonical type when this
                    // question matches one (curated truth beats LLM inference).
                    CatalogHit hit = catalogByLabel.get(normalizeLabel(label));
                    if (hit != null && String.isNotBlank(hit.type)) {
                        type = normalizeType(hit.type);
                    }

                    Map<String, Object> questionRec = new Map<String, Object>{
                        'attributes' => new Map<String, String>{ 'type' => ns + 'Form_Question__c' },
                        extRef => qRef,
                        fTplLookup => templateRef,
                        fPageLookup => pageRef,
                        fSectionLookup => sectionRef,
                        fOrder => qOrder,
                        fColumn => '1',
                        fQuestion => label,
                        fName => label.left(80),
                        fType => type,
                        fRequired => question.get('required') == true
                    };
                    List<Object> valueSet = question.get('valueSet') instanceof List<Object>
                        ? (List<Object>) question.get('valueSet') : null;
                    if (hit != null) {
                        // Bind the catalog entry so type/value-set/scoring resolve
                        // from the curated row, and copy its value set inline too.
                        questionRec.put(fCatLookup, hit.catalogId);
                        if (String.isNotBlank(hit.valueSet) && isChoiceType(type)) {
                            questionRec.put(fValueSet, hit.valueSet);
                        }
                    } else if (valueSet != null && !valueSet.isEmpty() && isChoiceType(type)) {
                        questionRec.put(fValueSet, buildValueSetJson(valueSet));
                    }
                    questionRecs.add(questionRec);
                    qOrder++;
                }
            }
        }

        List<Map<String, Object>> wrappers = new List<Map<String, Object>>{
            new Map<String, Object>{
                'template' => templateRec,
                'pages' => pageRecs,
                'sections' => sectionRecs,
                'questions' => questionRecs
            }
        };
        return JSON.serialize(wrappers);
    }

    // ------------------------------------------------------------------------
    // Question Catalog matching (canonical types from the curated library)
    // ------------------------------------------------------------------------

    private class CatalogHit {
        Id catalogId;
        String type;
        String valueSet;
    }

    @TestVisible
    private static Boolean isCatalogEnabled() {
        FieldForms_Configuration__c cfg = FieldForms_Configuration__c.getInstance();
        return cfg != null && cfg.Question_Catalog_Enabled__c == true;
    }

    /**
     * Build a normalized-label -> catalog entry map for the questions in the
     * spec, scoped to the brand (universal Scope__c=null entries always
     * eligible). Exact normalized-text match only - high precision, since a
     * wrong type override is worse than falling back to the LLM's guess.
     * One SOQL, gated by the catalog feature flag.
     */
    @TestVisible
    private static Map<String, CatalogHit> buildCatalogMatchMap(Map<String, Object> spec, String scope) {
        Map<String, CatalogHit> out = new Map<String, CatalogHit>();
        if (!isCatalogEnabled()) return out;

        Set<String> wanted = new Set<String>();
        for (Object pObj : pagesIn(spec)) {
            Map<String, Object> page = (Map<String, Object>) pObj;
            List<Object> sections = page.get('sections') instanceof List<Object>
                ? (List<Object>) page.get('sections') : new List<Object>();
            for (Object sObj : sections) {
                Map<String, Object> section = (Map<String, Object>) sObj;
                List<Object> questions = section.get('questions') instanceof List<Object>
                    ? (List<Object>) section.get('questions') : new List<Object>();
                for (Object qObj : questions) {
                    Map<String, Object> q = (Map<String, Object>) qObj;
                    String key = normalizeLabel((String) q.get('label'));
                    if (String.isNotBlank(key)) wanted.add(key);
                }
            }
        }
        if (wanted.isEmpty()) return out;

        // Pull scope-eligible catalog entries (universal + this brand) and
        // match in Apex (catalog question text isn't a simple SOQL filter).
        for (Form_Question_Catalog__c cat : [
            SELECT Id, Question__c, Type__c, Value_Set__c, Scope__c
            FROM Form_Question_Catalog__c
            WHERE Scope__c = null OR Scope__c = :scope
            LIMIT 5000
        ]) {
            String key = normalizeLabel(cat.Question__c);
            if (String.isNotBlank(key) && wanted.contains(key) && !out.containsKey(key)) {
                CatalogHit h = new CatalogHit();
                h.catalogId = cat.Id;
                h.type = cat.Type__c;
                h.valueSet = cat.Value_Set__c;
                out.put(key, h);
            }
        }
        return out;
    }

    /** Normalize question text for matching: lowercase, collapse whitespace,
     *  drop trailing punctuation. */
    @TestVisible
    private static String normalizeLabel(String s) {
        if (String.isBlank(s)) return '';
        return s.toLowerCase().trim().replaceAll('\\s+', ' ').replaceAll('[?:.\\s]+$', '');
    }

    private static String newRef(String prefix) {
        // External_Reference__c is a string upsert key. importTemplates does
        // not require Salesforce-Id shape; any unique-per-import string works.
        return 'AIGEN_' + prefix + '_' + Crypto.getRandomLong() + '_' + System.currentTimeMillis();
    }

    private static String stringOr(Object value, String fallback) {
        if (value == null) return fallback;
        String s = String.valueOf(value);
        return String.isBlank(s) ? fallback : s;
    }

    @TestVisible
    private static String normalizeType(String type) {
        if (String.isBlank(type)) return 'Text';
        // Whitelist against the global value set used on Form_Question__c.Type__c.
        Set<String> valid = new Set<String>{
            'Text', 'Text Area', 'Multiple Choice', 'Checkboxes', 'Dropdown',
            'Radio Buttons', 'Date', 'Time', 'Number', 'Email', 'Phone',
            'Rating', 'Slider', 'File Upload', 'Geolocation', 'Toggle',
            'Signature', 'Checkbox', 'Scan Barcode', 'Display Text'
        };
        // Title-case the AI's input loosely to forgive common variants.
        String trimmed = type.trim();
        for (String v : valid) {
            if (v.equalsIgnoreCase(trimmed)) return v;
        }
        return 'Text'; // Safe fallback for unknown types.
    }

    @TestVisible
    private static Boolean isChoiceType(String type) {
        return type == 'Dropdown' || type == 'Multiple Choice' || type == 'Radio Buttons';
    }

    @TestVisible
    private static String buildValueSetJson(List<Object> options) {
        // Matches the shape neuraFormBuilderAttributesValueSet expects: an
        // array of { id, label, value, icon } records.
        List<Map<String, Object>> entries = new List<Map<String, Object>>();
        for (Object opt : options) {
            String label = String.valueOf(opt);
            if (String.isBlank(label)) continue;
            entries.add(new Map<String, Object>{
                'id' => 'AIGEN_opt_' + Crypto.getRandomLong(),
                'label' => label,
                'value' => label,
                'icon' => ''
            });
        }
        return JSON.serialize(entries);
    }
}
