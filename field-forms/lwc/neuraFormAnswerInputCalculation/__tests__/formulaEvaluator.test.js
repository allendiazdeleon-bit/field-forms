import { evaluateFormula, extractReferences, formatResult } from '../formulaEvaluator';

const resolver = (map) => (id) => map[id];

describe('evaluateFormula', () => {
    it('handles bare arithmetic', () => {
        expect(evaluateFormula('2 + 3 * 4', resolver({})).value).toBe(14);
        expect(evaluateFormula('(2 + 3) * 4', resolver({})).value).toBe(20);
        expect(evaluateFormula('10 / 4', resolver({})).value).toBe(2.5);
        expect(evaluateFormula('10 % 3', resolver({})).value).toBe(1);
        expect(evaluateFormula('-5 + 8', resolver({})).value).toBe(3);
    });

    it('resolves {{questionId}} references', () => {
        const r = resolver({ q1: '10', q2: '4' });
        expect(evaluateFormula('{{q1}} + {{q2}}', r).value).toBe(14);
        expect(evaluateFormula('{{q1}} * {{q2}}', r).value).toBe(40);
    });

    it('treats missing or non-numeric references as zero', () => {
        const r = resolver({ q1: 'banana', q2: '5' });
        expect(evaluateFormula('{{q1}} + {{q2}}', r).value).toBe(5);
        expect(evaluateFormula('{{missing}} + 7', r).value).toBe(7);
    });

    it('supports SUM / AVG / MIN / MAX / COUNT', () => {
        const r = resolver({ a: '1', b: '2', c: '3' });
        expect(evaluateFormula('SUM({{a}}, {{b}}, {{c}})', r).value).toBe(6);
        expect(evaluateFormula('AVG({{a}}, {{b}}, {{c}})', r).value).toBe(2);
        expect(evaluateFormula('MIN({{a}}, {{b}}, {{c}})', r).value).toBe(1);
        expect(evaluateFormula('MAX({{a}}, {{b}}, {{c}})', r).value).toBe(3);
        expect(evaluateFormula('COUNT({{a}}, {{b}}, {{c}})', r).value).toBe(3);
    });

    it('supports ROUND, ABS, IF', () => {
        expect(evaluateFormula('ROUND(3.14159, 2)', resolver({})).value).toBe(3.14);
        expect(evaluateFormula('ROUND(3.5)', resolver({})).value).toBe(4);
        expect(evaluateFormula('ABS(-7)', resolver({})).value).toBe(7);
        expect(evaluateFormula('IF(1, 10, 20)', resolver({})).value).toBe(10);
        expect(evaluateFormula('IF(0, 10, 20)', resolver({})).value).toBe(20);
    });

    it('returns empty for empty formula', () => {
        const result = evaluateFormula('', resolver({}));
        expect(result.ok).toBe(true);
        expect(result.value).toBe('');
    });

    it('returns ok=false for division by zero', () => {
        const result = evaluateFormula('5 / 0', resolver({}));
        expect(result.ok).toBe(false);
        expect(result.value).toBe('');
    });

    it('returns ok=false for malformed expressions', () => {
        expect(evaluateFormula('2 + + 3', resolver({})).ok).toBe(false);
        expect(evaluateFormula('SUM(', resolver({})).ok).toBe(false);
        expect(evaluateFormula('FOO(1, 2)', resolver({})).ok).toBe(false);
    });

    it('does not allow arbitrary identifiers as expressions', () => {
        // No bare identifier outside a function call is valid - confirms
        // the parser would reject `process.exit()` style probes.
        expect(evaluateFormula('process', resolver({})).ok).toBe(false);
    });
});

describe('extractReferences', () => {
    it('finds every {{id}} in the formula', () => {
        expect(extractReferences('{{a}} + {{b}} * {{c}}')).toEqual(['a', 'b', 'c']);
    });
    it('handles whitespace inside braces', () => {
        expect(extractReferences('{{ a }} + {{  b  }}')).toEqual(['a', 'b']);
    });
    it('returns empty array for blank input', () => {
        expect(extractReferences('')).toEqual([]);
        expect(extractReferences(null)).toEqual([]);
    });
});

describe('formatResult', () => {
    it('formats Decimal as raw stringified number', () => {
        expect(formatResult(3.14, 'Decimal')).toBe('3.14');
    });
    it('rounds Integer', () => {
        expect(formatResult(3.7, 'Integer')).toBe('4');
    });
    it('formats Percent', () => {
        expect(formatResult(0.5, 'Percent')).toBe('50.00%');
    });
    it('returns empty string for empty/null/NaN', () => {
        expect(formatResult('', 'Decimal')).toBe('');
        expect(formatResult(null, 'Decimal')).toBe('');
        expect(formatResult(NaN, 'Decimal')).toBe('');
    });
});
