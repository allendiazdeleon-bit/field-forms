import { createAutoSaveController } from '../autoSaveController';

/**
 * Auto-save controller tests — exercises the state machine extracted
 * from neuraFormRenderer in wave 28.
 *
 * State transitions verified:
 *   - schedule()                -> emits 'pending'
 *   - debounce elapses (clean)  -> emits 'idle'
 *   - debounce elapses (dirty)  -> emits 'saving' then 'saved'
 *   - save throws               -> emits 'error'
 *
 * Each state emission must also produce a draftState payload that the
 * mobile shell's draft-queue badge expects.
 */

beforeEach(() => {
    jest.useFakeTimers();
});

afterEach(() => {
    jest.useRealTimers();
});

function makeMap(entries = []) {
    return new Map(entries);
}

describe('createAutoSaveController', () => {
    it('emits "pending" state immediately on schedule()', () => {
        const onStateChange = jest.fn();
        const ctrl = createAutoSaveController({
            getDirtyAnswers: () => makeMap([['q1', { uploadCompleted: false }]]),
            getLinkedFormId: () => 'lf-1',
            getFormFactor: () => 'Small',
            save: jest.fn().mockResolvedValue(undefined),
            onStateChange,
            debounceMs: 100
        });
        ctrl.schedule();
        expect(onStateChange).toHaveBeenCalledWith(
            expect.objectContaining({
                status: 'pending',
                label: 'Unsaved changes',
                draftState: expect.objectContaining({
                    pendingCount: 1,
                    hasError: false
                })
            })
        );
    });

    it('returns to "idle" if no answers are dirty when debounce elapses', async () => {
        const onStateChange = jest.fn();
        const save = jest.fn();
        const ctrl = createAutoSaveController({
            getDirtyAnswers: () => makeMap([['q1', { uploadCompleted: true }]]),
            getLinkedFormId: () => 'lf-1',
            getFormFactor: () => 'Small',
            save,
            onStateChange,
            debounceMs: 100
        });
        ctrl.schedule();
        jest.advanceTimersByTime(100);
        // Let any chained promises resolve.
        await Promise.resolve();
        expect(save).not.toHaveBeenCalled();
        // Last state emitted should be idle (status flipped from pending).
        const lastCall = onStateChange.mock.calls[onStateChange.mock.calls.length - 1][0];
        expect(lastCall.status).toBe('idle');
        expect(lastCall.draftState.pendingCount).toBe(0);
    });

    it('transitions pending -> saving -> saved with a save invocation', async () => {
        const onStateChange = jest.fn();
        const save = jest.fn().mockResolvedValue(undefined);
        const ctrl = createAutoSaveController({
            getDirtyAnswers: () => makeMap([['q1', { uploadCompleted: false }]]),
            getLinkedFormId: () => 'lf-1',
            getFormFactor: () => 'Small',
            save,
            onStateChange,
            debounceMs: 100
        });
        ctrl.schedule();
        jest.advanceTimersByTime(100);
        await Promise.resolve();
        await Promise.resolve(); // second tick for the catch
        const statuses = onStateChange.mock.calls.map((c) => c[0].status);
        expect(statuses).toEqual(expect.arrayContaining(['pending', 'saving', 'saved']));
        expect(save).toHaveBeenCalledWith(
            expect.any(Map),
            'lf-1',
            'Small'
        );
        // lastSavedAt should now be an ISO string.
        const lastCall = onStateChange.mock.calls[onStateChange.mock.calls.length - 1][0];
        expect(lastCall.lastSavedAt).toEqual(expect.any(String));
        expect(lastCall.label).toMatch(/^Saved /);
    });

    it('transitions to "error" when the save function rejects', async () => {
        const onStateChange = jest.fn();
        const save = jest.fn().mockRejectedValue(new Error('boom'));
        const ctrl = createAutoSaveController({
            getDirtyAnswers: () => makeMap([['q1', { uploadCompleted: false }]]),
            getLinkedFormId: () => 'lf-1',
            getFormFactor: () => 'Small',
            save,
            onStateChange,
            debounceMs: 100
        });
        ctrl.schedule();
        jest.advanceTimersByTime(100);
        await Promise.resolve();
        await Promise.resolve();
        const lastCall = onStateChange.mock.calls[onStateChange.mock.calls.length - 1][0];
        expect(lastCall.status).toBe('error');
        expect(lastCall.label).toMatch(/Save failed/);
        expect(lastCall.draftState.hasError).toBe(true);
    });

    it('debounces consecutive schedule() calls into a single save', async () => {
        const onStateChange = jest.fn();
        const save = jest.fn().mockResolvedValue(undefined);
        const ctrl = createAutoSaveController({
            getDirtyAnswers: () => makeMap([['q1', { uploadCompleted: false }]]),
            getLinkedFormId: () => 'lf-1',
            getFormFactor: () => 'Small',
            save,
            onStateChange,
            debounceMs: 100
        });
        ctrl.schedule();
        jest.advanceTimersByTime(50);
        ctrl.schedule();
        jest.advanceTimersByTime(50);
        ctrl.schedule();
        jest.advanceTimersByTime(100);
        await Promise.resolve();
        await Promise.resolve();
        expect(save).toHaveBeenCalledTimes(1);
    });

    it('handles a missing answer map without crashing', async () => {
        const onStateChange = jest.fn();
        const save = jest.fn();
        const ctrl = createAutoSaveController({
            getDirtyAnswers: () => null,
            getLinkedFormId: () => 'lf-1',
            getFormFactor: () => 'Small',
            save,
            onStateChange,
            debounceMs: 100
        });
        ctrl.schedule();
        jest.advanceTimersByTime(100);
        await Promise.resolve();
        expect(save).not.toHaveBeenCalled();
        const lastCall = onStateChange.mock.calls[onStateChange.mock.calls.length - 1][0];
        expect(lastCall.status).toBe('idle');
    });
});
