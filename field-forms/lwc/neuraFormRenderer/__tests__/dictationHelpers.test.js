import {
    collectDictatableQuestions,
    formatDictationDiagnostic,
    formatDictationSuccessMessage
} from '../dictationHelpers';

const FIELDS = { type: 'Type__c', valueSet: 'Value_Set__c', question: 'Question__c' };

function makePage(sections) {
    return { sections };
}
function makeQuestion(over = {}) {
    return {
        Id: 'q1',
        Type__c: 'Text',
        Question__c: 'Test question',
        Value_Set__c: '',
        shouldRender: true,
        ...over
    };
}

describe('collectDictatableQuestions', () => {
    it('returns one entry per visible question across all sections', () => {
        const page = makePage([
            { questions: [makeQuestion({ Id: 'q1' }), makeQuestion({ Id: 'q2' })] },
            { questions: [makeQuestion({ Id: 'q3' })] }
        ]);
        const out = collectDictatableQuestions(page, FIELDS);
        expect(out.map((q) => q.questionId)).toEqual(['q1', 'q2', 'q3']);
    });

    it('skips questions hidden by conditional rendering', () => {
        const page = makePage([
            { questions: [
                makeQuestion({ Id: 'q1' }),
                makeQuestion({ Id: 'q2', shouldRender: false }),
                makeQuestion({ Id: 'q3' })
            ] }
        ]);
        const out = collectDictatableQuestions(page, FIELDS);
        expect(out.map((q) => q.questionId)).toEqual(['q1', 'q3']);
    });

    it('parses Value_Set__c into allowedValues, ignoring null/empty entries', () => {
        const page = makePage([
            { questions: [makeQuestion({
                Id: 'q1',
                Value_Set__c: '[{"label":"Yes","value":"yes"},{"label":"No","value":"no"},{"label":"","value":""}]'
            })] }
        ]);
        const out = collectDictatableQuestions(page, FIELDS);
        expect(out[0].allowedValues).toEqual(['yes', 'no']);
    });

    it('returns an empty array when Value_Set__c is malformed JSON', () => {
        const page = makePage([
            { questions: [makeQuestion({ Value_Set__c: 'not JSON' })] }
        ]);
        const out = collectDictatableQuestions(page, FIELDS);
        expect(out[0].allowedValues).toEqual([]);
    });

    it('falls back to q.Name when the question field is missing', () => {
        const page = makePage([
            { questions: [{ Id: 'q1', Name: 'Fallback', shouldRender: true }] }
        ]);
        const out = collectDictatableQuestions(page, FIELDS);
        expect(out[0].label).toBe('Fallback');
    });

    it('returns [] for a missing or malformed page', () => {
        expect(collectDictatableQuestions(null, FIELDS)).toEqual([]);
        expect(collectDictatableQuestions({}, FIELDS)).toEqual([]);
        expect(collectDictatableQuestions({ sections: null }, FIELDS)).toEqual([]);
    });

    it('skips sections with no questions array', () => {
        const page = makePage([
            { questions: null },
            { questions: [makeQuestion({ Id: 'q1' })] }
        ]);
        const out = collectDictatableQuestions(page, FIELDS);
        expect(out.map((q) => q.questionId)).toEqual(['q1']);
    });
});

describe('formatDictationDiagnostic', () => {
    it('returns the empty-page message when questionCount is 0', () => {
        expect(formatDictationDiagnostic({ questionCount: 0 })).toMatch(
            /no questions visible/i
        );
    });

    it('returns the server diagnostic when present', () => {
        const msg = 'Server says: try saying the field name first.';
        expect(formatDictationDiagnostic({ questionCount: 3, diagnostic: msg })).toBe(msg);
    });

    it("returns the local fallback with the visible question count", () => {
        const msg = formatDictationDiagnostic({ questionCount: 7 });
        expect(msg).toMatch(/Couldn't match/);
        expect(msg).toMatch(/7 questions on page/);
    });

    it('handles a result missing questionCount entirely', () => {
        const msg = formatDictationDiagnostic({});
        expect(msg).toMatch(/0 questions on page/);
    });

    it('handles a missing result object', () => {
        const msg = formatDictationDiagnostic(undefined);
        expect(msg).toMatch(/0 questions on page/);
    });
});

describe('formatDictationSuccessMessage', () => {
    it('uses singular "field" for one mapping', () => {
        expect(formatDictationSuccessMessage(1)).toBe(
            'Filled 1 field from dictation. Review before continuing.'
        );
    });

    it('uses plural "fields" otherwise', () => {
        expect(formatDictationSuccessMessage(3)).toBe(
            'Filled 3 fields from dictation. Review before continuing.'
        );
        expect(formatDictationSuccessMessage(0)).toBe(
            'Filled 0 fields from dictation. Review before continuing.'
        );
    });

    it('adds (Agentforce) suffix when source is "agentforce"', () => {
        expect(formatDictationSuccessMessage(2, 'agentforce')).toBe(
            'Filled 2 fields from dictation (Agentforce). Review before continuing.'
        );
    });

    it('ignores other source labels', () => {
        expect(formatDictationSuccessMessage(2, 'openai')).toBe(
            'Filled 2 fields from dictation. Review before continuing.'
        );
    });

    it('coerces non-numeric mappingsCount', () => {
        expect(formatDictationSuccessMessage('5')).toBe(
            'Filled 5 fields from dictation. Review before continuing.'
        );
        expect(formatDictationSuccessMessage(null)).toBe(
            'Filled 0 fields from dictation. Review before continuing.'
        );
    });
});
