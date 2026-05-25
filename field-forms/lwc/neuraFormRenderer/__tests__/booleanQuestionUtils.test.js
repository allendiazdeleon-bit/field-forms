import {
    isBooleanQuestionType,
    filterBooleanQuestions,
    BOOLEAN_QUESTION_TYPES
} from '../booleanQuestionUtils';

describe('isBooleanQuestionType', () => {
    it('returns true for the boolean-flavored types', () => {
        expect(isBooleanQuestionType('Toggle')).toBe(true);
        expect(isBooleanQuestionType('Checkbox')).toBe(true);
    });

    it('returns false for non-boolean types', () => {
        expect(isBooleanQuestionType('Text')).toBe(false);
        expect(isBooleanQuestionType('Pass Fail NA')).toBe(false);
        expect(isBooleanQuestionType('Checkboxes')).toBe(false); // plural — multi-checkbox, not boolean
    });

    it('returns false for empty / missing', () => {
        expect(isBooleanQuestionType('')).toBe(false);
        expect(isBooleanQuestionType(null)).toBe(false);
        expect(isBooleanQuestionType(undefined)).toBe(false);
    });
});

describe('filterBooleanQuestions', () => {
    const TYPE_FIELD = 'Type__c';

    it('returns only the boolean-flavored questions from a section', () => {
        const questions = [
            { Id: 'q1', Type__c: 'Text' },
            { Id: 'q2', Type__c: 'Toggle' },
            { Id: 'q3', Type__c: 'Checkbox' },
            { Id: 'q4', Type__c: 'Number' }
        ];
        const filtered = filterBooleanQuestions(questions, TYPE_FIELD);
        expect(filtered.map((q) => q.Id)).toEqual(['q2', 'q3']);
    });

    it('returns an empty array for non-array input', () => {
        expect(filterBooleanQuestions(null, TYPE_FIELD)).toEqual([]);
        expect(filterBooleanQuestions(undefined, TYPE_FIELD)).toEqual([]);
        expect(filterBooleanQuestions('not-an-array', TYPE_FIELD)).toEqual([]);
    });

    it('returns an empty array when typeFieldApiName is missing', () => {
        expect(filterBooleanQuestions([{ Id: 'q1', Type__c: 'Toggle' }], '')).toEqual([]);
        expect(filterBooleanQuestions([{ Id: 'q1', Type__c: 'Toggle' }], null)).toEqual([]);
    });

    it('skips null entries in the input array without crashing', () => {
        const questions = [null, { Id: 'q1', Type__c: 'Toggle' }, undefined];
        expect(filterBooleanQuestions(questions, TYPE_FIELD).map((q) => q.Id)).toEqual(['q1']);
    });
});

describe('BOOLEAN_QUESTION_TYPES registry', () => {
    it('is frozen so callers cannot accidentally mutate it', () => {
        expect(Object.isFrozen(BOOLEAN_QUESTION_TYPES)).toBe(true);
    });

    it('matches the documented set', () => {
        expect(BOOLEAN_QUESTION_TYPES).toEqual(['Toggle', 'Checkbox']);
    });
});
