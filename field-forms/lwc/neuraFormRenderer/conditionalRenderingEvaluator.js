/**
 * Conditional-rendering condition evaluator — pure helpers extracted
 * from neuraFormRenderer's getKeyConditionMap / isNumericValue. Used
 * by the renderer to decide which pages / sections / questions should
 * render based on the current answers.
 *
 * Why this lives in its own module:
 *   The logic is purely a transform from (condition, answerValue) -> boolean.
 *   It deserves direct unit-test coverage because:
 *     - The operator table is broad (equals / contains / inList /
 *       startsWith / etc.) and each path has its own quoting + array
 *       handling rules.
 *     - It uses eval() to evaluate the assembled expression — preserved
 *       exactly to avoid behavior changes during the refactor. Tests
 *       lock in the eval-based semantics so a future safer rewrite
 *       (a parser instead of eval) can be validated against them.
 *
 * eval() safety note:
 *   The operator + value sources come from admin-curated metadata on
 *   Form_Question / Form_Section / Form_Page rendering conditions, not
 *   from end-user input. The exploitable surface is "an admin with edit
 *   access to the form template can inject JS that runs in the
 *   renderer," which is already true via many other vectors (custom
 *   formulas, Display Rich Text, etc.). Tightening to a real parser is
 *   future work — out of scope for this refactor.
 */
import {
    OPERATOR_MAP,
    STRING_LIST_OPERATORS,
    NEGATION_STRING_LIST_OPERATORS
} from './constants';

/**
 * String-content check used to decide whether to wrap a value in quotes
 * (when both sides parse as numbers, use numeric comparison; otherwise
 * fall back to string comparison).
 */
export function isNumericValue(str) {
    if (typeof str !== 'string') return false;
    return !isNaN(str) && !isNaN(parseFloat(str));
}

/**
 * Builds the JS expression string for a single condition + evaluates it.
 * Returns the boolean result.
 *
 * @param {object} item              The condition spec.
 *   @param {string} item.operator   Key in OPERATOR_MAP.
 *   @param {string|string[]} item.value  Comparison value (array for IN/NOT_IN).
 * @param {string|undefined} answerValue  The current answer for item.resource.
 * @returns {boolean}
 */
export function evaluateCondition(item, answerValue) {
    let condition;

    if (STRING_LIST_OPERATORS.includes(item.operator)) {
        if (Array.isArray(item.value)) {
            // Build a JS array literal: ['a','b','c']
            const stringArray = item.value.map((v) => `'${v}'`).join(',');
            condition = `[${stringArray}].${OPERATOR_MAP.get(item.operator)}('${answerValue}')`;
        } else {
            condition = `'${answerValue}'.${OPERATOR_MAP.get(item.operator)}('${item.value}')`;
        }
        if (NEGATION_STRING_LIST_OPERATORS.includes(item.operator)) {
            condition = `!${condition}`;
        }
    } else if (isNumericValue(answerValue) && isNumericValue(item.value)) {
        // Both sides parse as numbers — compare numerically (no quotes).
        condition = `${answerValue} ${OPERATOR_MAP.get(item.operator)} ${item.value}`;
    } else {
        condition = `'${answerValue}' ${OPERATOR_MAP.get(item.operator)} '${item.value}'`;
    }

    // eslint-disable-next-line no-eval
    return eval(condition);
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
