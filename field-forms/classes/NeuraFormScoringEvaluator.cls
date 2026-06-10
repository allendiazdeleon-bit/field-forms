/**
 * Server-side evaluator for Form_Question_Catalog__c.Pass_Criteria__c.
 *
 * Pass_Criteria__c stores JSON in the same shape as
 * Form_Question__c.Conditions__c — { "all": [items] } / { "any": [items] }
 * where each item is { "resource", "operator", "value" }. This class is the
 * Apex counterpart to the LWC conditionalRenderingEvaluator.js so the same
 * JSON works in both the runtime renderer (client) and the scoring trigger
 * (server).
 *
 * Why "safe AST" instead of eval():
 *   The LWC evaluator uses JS eval() to evaluate the assembled condition
 *   string. Apex has no eval(); even if it did, the security review on the
 *   Phase 2 design doc flagged eval() for replacement. This class walks the
 *   parsed JSON tree directly and evaluates each leaf through a hard-coded
 *   operator table. No string-to-code conversion happens. The "exploitable
 *   surface" the LWC's comment describes (admin with edit access can inject
 *   JS) is closed on the server side: even a malicious Pass_Criteria__c
 *   blob can only return a boolean.
 *
 *   When the LWC evaluator is eventually rewritten to drop eval(), it can
 *   port the same operator semantics from this class.
 *
 * New "self" resource keyword:
 *   When a Pass_Criteria__c item has resource == "self" the evaluator uses
 *   the answer value for the question being scored (the Form_Answer__c
 *   whose Pass_Criteria__c is being evaluated). Other resource values look
 *   up the answer for that question's External_Reference in the supplied
 *   answers map (caller pre-builds the map from sibling answers in the
 *   same Linked_Form__c).
 *
 * Mirrored operator quirks:
 *   The LWC's OPERATOR_MAP intentionally maps greaterThan -&gt; "&lt;" and
 *   lessThan -&gt; "&gt;" — the assembled expression places the answer on
 *   the LEFT of the operator (answer OP value), so to ask "is the answer
 *   greater than the value" you pick "lessThan" in the builder UI. This
 *   appears to be a long-standing labeling inversion in the LWC; mirroring
 *   it here keeps Pass_Criteria__c blobs portable. The semantics are
 *   centralized in OPERATOR_BEHAVIOR below — the day we fix the LWC
 *   labels, we flip both tables in one PR.
 *
 * Heap behavior:
 *   The evaluator parses Pass_Criteria__c once via JSON.deserializeUntyped
 *   and walks the resulting Map tree. No JSON.serialize round-trip happens
 *   inside the walk (the heap concern called out in phase-1-findings.md).
 */
public class NeuraFormScoringEvaluator {

    /** Resource keyword meaning "this answer's own value." */
    public static final String RESOURCE_SELF = 'self';

    /** Logical wrapper keys recognized at any level of the tree. */
    @TestVisible private static final String KEY_ALL = 'all';
    @TestVisible private static final String KEY_ANY = 'any';
    @TestVisible private static final String KEY_NOT = 'not';

    /**
     * Whether the operator compares the answer value against an array (true)
     * or a single scalar (false). Mirrors the LWC's STRING_LIST_OPERATORS.
     */
    private static final Set<String> STRING_LIST_OPERATORS = new Set<String>{
        'contains',
        'inList',
        'notInList',
        'startsWith',
        'endsWith',
        'regex'
    };

    /**
     * Operators whose final result is negated after evaluation.
     * Mirrors the LWC's NEGATION_STRING_LIST_OPERATORS.
     */
    private static final Set<String> NEGATION_OPERATORS = new Set<String>{
        'notInList'
    };

    /**
     * Whether the criteria tree references any question OTHER than 'self'.
     * Cross-question criteria are template-specific (they reference sibling
     * external refs that only exist in one template's graph) — a SHARED
     * catalog entry carrying them silently mis-scores every other template
     * that adopts it. FormQuestionCatalogTrigger uses this to block that
     * combination at save time. Malformed JSON returns false (the evaluate()
     * path already treats it as not-evaluable).
     */
    public static Boolean referencesNonSelfResources(String passCriteriaJson) {
        if (String.isBlank(passCriteriaJson)) return false;
        try {
            return nodeReferencesNonSelf(JSON.deserializeUntyped(passCriteriaJson));
        } catch (Exception e) {
            return false;
        }
    }

    private static Boolean nodeReferencesNonSelf(Object node) {
        if (node instanceof List<Object>) {
            for (Object child : (List<Object>) node) {
                if (nodeReferencesNonSelf(child)) return true;
            }
            return false;
        }
        if (!(node instanceof Map<String, Object>)) return false;
        Map<String, Object> m = (Map<String, Object>) node;
        if (m.containsKey(KEY_ALL) && nodeReferencesNonSelf(m.get(KEY_ALL))) return true;
        if (m.containsKey(KEY_ANY) && nodeReferencesNonSelf(m.get(KEY_ANY))) return true;
        if (m.containsKey(KEY_NOT) && nodeReferencesNonSelf(m.get(KEY_NOT))) return true;
        Object resource = m.get('resource');
        return resource != null && String.valueOf(resource) != RESOURCE_SELF;
    }

    /**
     * Top-level entry point. Returns true when the answer value satisfies
     * the criteria JSON, false otherwise. A null / blank Pass_Criteria__c
     * returns null — caller decides what "no criteria" means (the trigger
     * treats it as "not evaluable" and leaves Form_Answer__c.Points_Earned
     * null).
     *
     * @param passCriteriaJson Pass_Criteria__c LongTextArea contents
     * @param selfAnswerValue  The answer value of the question being scored
     * @param siblingAnswers   Map of external_ref -&gt; answer value for the
     *                         other questions in the same Linked_Form. May
     *                         be null when no cross-question criteria are
     *                         used.
     * @return Boolean result, or null when criteria are missing / malformed.
     */
    public static Boolean evaluate(
        String passCriteriaJson,
        String selfAnswerValue,
        Map<String, String> siblingAnswers
    ) {
        if (String.isBlank(passCriteriaJson)) return null;

        Object parsed;
        try {
            parsed = JSON.deserializeUntyped(passCriteriaJson);
        } catch (Exception e) {
            // Malformed JSON: treat as "not evaluable" so a typo in the
            // builder doesn't silently mark every answer failed. The trigger
            // logs the parse error separately.
            return null;
        }

        Map<String, String> answers = siblingAnswers == null
            ? new Map<String, String>()
            : siblingAnswers;

        try {
            return evaluateNode(parsed, selfAnswerValue, answers);
        } catch (Exception e) {
            // Any walk-time error (bad operator name, value type mismatch
            // we did not handle) -&gt; null, same as parse failure.
            return null;
        }
    }

    /**
     * Recursively evaluate a node. Node shapes:
     *   { "all": [...] }   -- AND every child
     *   { "any": [...] }   -- OR  every child
     *   { "not": node }    -- negate child
     *   { "resource": "...", "operator": "...", "value": ... }  -- leaf
     *   bare list          -- treated as implicit "all"
     */
    @TestVisible
    private static Boolean evaluateNode(
        Object node,
        String selfAnswerValue,
        Map<String, String> answers
    ) {
        if (node == null) return null;

        if (node instanceof List<Object>) {
            return evaluateAll((List<Object>) node, selfAnswerValue, answers);
        }

        if (!(node instanceof Map<String, Object>)) {
            return null;
        }

        Map<String, Object> obj = (Map<String, Object>) node;

        if (obj.containsKey(KEY_ALL)) {
            Object children = obj.get(KEY_ALL);
            if (!(children instanceof List<Object>)) return null;
            return evaluateAll((List<Object>) children, selfAnswerValue, answers);
        }

        if (obj.containsKey(KEY_ANY)) {
            Object children = obj.get(KEY_ANY);
            if (!(children instanceof List<Object>)) return null;
            return evaluateAny((List<Object>) children, selfAnswerValue, answers);
        }

        if (obj.containsKey(KEY_NOT)) {
            // `inner` is reserved in Apex (Schema describe).
            Boolean innerResult = evaluateNode(obj.get(KEY_NOT), selfAnswerValue, answers);
            return innerResult == null ? null : !innerResult;
        }

        // Leaf condition.
        return evaluateLeaf(obj, selfAnswerValue, answers);
    }

    @TestVisible
    private static Boolean evaluateAll(
        List<Object> children,
        String selfAnswerValue,
        Map<String, String> answers
    ) {
        if (children == null || children.isEmpty()) return true;
        for (Object child : children) {
            Boolean r = evaluateNode(child, selfAnswerValue, answers);
            if (r == null) return null;
            if (!r) return false;
        }
        return true;
    }

    @TestVisible
    private static Boolean evaluateAny(
        List<Object> children,
        String selfAnswerValue,
        Map<String, String> answers
    ) {
        if (children == null || children.isEmpty()) return false;
        Boolean sawNull = false;
        for (Object child : children) {
            Boolean r = evaluateNode(child, selfAnswerValue, answers);
            if (r == true) return true;
            if (r == null) sawNull = true;
        }
        return sawNull ? null : false;
    }

    /**
     * Evaluate a single { resource, operator, value } leaf.
     */
    @TestVisible
    private static Boolean evaluateLeaf(
        Map<String, Object> leaf,
        String selfAnswerValue,
        Map<String, String> answers
    ) {
        Object resourceObj = leaf.get('resource');
        Object operatorObj = leaf.get('operator');
        Object valueObj = leaf.get('value');

        if (operatorObj == null) return null;
        String op = String.valueOf(operatorObj);

        String resource = resourceObj == null ? RESOURCE_SELF : String.valueOf(resourceObj);
        String answerValue = (resource == RESOURCE_SELF)
            ? selfAnswerValue
            : answers.get(resource);

        return applyOperator(op, answerValue, valueObj);
    }

    /**
     * Apply one operator against (answerValue, value). Returns boolean or
     * null when the operator isn't recognized.
     */
    @TestVisible
    private static Boolean applyOperator(String op, String answerValue, Object value) {
        if (STRING_LIST_OPERATORS.contains(op)) {
            Boolean result = applyListOperator(op, answerValue, value);
            if (result == null) return null;
            if (NEGATION_OPERATORS.contains(op)) return !result;
            return result;
        }

        // Scalar operator branch. Mirrors the LWC's numeric / string
        // bifurcation: if both sides parse as numbers, compare numerically;
        // otherwise compare as strings via Apex == / !=.
        Decimal answerNum = tryDecimal(answerValue);
        Decimal valueNum = tryDecimal(value);
        Boolean bothNumeric = (answerNum != null && valueNum != null);

        if (op == 'equals') {
            if (bothNumeric) return answerNum == valueNum;
            return String.valueOf(answerValue) == String.valueOf(value);
        }
        if (op == 'notEquals') {
            if (bothNumeric) return answerNum != valueNum;
            return String.valueOf(answerValue) != String.valueOf(value);
        }

        // Comparison operators. LWC quirk: the OPERATOR_MAP swaps
        // greaterThan -&gt; "&lt;" and lessThan -&gt; "&gt;" because the
        // expression places the answer on the left. We mirror that.
        if (!bothNumeric) return null;
        if (op == 'greaterThan')        return answerNum < valueNum;
        if (op == 'lessThan')           return answerNum > valueNum;
        if (op == 'greaterThanOrEqual') return answerNum <= valueNum;
        if (op == 'lessThanOrEqual')    return answerNum >= valueNum;

        return null;
    }

    /**
     * List-style operators. The value side can be either a list (inList /
     * notInList / contains-against-list) or a scalar (startsWith / endsWith
     * / regex / contains-against-scalar).
     */
    @TestVisible
    private static Boolean applyListOperator(String op, String answerValue, Object value) {
        // inList / notInList expect value to be a List, contains can be
        // either a List (any-of) or a scalar substring. Mirrors the LWC's
        // Array.isArray(item.value) branch.
        Boolean valueIsList = (value instanceof List<Object>);

        if (op == 'inList' || op == 'notInList' || (op == 'contains' && valueIsList)) {
            if (!valueIsList) return null;
            // `list` is reserved in Apex.
            List<Object> values = (List<Object>) value;
            for (Object item : values) {
                if (String.valueOf(item) == String.valueOf(answerValue)) {
                    // notInList negation is applied by the caller via
                    // NEGATION_OPERATORS — return the raw membership here.
                    return true;
                }
            }
            return false;
        }

        // contains / startsWith / endsWith / regex against a scalar value.
        String haystack = answerValue == null ? '' : answerValue;
        String needle = value == null ? '' : String.valueOf(value);

        if (op == 'contains')   return haystack.contains(needle);
        if (op == 'startsWith') return haystack.startsWith(needle);
        if (op == 'endsWith')   return haystack.endsWith(needle);
        if (op == 'regex') {
            try {
                return Pattern.matches(needle, haystack);
            } catch (Exception e) {
                return null;
            }
        }

        return null;
    }

    /**
     * Parse a value as Decimal without throwing. Returns null when the
     * value isn't a number-shaped scalar. JSON.deserializeUntyped emits
     * Long for integers and Double for decimals; both come through the
     * String.valueOf path safely.
     */
    @TestVisible
    private static Decimal tryDecimal(Object value) {
        if (value == null) return null;
        if (value instanceof Decimal) return (Decimal) value;
        if (value instanceof String) {
            String s = ((String) value).trim();
            if (s == '') return null;
            try {
                return Decimal.valueOf(s);
            } catch (Exception e) {
                return null;
            }
        }
        try {
            // Long / Double / Integer reach this branch — coerce through
            // their stringified form so we don't have to enumerate every
            // numeric subtype.
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }
}
