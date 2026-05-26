/**
 * Adapter for the Steritech audit shape — a JSON array of line items,
 * each carrying a `line_item_code`, `line_item_title`, `policy`, and a
 * recursive `questions` tree where every option can carry a
 * `child_question` (Steritech's conditional-branching encoding). Up to
 * seven levels deep in the real customer payload.
 *
 * Maps that source into the canonical NeuraFormIR:
 *
 *   - Pages are synthesized by bucketing line items by `line_item_code`
 *     prefix (the source has no page concept of its own). Buckets are
 *     stable / documented in PAGE_BUCKETS below; admins re-bucket via
 *     the builder after the import.
 *   - One IR Section per line item; `policy` lands on
 *     Form_Section__c.Policy_Text__c (added in Wave 36).
 *   - One IR CatalogEntry per UNIQUE `question_id` (the asset). The same
 *     qid that appears in 60 line items produces one catalog entry.
 *   - One IR Binding per question INSTANCE (the placement). The same qid
 *     across 60 sections produces 60 bindings all pointing at the one
 *     catalog entry.
 *   - The recursive `child_question` shape is FLATTENED to sibling
 *     bindings whose `conditions` carry the ancestor option-chain. A
 *     question four levels deep gets three conditions ANDed together;
 *     the importer's existing conditional rendering applies.
 *
 * Type inference: the source doesn't tell us "Text" vs "Date" vs
 * "Number". We infer from question text heuristics (date prompts,
 * temperature prompts, free-text prompts, etc.). Every inference emits
 * a warning so an admin can audit at import time before publishing.
 *
 * Heap discipline: the real customer payload is 1.5 MB serialized.
 * Process line items one at a time from the top-level untyped parse;
 * keep no intermediate JSON strings. The importer runs in a queueable
 * (12MB async heap).
 *
 * See docs/phase-2-pillar-3-adapter-framework.md.
 */
public with sharing class NeuraFormSteritechAdapter implements NeuraFormSourceAdapter {

    /** Stable adapter label — appears in the import UI's picker. */
    public static final String ADAPTER_LABEL = 'Steritech Audit Format';

    /** External-ref prefix conventions. Stable so re-imports round-trip. */
    private static final String PAGE_REF_PREFIX = 'steritech_page_';
    private static final String SECTION_REF_PREFIX = 'steritech_section_';
    private static final String CATALOG_REF_PREFIX = 'steritech_catalog_';
    private static final String BINDING_REF_PREFIX = 'steritech_binding_';

    /**
     * Synthetic template external_ref when the import options don't
     * carry one. Admin can override via options['template_external_ref'].
     */
    private static final String DEFAULT_TEMPLATE_REF = 'steritech_audit_template';

    /**
     * Page bucket plan: line-item-code prefix → page title. Numeric codes
     * (700-series) live under "Pest Prevention"; letter prefixes map to
     * the standard Steritech audit groupings. Anything we don't
     * recognize falls into "Operations & Compliance" so admin still
     * sees the rows after import.
     */
    @TestVisible
    private static final Map<String, String> PAGE_BUCKETS = new Map<String, String>{
        '7'  => 'Pest Prevention',
        'A'  => 'Food Safety',
        'B'  => 'Person-in-Charge / Certifications',
        'C'  => 'Cleaning & Sanitation',
        'D'  => 'Documentation / Decor',
        'E'  => 'Egress / Playground / Electrical / Exterior',
        'F'  => 'First Aid / Facility / Food Quality / Fire Suppression',
        'G'  => 'Operations & Compliance',
        'L'  => 'Operations & Compliance',
        'M'  => 'Operations & Compliance',
        'P'  => 'Operations & Compliance',
        'R'  => 'Operations & Compliance',
        'S'  => 'Operations & Compliance',
        'W'  => 'Operations & Compliance'
    };

    /** Fallback page title for unrecognized prefixes. */
    private static final String PAGE_FALLBACK_TITLE = 'Operations & Compliance';
    private static final String PAGE_FALLBACK_KEY = 'misc';

    /** Warnings collected during the most recent parse() invocation. */
    @TestVisible
    private List<String> warnings = new List<String>();

    /** Read-only access to the warning list (post-parse). */
    public List<String> getWarnings() {
        return warnings;
    }

    public String label() {
        return ADAPTER_LABEL;
    }

    /**
     * Confidence: the Steritech shape is a JSON array whose first
     * element carries `line_item_code`, `line_item_title`, `policy`, and
     * `questions`. Cheap string sniff (first 4KB) before any parse —
     * keeps auto-pick fast when multiple adapters are registered.
     */
    public Decimal canHandle(String source) {
        if (String.isBlank(source)) return 0;
        String head = source.length() > 4000 ? source.substring(0, 4000) : source;
        String trimmed = head.trim();
        if (!trimmed.startsWith('[')) return 0;
        Boolean hasCode = trimmed.contains('"line_item_code"');
        Boolean hasTitle = trimmed.contains('"line_item_title"');
        Boolean hasPolicy = trimmed.contains('"policy"');
        Boolean hasQuestions = trimmed.contains('"questions"');
        if (hasCode && hasTitle && hasQuestions) {
            // policy is documented but a handful of line items may omit it;
            // require the other three and bump if policy is present.
            return hasPolicy ? 0.95 : 0.85;
        }
        if (hasCode || hasTitle) return 0.2;
        return 0;
    }

    /**
     * Parse the Steritech payload and emit IR. Options:
     *   - template_external_ref: override DEFAULT_TEMPLATE_REF
     *   - template_name: human-readable template name (defaults to
     *     "Steritech Audit"). Admin re-labels in the builder later.
     */
    public NeuraFormIR parse(String source, Map<String, String> options) {
        warnings = new List<String>();

        if (String.isBlank(source)) {
            throw new NeuraFormImporter.AdapterException('Empty source payload.');
        }

        List<Object> lineItems;
        try {
            Object parsed = JSON.deserializeUntyped(source);
            if (!(parsed instanceof List<Object>)) {
                throw new NeuraFormImporter.AdapterException(
                    'Steritech payload must be a top-level JSON array of line items.'
                );
            }
            lineItems = (List<Object>) parsed;
        } catch (NeuraFormImporter.AdapterException e) {
            throw e;
        } catch (Exception e) {
            throw new NeuraFormImporter.AdapterException(
                'Could not parse Steritech JSON: ' + e.getMessage()
            );
        }
        if (lineItems == null || lineItems.isEmpty()) {
            throw new NeuraFormImporter.AdapterException(
                'No line items found in Steritech payload.'
            );
        }

        NeuraFormIR ir = new NeuraFormIR();

        // ---- template ----
        NeuraFormIR.Template tpl = new NeuraFormIR.Template();
        tpl.external_ref = optionOrDefault(options, 'template_external_ref', DEFAULT_TEMPLATE_REF);
        tpl.name = optionOrDefault(options, 'template_name', 'Steritech Audit');
        ir.template = tpl;

        // Dedupe state across the whole template
        Set<String> emittedCatalogRefs = new Set<String>();
        Set<String> emittedPageRefs = new Set<String>();
        Map<String, Integer> pageOrderByKey = new Map<String, Integer>();

        Integer sectionOrder = 0;

        for (Object liObj : lineItems) {
            if (!(liObj instanceof Map<String, Object>)) continue;
            Map<String, Object> li = (Map<String, Object>) liObj;

            String code = asString(li.get('line_item_code'));
            String title = asString(li.get('line_item_title'));
            String policy = asString(li.get('policy'));

            if (String.isBlank(code)) {
                warnings.add('Line item skipped: missing line_item_code.');
                continue;
            }

            // Page bucket
            String prefixKey = bucketKey(code);
            String pageRef = PAGE_REF_PREFIX + prefixKey;
            if (!emittedPageRefs.contains(pageRef)) {
                emittedPageRefs.add(pageRef);
                NeuraFormIR.IRPage pg = new NeuraFormIR.IRPage();
                pg.external_ref = pageRef;
                pg.title = PAGE_BUCKETS.containsKey(prefixKey)
                    ? PAGE_BUCKETS.get(prefixKey) : PAGE_FALLBACK_TITLE;
                pg.order = pageOrderByKey.size() + 1;
                pageOrderByKey.put(prefixKey, (Integer) pg.order);
                ir.pages.add(pg);
            }

            // Section
            sectionOrder += 1;
            String sectionRef = SECTION_REF_PREFIX + code;
            NeuraFormIR.Section sec = new NeuraFormIR.Section();
            sec.external_ref = sectionRef;
            sec.page_ref = pageRef;
            sec.title = String.isBlank(title) ? code : title;
            sec.order = sectionOrder;
            sec.policy_text = policy;
            ir.sections.add(sec);

            // Questions (recursive walk)
            List<Object> qs = asList(li.get('questions'));
            if (qs.isEmpty()) {
                warnings.add('Line item ' + code + ' has no questions.');
                continue;
            }
            Map<String, Integer> qidCountInSection = new Map<String, Integer>();
            Integer bindingOrder = 0;
            for (Object qObj : qs) {
                if (!(qObj instanceof Map<String, Object>)) continue;
                bindingOrder = walkQuestion(
                    (Map<String, Object>) qObj,
                    code,
                    sectionRef,
                    ir,
                    emittedCatalogRefs,
                    qidCountInSection,
                    new List<NeuraFormIR.Condition>(),
                    bindingOrder
                );
            }
        }

        return ir;
    }

    /**
     * Walk a Steritech question + its option tree, emitting one catalog
     * entry (deduped) and one binding (per instance) per node.
     *
     * `parentConditions` is the AND-chain of ancestor option choices
     * accumulated through the recursion — empty for top-level questions,
     * one entry per ancestor for nested children.
     *
     * Returns the running binding order so the caller can continue
     * numbering across siblings.
     */
    private Integer walkQuestion(
        Map<String, Object> q,
        String lineItemCode,
        String sectionRef,
        NeuraFormIR ir,
        Set<String> emittedCatalogRefs,
        Map<String, Integer> qidCountInSection,
        List<NeuraFormIR.Condition> parentConditions,
        Integer bindingOrder
    ) {
        String qid = asString(q.get('question_id'));
        String qname = asString(q.get('question_name'));
        List<Object> options = asList(q.get('options'));

        // null-named placeholder branch: don't emit a catalog/binding,
        // but still walk children so deeper questions get path-through
        // conditions correctly.
        Boolean placeholder = String.isBlank(qname);

        if (!placeholder && String.isBlank(qid)) {
            warnings.add('Question skipped: missing question_id (text: '
                + truncate(qname, 60) + ').');
            return bindingOrder;
        }

        if (!placeholder) {
            // Catalog entry (dedupe by qid)
            String catalogRef = CATALOG_REF_PREFIX + qid;
            if (!emittedCatalogRefs.contains(catalogRef)) {
                emittedCatalogRefs.add(catalogRef);
                NeuraFormIR.CatalogEntry cat = new NeuraFormIR.CatalogEntry();
                cat.external_ref = catalogRef;
                cat.question_text = qname;
                cat.type = inferType(qname, options);
                cat.value_set = buildValueSet(options);
                ir.catalog_entries.add(cat);
                warnings.add('Type inferred: \'' + truncate(qname, 60)
                    + '\' → ' + cat.type);
            }

            // Binding (per instance)
            bindingOrder += 1;
            Integer n = qidCountInSection.containsKey(qid)
                ? qidCountInSection.get(qid) + 1 : 1;
            qidCountInSection.put(qid, n);
            NeuraFormIR.Binding bind = new NeuraFormIR.Binding();
            bind.external_ref = BINDING_REF_PREFIX + lineItemCode + '_' + qid + '_' + n;
            bind.section_ref = sectionRef;
            bind.catalog_ref = catalogRef;
            bind.order = bindingOrder;
            if (!parentConditions.isEmpty()) {
                // Copy the accumulated conditions onto the binding.
                bind.conditions = new List<NeuraFormIR.Condition>(parentConditions);
            }
            ir.bindings.add(bind);
        }

        // Recurse into option children, accumulating the path-through
        // condition for each one. Conditions reference the catalog ref
        // of the closest non-placeholder ancestor — the importer's
        // existing condition resolver expects catalog refs.
        if (options.isEmpty()) return bindingOrder;

        String conditionResource = placeholder
            ? mostRecentResource(parentConditions)
            : (CATALOG_REF_PREFIX + qid);

        for (Object optObj : options) {
            if (!(optObj instanceof Map<String, Object>)) continue;
            Map<String, Object> opt = (Map<String, Object>) optObj;
            Object child = opt.get('child_question');
            if (!(child instanceof Map<String, Object>)) continue;
            String optName = asString(opt.get('option_name'));

            List<NeuraFormIR.Condition> nextConditions =
                new List<NeuraFormIR.Condition>(parentConditions);
            if (String.isNotBlank(conditionResource)) {
                NeuraFormIR.Condition c = new NeuraFormIR.Condition();
                c.resource = conditionResource;
                c.operator = 'equals';
                c.value = optName;
                nextConditions.add(c);
            }
            bindingOrder = walkQuestion(
                (Map<String, Object>) child,
                lineItemCode,
                sectionRef,
                ir,
                emittedCatalogRefs,
                qidCountInSection,
                nextConditions,
                bindingOrder
            );
        }
        return bindingOrder;
    }

    /**
     * Type-inference heuristics. Ordered: stop at first match.
     * Branch questions (those with options) default to Multiple Choice.
     * Leaf questions default to Text. Date / Number / Text Area are
     * pulled out by lexical signals in the question text.
     */
    @TestVisible
    private static String inferType(String questionText, List<Object> options) {
        Boolean hasOptions = options != null && !options.isEmpty();
        if (String.isBlank(questionText)) {
            return hasOptions ? 'Multiple Choice' : 'Text';
        }
        String t = questionText.toLowerCase();
        // Date
        if (t.startsWith('enter the date') || t.startsWith('enter date')
            || t.contains('date of ')) {
            return 'Date';
        }
        // Long-form text
        if (t.startsWith('briefly describe') || t.startsWith('describe ')
            || t.contains('describe in detail')
            || t.contains('additional details')) {
            return 'Text Area';
        }
        // Number (temperature etc.)
        if (t.startsWith('what was the final cooking temperature')
            || (t.contains('temperature ') && !hasOptions)) {
            return 'Number';
        }
        // Has options → multiple choice
        if (hasOptions) {
            return 'Multiple Choice';
        }
        // "Enter ..." (non-date) → text
        if (t.startsWith('enter the name') || t.startsWith('enter ')) {
            return 'Text';
        }
        return 'Text';
    }

    /**
     * Translate the source's option list into the Field Forms
     * Value_Set__c JSON shape (`[{id, label, value}]`). Returns null
     * when no options are present so the importer leaves the field
     * unset for free-text questions.
     */
    private static String buildValueSet(List<Object> options) {
        if (options == null || options.isEmpty()) return null;
        List<Map<String, String>> rows = new List<Map<String, String>>();
        Set<String> seen = new Set<String>();
        for (Object optObj : options) {
            if (!(optObj instanceof Map<String, Object>)) continue;
            String name = asString(((Map<String, Object>) optObj).get('option_name'));
            if (String.isBlank(name)) continue;
            if (seen.contains(name)) continue;
            seen.add(name);
            rows.add(new Map<String, String>{
                'id' => name,
                'label' => name,
                'value' => name
            });
        }
        return rows.isEmpty() ? null : JSON.serialize(rows);
    }

    /**
     * Bucket key for a line item code. Numeric codes (700-series) all
     * share the '7' bucket; letter-prefixed codes use the leading
     * letter. Unrecognized prefixes fall through to 'misc' so the data
     * is never silently dropped.
     */
    @TestVisible
    private static String bucketKey(String code) {
        if (String.isBlank(code)) return PAGE_FALLBACK_KEY;
        String first = code.substring(0, 1);
        if (first.isNumeric()) return '7';
        String upper = first.toUpperCase();
        if (PAGE_BUCKETS.containsKey(upper)) return upper;
        return PAGE_FALLBACK_KEY;
    }

    /** Most-recent condition resource — used when a placeholder branch
     *  sits between a real ancestor and its real grandchild. */
    private static String mostRecentResource(List<NeuraFormIR.Condition> chain) {
        if (chain == null || chain.isEmpty()) return null;
        return chain[chain.size() - 1].resource;
    }

    // -----------------------------------------------------------------
    // Helpers
    // -----------------------------------------------------------------

    private static String optionOrDefault(
        Map<String, String> options, String key, String fallback
    ) {
        if (options == null) return fallback;
        String v = options.get(key);
        return String.isBlank(v) ? fallback : v;
    }

    private static String asString(Object o) {
        return (o == null) ? null : String.valueOf(o);
    }

    private static List<Object> asList(Object o) {
        return (o instanceof List<Object>) ? (List<Object>) o : new List<Object>();
    }

    private static String truncate(String s, Integer n) {
        if (s == null) return '';
        return (s.length() <= n) ? s : s.substring(0, n) + '...';
    }
}
