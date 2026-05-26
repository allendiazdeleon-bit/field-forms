import { findQuestionLocation } from '../findingsHelpers';

describe('findQuestionLocation', () => {
    const formObject = {
        pages: [
            {
                sections: [
                    {
                        questions: [
                            { Id: 'q1', External_Reference__c: 'food_safety_1' },
                            { Id: 'q2', External_Reference__c: 'food_safety_2' }
                        ]
                    }
                ]
            },
            {
                sections: [
                    {
                        questions: [
                            { Id: 'q3', External_Reference__c: 'temp_logs_1' }
                        ]
                    },
                    {
                        questions: [
                            { Id: 'q4', External_Reference__c: 'temp_logs_2' }
                        ]
                    }
                ]
            }
        ]
    };

    it('returns null when externalRef is missing', () => {
        expect(findQuestionLocation(formObject, null)).toBeNull();
        expect(findQuestionLocation(formObject, '')).toBeNull();
        expect(findQuestionLocation(formObject, undefined)).toBeNull();
    });

    it('returns null when formObject has no pages', () => {
        expect(findQuestionLocation({}, 'food_safety_1')).toBeNull();
        expect(findQuestionLocation(null, 'food_safety_1')).toBeNull();
    });

    it('finds a question on the first page', () => {
        expect(findQuestionLocation(formObject, 'food_safety_1')).toEqual({
            pageIndex: 0,
            questionId: 'q1'
        });
    });

    it('finds a question on a later page', () => {
        expect(findQuestionLocation(formObject, 'temp_logs_1')).toEqual({
            pageIndex: 1,
            questionId: 'q3'
        });
    });

    it('finds a question in a non-first section of a page', () => {
        expect(findQuestionLocation(formObject, 'temp_logs_2')).toEqual({
            pageIndex: 1,
            questionId: 'q4'
        });
    });

    it('returns null when no question matches the externalRef', () => {
        expect(findQuestionLocation(formObject, 'does_not_exist')).toBeNull();
    });

    it('handles a question without External_Reference__c', () => {
        const fo = {
            pages: [
                {
                    sections: [
                        { questions: [{ Id: 'no-ref' }] }
                    ]
                }
            ]
        };
        expect(findQuestionLocation(fo, 'anything')).toBeNull();
    });

    it('short-circuits on the first match for duplicate refs', () => {
        // Same External_Reference bound twice (uncommon but legal).
        const fo = {
            pages: [
                {
                    sections: [{ questions: [{ Id: 'first', External_Reference__c: 'dup' }] }]
                },
                {
                    sections: [{ questions: [{ Id: 'second', External_Reference__c: 'dup' }] }]
                }
            ]
        };
        expect(findQuestionLocation(fo, 'dup')).toEqual({
            pageIndex: 0,
            questionId: 'first'
        });
    });
});
