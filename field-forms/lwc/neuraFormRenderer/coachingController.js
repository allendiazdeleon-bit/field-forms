/**
 * Coaching controller — manages the real-time coaching pipeline
 * (Vignette 3) the same way autoSaveController manages saves.
 *
 * Why this is a module and not inline renderer code:
 *   1. The fetch is a live LLM round trip (2-5s). Firing it straight from
 *      handleAnswerChange meant one Apex -> Models API callout per
 *      keystroke, with whichever response resolved last winning. The
 *      debounce + monotonic request token here make the pipeline
 *      single-flight and last-request-wins.
 *   2. Same testability story as autoSaveController: dependencies are
 *      injected, the controller never reads `this`, so fake-time tests
 *      can drive the debounce/token logic without an LWC environment.
 *
 * Availability: there is no supported online/offline signal on FSL Mobile
 * (and formFactor is always 'Small' there, so it can't distinguish an
 * online phone from the offline runtime). Instead of gating up front, the
 * first hard failure trips a circuit breaker that disables coaching for
 * the rest of the session — offline runtimes fail once and go quiet,
 * online phones get coaching.
 *
 * Public API:
 *   schedule(questionId, answerValue)  Call on every answer change.
 */

const DEFAULT_DEBOUNCE_MS = 1500;

// Server contract: NeuraFormCoachingController.CoachingResult.suggestedAction
// is 'photo' | 'review' | null. Unknown/absent actions render no CTA rather
// than a misleading default.
const ACTION_LABELS = {
    photo: 'Take a closer photo',
    review: 'Review prior findings'
};

/**
 * @param {object} opts
 * @param {(params: {linkedFormId: string, questionId: string, currentAnswer: string}) => Promise<object>} opts.fetchCoaching
 *    Imperative Apex call returning a CoachingResult.
 * @param {() => string} opts.getLinkedFormId
 * @param {(card: {message: string, actionLabel: string|null, questionId: string}) => void} opts.onCoaching
 *    Fires when a nudge should be shown. The renderer mirrors it into a
 *    @track field for the template.
 * @param {number} [opts.debounceMs=1500]
 */
export function createCoachingController({
    fetchCoaching,
    getLinkedFormId,
    onCoaching,
    debounceMs = DEFAULT_DEBOUNCE_MS
} = {}) {
    let timer = null;
    let requestToken = 0;
    let disabled = false;
    let pending = null;
    const coachedQuestionIds = new Set();

    function schedule(questionId, answerValue) {
        if (disabled || !questionId || !answerValue) return;
        // One nudge per question per session — re-edits don't re-nudge.
        // Marked at schedule time (not on success) so the in-flight window
        // can't queue duplicates for the same question.
        if (coachedQuestionIds.has(questionId)) return;
        pending = { questionId, answerValue };
        if (timer) clearTimeout(timer);
        timer = setTimeout(() => { run(); }, debounceMs);
    }

    async function run() {
        const req = pending;
        pending = null;
        if (!req || disabled) return;
        const token = ++requestToken;
        try {
            const result = await fetchCoaching({
                linkedFormId: getLinkedFormId(),
                questionId: req.questionId,
                currentAnswer: req.answerValue
            });
            // A newer request superseded this one while it was in flight —
            // its answer text is stale; drop it.
            if (token !== requestToken || disabled) return;
            if (result && result.hasCoaching && result.message) {
                coachedQuestionIds.add(req.questionId);
                onCoaching({
                    message: result.message,
                    actionLabel: ACTION_LABELS[result.suggestedAction] || null,
                    questionId: req.questionId
                });
            }
        } catch (e) {
            // Circuit breaker: offline runtime / AI disabled / no perms all
            // land here. Coaching is best-effort chrome — fail once, go
            // quiet for the session, never break the inspection flow.
            disabled = true;
        }
    }

    return { schedule };
}
