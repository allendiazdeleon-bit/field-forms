import {
    isNumericValue,
    evaluateCondition,
    buildKeyConditionMap
} from '../conditionalRenderingEvaluator';

/**
 * Direct coverage for the conditional-rendering evaluator. Pre-wave-30
 * these branches lived inside neuraFormRenderer.getKeyConditionMap with
 * no test coverage at all — every operator was "trust the metadata,
 * trust the eval, hope for the best."
 *
 * The tests below lock in the EXISTING semantics, not what the
 * semantics arguably should be. A future safer-eval rewrite can be
 * validated against these.
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

describe('evaluateCondition — numeric comparisons (note: OPERATOR_MAP is inverted)', () => {
    // OPERATOR_MAP defines greaterThan -> '<' (intentional or legacy bug;
    // the test locks in current behavior, not the arguably-correct one).
    it('"greaterThan" uses < operator (existing semantics)', () => {
        expect(evaluateCondition({ operator: 'greaterThan', value: '10' }, '5')).toBe(true);
        expect(evaluateCondition({ operator: 'greaterThan', value: '5' }, '10')).toBe(false);
    });

    it('"lessThan" uses > operator (existing semantics)', () => {
        expect(evaluateCondition({ operator: 'lessThan', value: '5' }, '10')).toBe(true);
        expect(evaluateCondition({ operator: 'lessThan', value: '10' }, '5')).toBe(false);
    });
});

describe('evaluateCondition — string-list operators', () => {
    it('"contains" on a plain string maps to String.includes', () => {
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

    it('"notInList" with an array negates membership', () => {
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

    it('returns false for conditions whose answer is missing', () => {
        const conditions = [
            { key: 'A', resource: 'q1', operator: 'equals', value: 'yes' }
        ];
        const map = buildKeyConditionMap(conditions, () => undefined);
        // 'undefined' === 'yes' → false
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
        // answerValue is undefined; '' === 'undefined' is false. Should not throw.
        const map = buildKeyConditionMap(conditions);
        expect(map.has('A')).toBe(true);
    });
});
