/**
 * Auto-save controller — manages the debounced save-on-change pipeline.
 *
 * Extracted from neuraFormRenderer in wave 28. Two reasons it became
 * its own module:
 *   1. State machine: pending -> saving -> saved | error. The transitions
 *      and the debounce are easier to reason about in isolation.
 *   2. Independent testability: with the save function injected, unit
 *      tests can fake-time the debounce and verify the right state
 *      transitions fire without standing up a full LWC + LDS environment.
 *
 * Coupling shape:
 *   - The controller does NOT own the reactive @track state — that lives
 *     on the renderer so the template renders reactively. The controller
 *     emits state-change callbacks that the renderer mirrors into its
 *     own @track fields.
 *   - Dependencies are passed as named-parameter callbacks at
 *     construction time. The controller never reads `this`.
 *
 * Public API:
 *   schedule()  Call when any answer changes. Resets the debounce
 *               timer; once it elapses, runs the save pipeline.
 */

const DEFAULT_DEBOUNCE_MS = 1500;

function formatSavedLabel(date) {
    const hh = String(date.getHours() % 12 || 12);
    const mm = String(date.getMinutes()).padStart(2, '0');
    const ampm = date.getHours() >= 12 ? 'pm' : 'am';
    return `Saved ${hh}:${mm} ${ampm}`;
}

/**
 * @param {object} opts
 * @param {() => Map} opts.getDirtyAnswers
 *    Returns the questionAnswerMap. Each value should have an
 *    `uploadCompleted` boolean indicating whether the entry already
 *    landed in a prior save.
 * @param {() => string} opts.getLinkedFormId
 *    Returns the active Linked_Form__c Id (the parent record the
 *    Form_Answer rows belong to).
 * @param {() => string} opts.getFormFactor
 *    Returns the @salesforce/client/formFactor value. The save function
 *    uses this to route writes through Apex (desktop) vs uiRecordApi
 *    (everything else — see databaseLayer.js for the rationale).
 * @param {(answers: Map, linkedFormId: string, formFactor: string) => Promise<void>} opts.save
 *    Saves the dirty answers. Wrapped here so tests can substitute a
 *    spy without pulling in the full LDS pipeline.
 * @param {(state: { status: string, label: string, lastSavedAt: string|null, draftState: object }) => void} opts.onStateChange
 *    Fires every time the controller transitions between states. The
 *    renderer mirrors `status` and `label` into its @track fields for
 *    template binding, and dispatches `draftState` as the draftstate
 *    CustomEvent detail consumed by the mobile shell's draft-queue
 *    badge.
 * @param {number} [opts.debounceMs=1500]
 *    Override the debounce window. Lower values fire saves more
 *    aggressively; useful for tests.
 */
export function createAutoSaveController({
    getDirtyAnswers,
    getLinkedFormId,
    getFormFactor,
    save,
    onStateChange,
    debounceMs = DEFAULT_DEBOUNCE_MS
} = {}) {
    let timer = null;
    let lastSavedAt = null;

    function emit(status, label) {
        const isPending = status === 'pending' || status === 'saving';
        const state = {
            status,
            label,
            lastSavedAt,
            draftState: {
                pendingCount: isPending ? 1 : 0,
                hasError: status === 'error',
                lastSyncedAt: lastSavedAt
            }
        };
        if (typeof onStateChange === 'function') onStateChange(state);
    }

    function schedule() {
        emit('pending', 'Unsaved changes');
        if (timer) clearTimeout(timer);
        timer = setTimeout(() => { run(); }, debounceMs);
    }

    async function run() {
        const answers = getDirtyAnswers ? getDirtyAnswers() : null;
        if (!answers || typeof answers.values !== 'function') {
            // Defensive: if the renderer hasn't initialized the answer
            // map yet, just bail back to idle rather than crashing.
            emit('idle', '');
            return;
        }
        let hasDirty = false;
        for (const v of answers.values()) {
            if (!v || !v.uploadCompleted) { hasDirty = true; break; }
        }
        if (!hasDirty) {
            emit('idle', '');
            return;
        }

        emit('saving', 'Saving…');
        try {
            await save(answers, getLinkedFormId(), getFormFactor());
            lastSavedAt = new Date().toISOString();
            emit('saved', formatSavedLabel(new Date()));
        } catch (e) {
            emit('error', 'Save failed (will retry on Next)');
        }
    }

    return { schedule };
}
