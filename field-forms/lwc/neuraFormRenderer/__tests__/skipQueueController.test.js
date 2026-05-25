import {
    toggleSkipped,
    formatSkippedBadgeLabel,
    formatBlockedSubmitMessage
} from '../skipQueueController';

describe('skipQueueController.toggleSkipped', () => {
    it('adds the id when not present', () => {
        expect(toggleSkipped(['a', 'b'], 'c')).toEqual(['a', 'b', 'c']);
    });

    it('removes the id when present', () => {
        expect(toggleSkipped(['a', 'b', 'c'], 'b')).toEqual(['a', 'c']);
    });

    it('returns a new array reference (LWC reactivity needs it)', () => {
        const before = ['a', 'b'];
        const after = toggleSkipped(before, 'c');
        expect(after).not.toBe(before);
    });

    it('is a no-op when questionId is falsy', () => {
        const before = ['a'];
        expect(toggleSkipped(before, '')).toBe(before);
        expect(toggleSkipped(before, null)).toBe(before);
        expect(toggleSkipped(before, undefined)).toBe(before);
    });

    it('handles a non-array input defensively', () => {
        expect(toggleSkipped(null, 'a')).toEqual(['a']);
        expect(toggleSkipped(undefined, 'a')).toEqual(['a']);
    });
});

describe('skipQueueController.formatSkippedBadgeLabel', () => {
    it('uses singular wording for one', () => {
        expect(formatSkippedBadgeLabel(1)).toBe('1 to revisit');
    });
    it('uses plural wording for zero or many', () => {
        expect(formatSkippedBadgeLabel(0)).toBe('0 to revisit');
        expect(formatSkippedBadgeLabel(3)).toBe('3 to revisit');
    });
    it('coerces non-numeric input', () => {
        expect(formatSkippedBadgeLabel('5')).toBe('5 to revisit');
        expect(formatSkippedBadgeLabel(null)).toBe('0 to revisit');
        expect(formatSkippedBadgeLabel(undefined)).toBe('0 to revisit');
    });
});

describe('skipQueueController.formatBlockedSubmitMessage', () => {
    it('uses singular "field" for one', () => {
        expect(formatBlockedSubmitMessage(1)).toBe(
            'You still have 1 field flagged to revisit. Clear them before submitting.'
        );
    });
    it('uses plural "fields" for zero or many', () => {
        expect(formatBlockedSubmitMessage(0)).toBe(
            'You still have 0 fields flagged to revisit. Clear them before submitting.'
        );
        expect(formatBlockedSubmitMessage(7)).toBe(
            'You still have 7 fields flagged to revisit. Clear them before submitting.'
        );
    });
});
