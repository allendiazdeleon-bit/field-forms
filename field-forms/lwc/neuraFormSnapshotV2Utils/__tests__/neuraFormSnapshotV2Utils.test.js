import {
    applySnapshotV2,
    normalizeSnapshotChunksFromGraphQL,
    normalizeSnapshotChunksFromApex
} from 'c/neuraFormSnapshotV2Utils';

describe('applySnapshotV2', () => {
    test('returns the formTemplate unchanged when no chunks are provided', () => {
        const tpl = { Id: 't1', Pages_JSON__c: '[{"Id":"p1"}]' };
        expect(applySnapshotV2(tpl, [])).toBe(tpl);
        expect(applySnapshotV2(tpl, null)).toBe(tpl);
        expect(applySnapshotV2(tpl, undefined)).toBe(tpl);
    });

    test('returns the formTemplate unchanged when chunks is an empty array', () => {
        const tpl = { Id: 't1', Pages_JSON__c: '[{"Id":"p1"}]' };
        const result = applySnapshotV2(tpl, []);
        expect(result).toBe(tpl);
    });

    test('assembles a single payload type with one chunk', () => {
        const tpl = { Id: 't1', Pages_JSON__c: '[{"Id":"old"}]' };
        const chunks = [
            { type: 'Pages', index: 0, payload: '[{"Id":"p1"},{"Id":"p2"}]' }
        ];
        const result = applySnapshotV2(tpl, chunks);

        expect(JSON.parse(result.Pages_JSON__c)).toEqual([
            { Id: 'p1' },
            { Id: 'p2' }
        ]);
        // Original object is not mutated.
        expect(tpl.Pages_JSON__c).toBe('[{"Id":"old"}]');
    });

    test('concatenates multiple chunks of the same type in index order', () => {
        // Intentionally inserted out of order to verify sort behavior.
        const chunks = [
            { type: 'Questions', index: 1, payload: '[{"Id":"q3"}]' },
            { type: 'Questions', index: 0, payload: '[{"Id":"q1"},{"Id":"q2"}]' },
            { type: 'Questions', index: 2, payload: '[{"Id":"q4"}]' }
        ];
        const result = applySnapshotV2({}, chunks);
        const questions = JSON.parse(result.Questions_JSON__c);
        expect(questions.map((q) => q.Id)).toEqual(['q1', 'q2', 'q3', 'q4']);
    });

    test('handles all six payload types in one call', () => {
        const chunks = [
            { type: 'Pages', index: 0, payload: '[{"Id":"p1"}]' },
            { type: 'Sections', index: 0, payload: '[{"Id":"s1"}]' },
            { type: 'Questions', index: 0, payload: '[{"Id":"q1"}]' },
            { type: 'PageConditions', index: 0, payload: '[{"id":"p1","conditions":[]}]' },
            { type: 'SectionConditions', index: 0, payload: '[{"id":"s1","conditions":[]}]' },
            { type: 'QuestionConditions', index: 0, payload: '[{"id":"q1","conditions":[]}]' }
        ];
        const result = applySnapshotV2({}, chunks);

        expect(JSON.parse(result.Pages_JSON__c)).toEqual([{ Id: 'p1' }]);
        expect(JSON.parse(result.Sections_JSON__c)).toEqual([{ Id: 's1' }]);
        expect(JSON.parse(result.Questions_JSON__c)).toEqual([{ Id: 'q1' }]);
        expect(JSON.parse(result.Page_Conditions__c)).toEqual([
            { id: 'p1', conditions: [] }
        ]);
        expect(JSON.parse(result.Section_Conditions__c)).toEqual([
            { id: 's1', conditions: [] }
        ]);
        expect(JSON.parse(result.Question_Conditions__c)).toEqual([
            { id: 'q1', conditions: [] }
        ]);
    });

    test('clears legacy overflow chunk fields when Questions chunks are present', () => {
        const tpl = {
            Questions_JSON_1__c: '[{"Id":"stale"}]',
            Questions_JSON_2__c: '[{"Id":"stale2"}]'
        };
        const chunks = [
            { type: 'Questions', index: 0, payload: '[{"Id":"q1"}]' }
        ];
        const result = applySnapshotV2(tpl, chunks);
        expect(result.Questions_JSON_1__c).toBeNull();
        expect(result.Questions_JSON_2__c).toBeNull();
    });

    test('preserves untouched legacy fields when only some payload types are present', () => {
        const tpl = {
            Pages_JSON__c: '[{"Id":"legacy-page"}]',
            Sections_JSON__c: '[{"Id":"legacy-section"}]'
        };
        const chunks = [
            { type: 'Questions', index: 0, payload: '[{"Id":"q1"}]' }
        ];
        const result = applySnapshotV2(tpl, chunks);
        // Pages and Sections still hold their legacy values because the
        // chunk set didn't include them.
        expect(result.Pages_JSON__c).toBe('[{"Id":"legacy-page"}]');
        expect(result.Sections_JSON__c).toBe('[{"Id":"legacy-section"}]');
        expect(JSON.parse(result.Questions_JSON__c)).toEqual([{ Id: 'q1' }]);
    });

    test('degrades gracefully on a malformed chunk payload', () => {
        // Silence the console.error this triggers so the test output stays clean.
        const errSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
        const chunks = [
            { type: 'Questions', index: 0, payload: '[{"Id":"q1"}]' },
            { type: 'Questions', index: 1, payload: 'not-valid-json' },
            { type: 'Questions', index: 2, payload: '[{"Id":"q3"}]' }
        ];
        const result = applySnapshotV2({}, chunks);
        // Bad chunk is dropped; surrounding chunks still contribute.
        expect(JSON.parse(result.Questions_JSON__c)).toEqual([
            { Id: 'q1' },
            { Id: 'q3' }
        ]);
        expect(errSpy).toHaveBeenCalled();
        errSpy.mockRestore();
    });

    test('ignores chunks with no type or null payload defensively', () => {
        const chunks = [
            { type: null, index: 0, payload: '[{"Id":"x"}]' },
            { type: 'Pages', index: 0, payload: null },
            { type: 'Pages', index: 1, payload: '[{"Id":"p1"}]' }
        ];
        const result = applySnapshotV2({}, chunks);
        expect(JSON.parse(result.Pages_JSON__c)).toEqual([{ Id: 'p1' }]);
    });

    test('does not include keys for payload types absent from chunks', () => {
        const chunks = [
            { type: 'Pages', index: 0, payload: '[{"Id":"p1"}]' }
        ];
        const result = applySnapshotV2({ Id: 't1' }, chunks);
        expect(result.Sections_JSON__c).toBeUndefined();
        expect(result.Questions_JSON__c).toBeUndefined();
    });
});

describe('normalizeSnapshotChunksFromGraphQL', () => {
    test('returns empty array when no Form_Template_Snapshots__r relationship', () => {
        expect(normalizeSnapshotChunksFromGraphQL({})).toEqual([]);
        expect(normalizeSnapshotChunksFromGraphQL(null)).toEqual([]);
        expect(
            normalizeSnapshotChunksFromGraphQL({ Form_Template_Snapshots__r: {} })
        ).toEqual([]);
    });

    test('flattens edges/node/value wrapping into {type, index, payload}', () => {
        const formTemplate = {
            Form_Template_Snapshots__r: {
                edges: [
                    {
                        node: {
                            Payload_Type__c: { value: 'Pages' },
                            Chunk_Index__c: { value: 0 },
                            Payload__c: { value: '[{"Id":"p1"}]' }
                        }
                    },
                    {
                        node: {
                            Payload_Type__c: { value: 'Questions' },
                            Chunk_Index__c: { value: 3 },
                            Payload__c: { value: '[{"Id":"q1"}]' }
                        }
                    }
                ]
            }
        };
        const result = normalizeSnapshotChunksFromGraphQL(formTemplate);
        expect(result).toEqual([
            { type: 'Pages', index: 0, payload: '[{"Id":"p1"}]' },
            { type: 'Questions', index: 3, payload: '[{"Id":"q1"}]' }
        ]);
    });

    test('coerces missing Chunk_Index__c.value to 0', () => {
        const formTemplate = {
            Form_Template_Snapshots__r: {
                edges: [
                    {
                        node: {
                            Payload_Type__c: { value: 'Pages' },
                            Chunk_Index__c: { value: null },
                            Payload__c: { value: '[]' }
                        }
                    }
                ]
            }
        };
        const [chunk] = normalizeSnapshotChunksFromGraphQL(formTemplate);
        expect(chunk.index).toBe(0);
    });
});

describe('normalizeSnapshotChunksFromApex', () => {
    test('returns empty array when input is falsy', () => {
        expect(normalizeSnapshotChunksFromApex(null)).toEqual([]);
        expect(normalizeSnapshotChunksFromApex(undefined)).toEqual([]);
        expect(normalizeSnapshotChunksFromApex([])).toEqual([]);
    });

    test('maps bare SObject shape to {type, index, payload}', () => {
        const apexChunks = [
            {
                Id: 'a01',
                Payload_Type__c: 'Pages',
                Chunk_Index__c: 0,
                Payload__c: '[{"Id":"p1"}]'
            },
            {
                Id: 'a02',
                Payload_Type__c: 'Questions',
                Chunk_Index__c: 2,
                Payload__c: '[{"Id":"q1"}]'
            }
        ];
        const result = normalizeSnapshotChunksFromApex(apexChunks);
        expect(result).toEqual([
            { type: 'Pages', index: 0, payload: '[{"Id":"p1"}]' },
            { type: 'Questions', index: 2, payload: '[{"Id":"q1"}]' }
        ]);
    });

    test('coerces null Chunk_Index__c to 0', () => {
        const apexChunks = [
            { Payload_Type__c: 'Pages', Chunk_Index__c: null, Payload__c: '[]' }
        ];
        const [chunk] = normalizeSnapshotChunksFromApex(apexChunks);
        expect(chunk.index).toBe(0);
    });
});

describe('end-to-end: GraphQL shape → applySnapshotV2', () => {
    test('renders a complete formTemplate from a realistic GraphQL response', () => {
        const formTemplate = {
            Id: 't1',
            Name: 'My Form',
            Pages_JSON__c: null, // v2 writer nulls legacy
            Sections_JSON__c: null,
            Questions_JSON__c: null,
            Form_Template_Snapshots__r: {
                edges: [
                    {
                        node: {
                            Payload_Type__c: { value: 'Pages' },
                            Chunk_Index__c: { value: 0 },
                            Payload__c: { value: '[{"Id":"p1","Order__c":1}]' }
                        }
                    },
                    {
                        node: {
                            Payload_Type__c: { value: 'Sections' },
                            Chunk_Index__c: { value: 0 },
                            Payload__c: { value: '[{"Id":"s1","Form_Page__c":"p1"}]' }
                        }
                    },
                    {
                        node: {
                            Payload_Type__c: { value: 'Questions' },
                            Chunk_Index__c: { value: 0 },
                            Payload__c: { value: '[{"Id":"q1","Form_Section__c":"s1"}]' }
                        }
                    }
                ]
            }
        };
        const chunks = normalizeSnapshotChunksFromGraphQL(formTemplate);
        const assembled = applySnapshotV2(formTemplate, chunks);

        expect(JSON.parse(assembled.Pages_JSON__c)).toEqual([
            { Id: 'p1', Order__c: 1 }
        ]);
        expect(JSON.parse(assembled.Sections_JSON__c)).toEqual([
            { Id: 's1', Form_Page__c: 'p1' }
        ]);
        expect(JSON.parse(assembled.Questions_JSON__c)).toEqual([
            { Id: 'q1', Form_Section__c: 's1' }
        ]);
    });
});
