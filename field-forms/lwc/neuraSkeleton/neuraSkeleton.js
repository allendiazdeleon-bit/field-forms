import { LightningElement, api } from 'lwc';

/**
 * Loading skeleton placeholder. Use INSTEAD of a full-page spinner for
 * surfaces that take longer than ~200ms to render — gives users a
 * sense of structure while data loads (improves perceived performance).
 *
 * Variants:
 *   - 'list'  → repeated row stubs (default count 3). Good for the form selector.
 *   - 'card'  → single block with title + body lines. Good for review cards.
 *   - 'text'  → 1-3 short text lines. Good for inline summaries.
 *
 * Pure CSS animation, no JS heartbeat — cheap on FSL Mobile WebViews.
 */
export default class NeuraSkeleton extends LightningElement {
    @api variant = 'list';
    @api count = 3;

    get isList() { return this.variant === 'list'; }
    get isCard() { return this.variant === 'card'; }
    get isText() { return this.variant === 'text'; }

    get rows() {
        const n = Math.max(1, Math.min(10, Number(this.count) || 3));
        return Array.from({ length: n }, (_, i) => ({ key: `s${i}` }));
    }
}
