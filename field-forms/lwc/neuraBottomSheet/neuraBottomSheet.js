import { LightningElement, api } from 'lwc';

/**
 * Bottom-sheet modal — the FSL-Mobile-native alternative to a centered
 * dialog. Renders a scrim + a sheet that slides up from the bottom edge.
 *
 * Why this exists:
 *   On phone-sized WebViews, centered modals collide with the soft keyboard
 *   and feel out of place. A bottom sheet (a) anchors to the thumb zone,
 *   (b) leaves the host record visible above the scrim for context, and
 *   (c) supports drag-to-dismiss which is the gesture mobile users already
 *   expect from native iOS/Android sheets.
 *
 * Pure CSS animations + Nimbus-friendly markup — safe to use offline.
 *
 * Public API:
 *   @api open             controlled open/closed state
 *   @api heading          optional title displayed in the sheet header
 *   @api size             'auto' | 'half' | 'full' (default 'auto')
 *   @api nonDismissible   set true to BLOCK scrim-tap / drag / escape closing
 *                         (LWC1099 requires booleans to default to false, so
 *                         the property is phrased in the negative — default
 *                         behavior is dismissible)
 *   @api hideCloseButton  suppress the X button in the header (default false)
 *   @api hideHandle       suppress the drag handle pill (default false)
 *
 * Slots:
 *   default              body content
 *   footer               sticky CTAs / action row
 *
 * Events:
 *   close                fired with detail { reason } where reason is
 *                        'scrim' | 'close-button' | 'drag' | 'escape'
 *
 * Typical usage:
 *   <c-neura-bottom-sheet
 *       open={signatureOpen}
 *       heading="Capture signature"
 *       size="half"
 *       onclose={handleSignatureClose}>
 *       <c-neura-form-answer-input-signature ...></c-neura-form-answer-input-signature>
 *       <div slot="footer">
 *           <lightning-button label="Save" variant="brand" onclick={handleSave}></lightning-button>
 *       </div>
 *   </c-neura-bottom-sheet>
 */
const SIZE_CLASS = {
    auto: 'sheet sheet_auto',
    half: 'sheet sheet_half',
    full: 'sheet sheet_full'
};

const DISMISS_DRAG_THRESHOLD_PX = 80;

export default class NeuraBottomSheet extends LightningElement {
    @api open = false;
    @api heading;
    @api size = 'auto';
    @api nonDismissible = false;
    @api hideCloseButton = false;
    @api hideHandle = false;

    _dragStartY = null;
    _dragDeltaY = 0;
    _isDragging = false;

    // Inverted convenience getter so internal logic reads naturally.
    get _dismissible() { return !this.nonDismissible; }

    get scrimClass() {
        return this.open ? 'scrim scrim_open' : 'scrim';
    }

    get sheetClass() {
        const base = SIZE_CLASS[this.size] || SIZE_CLASS.auto;
        return `${base} ${this.open ? 'sheet_open' : ''}`.trim();
    }

    get titleId() {
        // Stable id so aria-labelledby resolves even when heading is set later.
        return 'neura-bottom-sheet-title';
    }

    handleScrimClick() {
        if (this._dismissible) this._dispatchClose('scrim');
    }

    handleCloseClick() {
        this._dispatchClose('close-button');
    }

    handleSheetClick(event) {
        // Don't let inner clicks reach the scrim — scrim has the dismiss
        // handler and the sheet is overlapping it visually.
        event.stopPropagation();
    }

    handleHandleTouchStart(event) {
        if (!this._dismissible) return;
        const touch = event.touches && event.touches[0];
        if (!touch) return;
        this._dragStartY = touch.clientY;
        this._isDragging = true;
    }

    handleHandleTouchMove(event) {
        if (!this._isDragging) return;
        const touch = event.touches && event.touches[0];
        if (!touch) return;
        const dy = touch.clientY - this._dragStartY;
        // Only allow downward drag; ignore upward pulls so the sheet
        // doesn't get yanked above its open position.
        if (dy > 0) {
            this._dragDeltaY = dy;
            const sheet = this.refs && this.refs.sheet;
            if (sheet) {
                sheet.style.transform = `translateY(${dy}px)`;
                sheet.style.transition = 'none';
            }
        }
    }

    handleHandleTouchEnd() {
        if (!this._isDragging) return;
        this._isDragging = false;
        const sheet = this.refs && this.refs.sheet;
        if (sheet) {
            sheet.style.transform = '';
            sheet.style.transition = '';
        }
        if (this._dragDeltaY > DISMISS_DRAG_THRESHOLD_PX) {
            this._dispatchClose('drag');
        }
        this._dragDeltaY = 0;
    }

    handleKeydown(event) {
        if (event.key === 'Escape' && this._dismissible) {
            this._dispatchClose('escape');
        }
    }

    renderedCallback() {
        if (!this.open) return;
        // Move focus to the sheet on open so screen readers + keyboard
        // users land inside the modal context. Skip if the user has
        // already focused something inside.
        const sheet = this.refs && this.refs.sheet;
        if (sheet && !sheet.contains(document.activeElement)) {
            // tabindex=-1 set in template makes the wrapper focusable
            sheet.focus({ preventScroll: true });
        }
    }

    _dispatchClose(reason) {
        this.dispatchEvent(new CustomEvent('close', { detail: { reason } }));
    }
}
