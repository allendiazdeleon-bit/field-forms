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

    @TestVisible private static final String DEFAULT_MODEL = 'sfdc_ai__DefaultGPT4Omni';
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

        try {
            String llmText = invokeLLM(buildSystemPrompt(), buildUserPrompt(prompt, context));
            Map<String, Object> spec = extractJsonObject(llmText);
            validateSpec(spec);

            // Transform the simple AI spec into the FormTemplateWrapper JSON
            // consumed by the existing import pipeline, then delegate to it
            // so all the FLS / sharing / upsert behavior is shared.
            String wrapperJson = transformSpecToImportJson(spec);
            List<Form_Template__c> created = neuraFormExportController.importTemplates(wrapperJson);

            if (created == null || created.isEmpty()) {
                throw new AuraHandledException('Import succeeded but no template was returned.');
            }
            // Rebuild snapshot fields immediately so the new template is
            // ready for the runtime (no need to wait for a child DML).
            Set<Id> ids = new Set<Id>{ created[0].Id };
            NeuraFormLogic.processTemplates(ids);

            GenerationResult result = new GenerationResult();
            result.formTemplateId = created[0].Id;
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
        // ConnectApi.EinsteinLLM is the supported Apex entry point for the
        // Einstein Models API. The class names have shifted across releases;
        // if a deploy fails to compile here, adjust to the input/output
        // representation classes available in the target org's API version.
        // (Targeting Salesforce v62+; surface is documented as stable from
        // Spring '25.)
        ConnectApi.EinsteinPromptTextGenerationsInput input =
            new ConnectApi.EinsteinPromptTextGenerationsInput();
        input.text = systemPrompt + '\n\n---\n\n' + userPrompt;

        ConnectApi.EinsteinLlmGenerationsInput body =
            new ConnectApi.EinsteinLlmGenerationsInput();
        body.promptTextGenerationsInput = input;

        ConnectApi.EinsteinLlmGenerationsResponseRepresentation response =
            ConnectApi.EinsteinLLM.generateMessages(body, DEFAULT_MODEL);

        if (response == null || response.generations == null || response.generations.isEmpty()) {
            throw new AuraHandledException('Einstein returned no generations.');
        }
        return response.generations[0].text;
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

        List<Map<String, Object>> pageRecs = new List<Map<String, Object>>();
        List<Map<String, Object>> sectionRecs = new List<Map<String, Object>>();
        List<Map<String, Object>> questionRecs = new List<Map<String, Object>>();

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
                    if (valueSet != null && !valueSet.isEmpty() && isChoiceType(type)) {
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
