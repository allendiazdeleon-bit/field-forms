/**
 * Swipe-between-pages gesture controller.
 *
 * Extracted from neuraFormRenderer in wave 28 to reduce that class's
 * ~1500-line surface and make the gesture logic independently testable.
 *
 * Returns { onTouchStart, onTouchEnd } handlers that the renderer wires
 * into the page-wrapper div's touch events. When a swipe matches the
 * thresholds, calls onNavigate('previous' | 'next').
 *
 * Why not a mixin:
 *   The swipe logic has no read-coupling to the host class. A pure
 *   factory with explicit dependencies (the navigate callback) makes
 *   the contract obvious and the unit tests trivial.
 *
 * Gesture contract — only fires on real swipes:
 *   - >= 60px horizontal travel (HORIZONTAL_PX)
 *   - <= 30px vertical drift (MAX_VERT_PX)
 *   - horizontal:vertical ratio >= 2:1 (mostly horizontal)
 *   - <= 500ms duration (a real flick, not a slow pan)
 *   - touch did NOT start on an interactive element (signature canvas,
 *     form input, button, scrollable list) — those keep their native
 *     touch behavior so the user never loses control of fine gestures
 */

const DEFAULTS = {
    horizontalPx: 60,
    maxVertPx: 30,
    maxDurationMs: 500
};

// Elements whose own touch behavior must win over swipe navigation.
const INTERACTIVE_TARGET_SELECTOR = [
    'canvas',
    'input',
    'textarea',
    'select',
    'button',
    'lightning-input',
    'lightning-textarea',
    'lightning-combobox',
    'lightning-input-rich-text',
    'lightning-radio-group',
    'lightning-checkbox-group',
    'lightning-file-upload',
    'lightning-button',
    '[contenteditable="true"]'
].join(', ');

/**
 * @param {object} opts
 * @param {(direction: 'previous'|'next') => void} opts.onNavigate
 *    Called when the touchend matches a valid swipe.
 * @param {Partial<typeof DEFAULTS>} [opts.thresholds]
 *    Override individual thresholds; missing keys fall back to defaults.
 * @returns {{ onTouchStart: (e:TouchEvent)=>void, onTouchEnd: (e:TouchEvent)=>void }}
 */
export function createSwipeController({ onNavigate, thresholds = {} } = {}) {
    const horizontalPx = thresholds.horizontalPx ?? DEFAULTS.horizontalPx;
    const maxVertPx = thresholds.maxVertPx ?? DEFAULTS.maxVertPx;
    const maxDurationMs = thresholds.maxDurationMs ?? DEFAULTS.maxDurationMs;

    // Closure state — captured per controller instance so multiple
    // simultaneous instances (unlikely but possible during test) don't
    // share gesture state.
    let startX = 0;
    let startY = 0;
    let startTime = 0;
    let bailed = false;

    function onTouchStart(event) {
        const touch = event && event.touches && event.touches[0];
        if (!touch) return;
        startX = touch.clientX;
        startY = touch.clientY;
        startTime = Date.now();
        const target = event.target;
        bailed = !!(
            target &&
            typeof target.closest === 'function' &&
            target.closest(INTERACTIVE_TARGET_SELECTOR)
        );
    }

    function onTouchEnd(event) {
        if (bailed) {
            bailed = false;
            return;
        }
        const touch = event && event.changedTouches && event.changedTouches[0];
        if (!touch) return;
        const dx = touch.clientX - startX;
        const dy = touch.clientY - startY;
        const dt = Date.now() - startTime;
        const absX = Math.abs(dx);
        const absY = Math.abs(dy);
        if (absX < horizontalPx) return;
        if (absY > maxVertPx) return;
        if (absX < 2 * absY) return;
        if (dt > maxDurationMs) return;
        // Right-swipe goes BACK (previous page); left-swipe goes FORWARD.
        const direction = dx > 0 ? 'previous' : 'next';
        if (typeof onNavigate === 'function') onNavigate(direction);
    }

    return { onTouchStart, onTouchEnd };
}
