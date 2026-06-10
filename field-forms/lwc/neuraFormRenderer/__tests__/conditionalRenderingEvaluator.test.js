import {
    isNumericValue,
    evaluateCondition,
    buildKeyConditionMap
} from '../conditionalRenderingEvaluator';

/**
 * Direct coverage for the conditional-rendering evaluator.
 *
 * These tests cover the CORRECTED semantics that replaced the original
 * eval()-based evaluator: comparison operators read naturally
 * ("answer greaterThan value" means answer > value — the old OPERATOR_MAP
 * ran them inverted), isTrue/isFalse are real operators, and end-user
 * answer text can never break evaluation (the old version interpolated
 * answers into an eval'd string, so an apostrophe threw a SyntaxError).
 */

describe('isNumericValue', () => {
    it('returns true for numeric strings', () => {
        expect(isNumericValue('0')).toBe(true);
        expect(isNumericValue('42')).toBe(true);
        expect(isNumericValue('-3.14')).toBe(true);
        expect(isNumericValue('1e5')).toBe(true);
    });

    it('returns false for non-numeric strings', () => {
        expect(isNumericValue('hello')).toBe(false);
        expect(isNumericValue('')).toBe(false);
        expect(isNumericValue('   ')).toBe(false);
        expect(isNumericValue('1abc')).toBe(false);
    });

    it('returns false for non-strings (numbers, null, undefined)', () => {
        expect(isNumericValue(42)).toBe(false);
        expect(isNumericValue(null)).toBe(false);
        expect(isNumericValue(undefined)).toBe(false);
        expect(isNumericValue({})).toBe(false);
    });
});

describe('evaluateCondition — equality / inequality', () => {
    it('"equals" with numeric strings does numeric compare', () => {
        expect(evaluateCondition({ operator: 'equals', value: '5' }, '5')).toBe(true);
        expect(evaluateCondition({ operator: 'equals', value: '5.0' }, '5')).toBe(true);
        expect(evaluateCondition({ operator: 'equals', value: '5' }, '6')).toBe(false);
    });

    it('"equals" with non-numeric strings does string compare', () => {
        expect(evaluateCondition({ operator: 'equals', value: 'yes' }, 'yes')).toBe(true);
        expect(evaluateCondition({ operator: 'equals', value: 'yes' }, 'no')).toBe(false);
    });

    it('"notEquals" flips equality', () => {
        expect(evaluateCondition({ operator: 'notEquals', value: 'yes' }, 'no')).toBe(true);
        expect(evaluateCondition({ operator: 'notEquals', value: 'yes' }, 'yes')).toBe(false);
    });
});

describe('evaluateCondition — numeric comparisons (corrected orientation)', () => {
    // "answer greaterThan value" must mean answer > value. The original
    // OPERATOR_MAP inverted these — an admin authoring "Temperature
    // Greater Than 40" got a condition that fired when temperature was
    // BELOW 40. An org scan found zero stored conditions, so correcting
    // the orientation breaks nothing in place.
    it('"greaterThan" is true when the answer exceeds the value', () => {
        expect(evaluateCondition({ operator: 'greaterThan', value: '10' }, '15')).toBe(true);
        expect(evaluateCondition({ operator: 'greaterThan', value: '10' }, '5')).toBe(false);
        expect(evaluateCondition({ operator: 'greaterThan', value: '10' }, '10')).toBe(false);
    });

    it('"lessThan" is true when the answer is below the value', () => {
        expect(evaluateCondition({ operator: 'lessThan', value: '10' }, '5')).toBe(true);
        expect(evaluateCondition({ operator: 'lessThan', value: '10' }, '15')).toBe(false);
    });

    it('"greaterThanOrEqual" / "lessThanOrEqual" include the boundary', () => {
        expect(evaluateCondition({ operator: 'greaterThanOrEqual', value: '10' }, '10')).toBe(true);
        expect(evaluateCondition({ operator: 'greaterThanOrEqual', value: '10' }, '9')).toBe(false);
        expect(evaluateCondition({ operator: 'lessThanOrEqual', value: '10' }, '10')).toBe(true);
        expect(evaluateCondition({ operator: 'lessThanOrEqual', value: '10' }, '11')).toBe(false);
    });
});

describe('evaluateCondition — string-list operators', () => {
    it('"contains" checks substring membership in the answer', () => {
        expect(
            evaluateCondition({ operator: 'contains', value: 'ello' }, 'hello world')
        ).toBe(true);
        expect(
            evaluateCondition({ operator: 'contains', value: 'xyz' }, 'hello world')
        ).toBe(false);
    });

    it('"inList" with an array checks membership', () => {
        expect(
            evaluateCondition({ operator: 'inList', value: ['a', 'b', 'c'] }, 'b')
        ).toBe(true);
        expect(
            evaluateCondition({ operator: 'inList', value: ['a', 'b', 'c'] }, 'z')
        ).toBe(false);
    });

    it('"inList" with a comma-separated string checks membership', () => {
        expect(evaluateCondition({ operator: 'inList', value: 'a, b, c' }, 'b')).toBe(true);
        expect(evaluateCondition({ operator: 'inList', value: 'a, b, c' }, 'z')).toBe(false);
    });

    it('"notInList" negates membership', () => {
        expect(
            evaluateCondition({ operator: 'notInList', value: ['a', 'b'] }, 'z')
        ).toBe(true);
        expect(
            evaluateCondition({ operator: 'notInList', value: ['a', 'b'] }, 'a')
        ).toBe(false);
    });

    it('"startsWith" / "endsWith" do prefix / suffix string checks', () => {
        expect(evaluateCondition({ operator: 'startsWith', value: 'hello' }, 'hello world')).toBe(true);
        expect(evaluateCondition({ operator: 'startsWith', value: 'world' }, 'hello world')).toBe(false);
        expect(evaluateCondition({ operator: 'endsWith', value: 'world' }, 'hello world')).toBe(true);
        expect(evaluateCondition({ operator: 'endsWith', value: 'hello' }, 'hello world')).toBe(false);
    });

    it('"regex" matches patterns and treats invalid patterns as false', () => {
        expect(evaluateCondition({ operator: 'regex', value: '^h.llo' }, 'hello world')).toBe(true);
        expect(evaluateCondition({ operator: 'regex', value: '^x' }, 'hello world')).toBe(false);
        expect(evaluateCondition({ operator: 'regex', value: '[unclosed' }, 'anything')).toBe(false);
    });
});

describe('evaluateCondition — boolean operators (previously unevaluable)', () => {
    it('"isTrue" matches the toggle/checkbox true string', () => {
        expect(evaluateCondition({ operator: 'isTrue' }, 'true')).toBe(true);
        expect(evaluateCondition({ operator: 'isTrue' }, 'True')).toBe(true);
        expect(evaluateCondition({ operator: 'isTrue' }, 'false')).toBe(false);
        expect(evaluateCondition({ operator: 'isTrue' }, undefined)).toBe(false);
    });

    it('"isFalse" matches false AND unanswered (boolean questions default off)', () => {
        expect(evaluateCondition({ operator: 'isFalse' }, 'false')).toBe(true);
        expect(evaluateCondition({ operator: 'isFalse' }, '')).toBe(true);
        expect(evaluateCondition({ operator: 'isFalse' }, undefined)).toBe(true);
        expect(evaluateCondition({ operator: 'isFalse' }, 'true')).toBe(false);
    });
});

describe('evaluateCondition — hostile/edge inputs never throw', () => {
    it("an apostrophe in the answer doesn't break evaluation", () => {
        // The eval()-based version threw a SyntaxError here, killing
        // conditional rendering for the page.
        expect(evaluateCondition({ operator: 'contains', value: 'leak' }, "it's leaking")).toBe(true);
        expect(evaluateCondition({ operator: 'equals', value: 'x' }, "it's leaking")).toBe(false);
    });

    it('script-looking answers are treated as plain strings', () => {
        const hostile = "'); alert(1); ('";
        expect(evaluateCondition({ operator: 'equals', value: hostile }, hostile)).toBe(true);
        expect(evaluateCondition({ operator: 'contains', value: 'alert' }, hostile)).toBe(true);
    });

    it('unknown operators evaluate to false instead of throwing', () => {
        expect(evaluateCondition({ operator: 'doesNotExist', value: 'x' }, 'x')).toBe(false);
    });
});

describe('buildKeyConditionMap', () => {
    it('resolves each condition with the provided resolver', () => {
        const conditions = [
            { key: 'A', resource: 'q1', operator: 'equals', value: 'yes' },
            { key: 'B', resource: 'q2', operator: 'equals', value: '5' }
        ];
        const answers = { q1: 'yes', q2: '5' };
        const map = buildKeyConditionMap(conditions, (id) => answers[id]);
        expect(map.get('A')).toBe(true);
        expect(map.get('B')).toBe(true);
    });

    it('returns false for conditions whose answer is missing (dangling ref)', () => {
        const conditions = [
            { key: 'A', resource: 'deleted-question', operator: 'equals', value: 'yes' }
        ];
        const map = buildKeyConditionMap(conditions, () => undefined);
        expect(map.get('A')).toBe(false);
    });

    it('returns an empty map for empty / non-array input', () => {
        expect(buildKeyConditionMap([], () => 'x').size).toBe(0);
        expect(buildKeyConditionMap(null, () => 'x').size).toBe(0);
        expect(buildKeyConditionMap(undefined, () => 'x').size).toBe(0);
    });

    it('survives a missing resolver function', () => {
        const conditions = [
            { key: 'A', resource: 'q1', operator: 'equals', value: '' }
        ];
        const map = buildKeyConditionMap(conditions);
        expect(map.has('A')).toBe(true);
    });
});
