/**
 * Conditional-rendering condition evaluator — pure helpers used by the
 * renderer to decide which pages / sections / questions should render
 * based on the current answers.
 *
 * Rewritten (from the original eval()-based version) as a direct
 * comparator for three reasons, each a real bug in the field:
 *   1. Operator orientation: the old OPERATOR_MAP mapped greaterThan to
 *      '<' and evaluated `answer < value` — every numeric comparison an
 *      admin authored ran INVERTED at runtime.
 *   2. isTrue / isFalse were authorable in the criteria builder but
 *      missing from the map, so eval() saw `'x' undefined 'y'` and threw.
 *   3. The answer value is END-USER input and was interpolated into a
 *      quoted JS string — a tech typing an apostrophe ("it's leaking")
 *      broke the expression and killed conditional rendering for the
 *      page; it was also a script-injection surface.
 *
 * Semantics:
 *   - equals / notEquals / greaterThan / lessThan / greaterThanOrEqual /
 *     lessThanOrEqual compare numerically when BOTH sides parse as
 *     numbers, lexicographically otherwise (preserves the old
 *     mixed-type fallback).
 *   - contains / startsWith / endsWith are plain string checks on the
 *     answer.
 *   - inList / notInList accept an array value, or a comma-separated
 *     string ("a, b, c") — membership of the answer in that list.
 *   - regex compiles the value as a RegExp; an invalid pattern is false.
 *   - isTrue matches the string 'true' (toggles/checkboxes store
 *     'true'/'false' strings). isFalse matches 'false' OR an
 *     empty/missing answer — the renderer seeds boolean questions with
 *     'false', but an unseeded boolean should still satisfy "is false".
 *   - Unknown operators and missing answers evaluate to false rather
 *     than throwing — a bad rule must never take the form down.
 */

/**
 * String-content check used to decide numeric vs string comparison
 * (when both sides parse as numbers, compare numerically).
 */
export function isNumericValue(str) {
    if (typeof str !== 'string') return false;
    return !isNaN(str) && !isNaN(parseFloat(str));
}

function toComparable(answerStr, valueStr) {
    if (isNumericValue(answerStr) && isNumericValue(valueStr)) {
        return [parseFloat(answerStr), parseFloat(valueStr)];
    }
    return [answerStr, valueStr];
}

function asList(value) {
    if (Array.isArray(value)) return value.map((v) => String(v).trim());
    return String(value ?? '')
        .split(',')
        .map((v) => v.trim())
        .filter((v) => v.length > 0);
}

/**
 * Evaluate a single condition against the referenced question's answer.
 *
 * @param {object} item              The condition spec.
 *   @param {string} item.operator   Operator key (see semantics above).
 *   @param {string|string[]} item.value  Comparison value.
 * @param {string|undefined} answerValue  The current answer for item.resource.
 * @returns {boolean}
 */
export function evaluateCondition(item, answerValue) {
    const answerStr =
        answerValue === undefined || answerValue === null ? '' : String(answerValue);
    const valueStr = item.value === undefined || item.value === null ? '' : String(item.value);

    switch (item.operator) {
        case 'equals': {
            const [a, v] = toComparable(answerStr, valueStr);
            return a === v;
        }
        case 'notEquals': {
            const [a, v] = toComparable(answerStr, valueStr);
            return a !== v;
        }
        case 'greaterThan': {
            const [a, v] = toComparable(answerStr, valueStr);
            return a > v;
        }
        case 'lessThan': {
            const [a, v] = toComparable(answerStr, valueStr);
            return a < v;
        }
        case 'greaterThanOrEqual': {
            const [a, v] = toComparable(answerStr, valueStr);
            return a >= v;
        }
        case 'lessThanOrEqual': {
            const [a, v] = toComparable(answerStr, valueStr);
            return a <= v;
        }
        case 'contains':
            return answerStr.includes(valueStr);
        case 'startsWith':
            return answerStr.startsWith(valueStr);
        case 'endsWith':
            return answerStr.endsWith(valueStr);
        case 'inList':
            return asList(item.value).includes(answerStr);
        case 'notInList':
            return !asList(item.value).includes(answerStr);
        case 'regex': {
            try {
                return new RegExp(valueStr).test(answerStr);
            } catch (e) {
                return false;
            }
        }
        case 'isTrue':
            return answerStr.toLowerCase() === 'true';
        case 'isFalse':
            return answerStr === '' || answerStr.toLowerCase() === 'false';
        default:
            return false;
    }
}

/**
 * Build a Map<key, booleanResult> from a list of condition specs and
 * a resolver that fetches the answer value for each referenced question.
 *
 * @param {Array<{key:string, resource:string}>} conditions
 * @param {(questionId:string) => string|undefined} resolveAnswer
 * @returns {Map<string, boolean>}
 */
export function buildKeyConditionMap(conditions, resolveAnswer) {
    const map = new Map();
    if (!Array.isArray(conditions)) return map;
    conditions.forEach((item) => {
        const answerValue =
            typeof resolveAnswer === 'function'
                ? resolveAnswer(item.resource)
                : undefined;
        map.set(item.key, evaluateCondition(item, answerValue));
    });
    return map;
}
