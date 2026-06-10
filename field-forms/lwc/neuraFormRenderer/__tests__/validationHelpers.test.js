import {
    collectMissingRequiredLabels,
    isAnswerEmpty
} from '../validationHelpers';

const FIELDS = {
    required: 'Required__c',
    question: 'Question__c',
    answer: 'Answer__c'
};

function makeQ(over = {}) {
    return {
        Id: 'q1',
        Required__c: true,
        Question__c: 'Test question',
        shouldRender: true,
        ...over
    };
}

function answerMap(entries = {}) {
    return new Map(Object.entries(entries));
}

describe('isAnswerEmpty', () => {
    it('treats undefined / null / empty / whitespace as empty', () => {
        expect(isAnswerEmpty(undefined)).toBe(true);
        expect(isAnswerEmpty(null)).toBe(true);
        expect(isAnswerEmpty('')).toBe(true);
        expect(isAnswerEmpty('   ')).toBe(true);
        expect(isAnswerEmpty('\t\n')).toBe(true);
    });

    it('treats any non-empty value as non-empty', () => {
        expect(isAnswerEmpty('x')).toBe(false);
        expect(isAnswerEmpty(' x ')).toBe(false);
        expect(isAnswerEmpty(0)).toBe(false);
        expect(isAnswerEmpty(false)).toBe(false);
        expect(isAnswerEmpty('false')).toBe(false);
    });
});

describe('collectMissingRequiredLabels', () => {
    it('returns labels of required-and-visible-and-empty questions', () => {
        const page = {
            sections: [
                { questions: [
                    makeQ({ Id: 'q1', Question__c: 'Customer name' }),
                    makeQ({ Id: 'q2', Question__c: 'Phone number' })
                ] }
            ]
        };
        const map = answerMap({
            q1: { Answer__c: '' },
            q2: { Answer__c: '   ' }
        });
        expect(collectMissingRequiredLabels(page, map, FIELDS)).toEqual([
            'Customer name', 'Phone number'
        ]);
    });

    it('omits required questions that have a value', () => {
        const page = {
            sections: [{ questions: [makeQ({ Id: 'q1', Question__c: 'Customer name' })] }]
        };
        const map = answerMap({ q1: { Answer__c: 'Alice' } });
        expect(collectMissingRequiredLabels(page, map, FIELDS)).toEqual([]);
    });

    it('omits non-required questions even when empty', () => {
        const page = {
            sections: [{ questions: [makeQ({ Required__c: false, Question__c: 'Optional' })] }]
        };
        expect(collectMissingRequiredLabels(page, answerMap(), FIELDS)).toEqual([]);
    });

    it('omits hidden (shouldRender false) questions even when required + empty', () => {
        const page = {
            sections: [{ questions: [makeQ({
                shouldRender: false,
                Question__c: 'Hidden question'
            })] }]
        };
        expect(collectMissingRequiredLabels(page, answerMap(), FIELDS)).toEqual([]);
    });

    it('falls back to q.Name then "Unnamed question" when Question__c is missing', () => {
        const page = {
            sections: [{ questions: [
                makeQ({ Id: 'q1', Question__c: '', Name: 'NameField' }),
                makeQ({ Id: 'q2', Question__c: '', Name: '' })
            ] }]
        };
        expect(collectMissingRequiredLabels(page, answerMap(), FIELDS)).toEqual([
            'NameField', 'Unnamed question'
        ]);
    });

    it('returns [] for missing/malformed page', () => {
        expect(collectMissingRequiredLabels(null, answerMap(), FIELDS)).toEqual([]);
        expect(collectMissingRequiredLabels({}, answerMap(), FIELDS)).toEqual([]);
        expect(collectMissingRequiredLabels({ sections: null }, answerMap(), FIELDS)).toEqual([]);
    });

    it('returns [] when required/answer field names are missing', () => {
        const page = {
            sections: [{ questions: [makeQ()] }]
        };
        expect(collectMissingRequiredLabels(page, answerMap(), { answer: 'Answer__c' })).toEqual([]);
        expect(collectMissingRequiredLabels(page, answerMap(), { required: 'Required__c' })).toEqual([]);
    });

    it('handles a missing or non-Map answerMap without throwing', () => {
        const page = { sections: [{ questions: [makeQ({ Required__c: true })] }] };
        // answer is missing entirely -> treated as empty -> shows up
        expect(collectMissingRequiredLabels(page, null, FIELDS)).toEqual(['Test question']);
        expect(collectMissingRequiredLabels(page, undefined, FIELDS)).toEqual(['Test question']);
        expect(collectMissingRequiredLabels(page, {}, FIELDS)).toEqual(['Test question']);
    });

    it('walks multiple sections and skips section entries with no questions', () => {
        const page = {
            sections: [
                { questions: null },
                { questions: [makeQ({ Id: 'q1', Question__c: 'First missing' })] },
                { questions: [
                    makeQ({ Id: 'q2', Question__c: 'Second missing' })
                ] }
            ]
        };
        expect(collectMissingRequiredLabels(page, answerMap(), FIELDS)).toEqual([
            'First missing', 'Second missing'
        ]);
    });
});

describe('collectMissingRequiredAcrossPages (finish-time enforcement)', () => {
    const { collectMissingRequiredAcrossPages } = require('../validationHelpers');
    const names = {
        required: 'Required__c',
        question: 'Question__c',
        answer: 'Answer__c',
        type: 'Type__c',
        pageTitle: 'Title__c'
    };
    const q = (id, label, required, type = 'Text') => ({
        Id: id, Required__c: required, Question__c: label, Type__c: type
    });

    it('walks every visible page and tags gaps with page location', () => {
        const pages = [
            { Title__c: 'Exterior', sections: [{ questions: [q('q1', 'Roof condition', true)] }] },
            { Title__c: 'Hidden', shouldRender: false, sections: [{ questions: [q('q2', 'Never shown', true)] }] },
            { Title__c: 'Interior', sections: [{ questions: [q('q3', 'Freezer temp', true), q('q4', 'Notes', false)] }] }
        ];
        const answers = new Map([['q1', { Answer__c: 'Good' }]]);
        const missing = collectMissingRequiredAcrossPages(pages, answers, names);
        expect(missing).toHaveLength(1);
        expect(missing[0]).toMatchObject({ id: 'q3', label: 'Freezer temp', pageIndex: 2, pageTitle: 'Interior' });
    });

    it('returns empty for non-array input', () => {
        expect(collectMissingRequiredAcrossPages(null, new Map(), names)).toEqual([]);
    });
});
