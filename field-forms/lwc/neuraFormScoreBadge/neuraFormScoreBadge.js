import { LightningElement, api } from 'lwc';

/**
 * Compact, accessible score badge — the visual primitive for Pillar 5's
 * "score + pass/fail at a glance" surface. Mounts inside the form
 * header (page-level rollup), section headers (when the renderer wires
 * per-section scoring), and any future summary screens.
 *
 * Three render states, each carrying a redundant signal so the badge
 * is usable to color-blind users and prints legibly:
 *
 *   passed        ✓ + green + filled bar      score >= threshold
 *   failed        ✗ + red   + filled bar      score < threshold
 *   evaluating    · + neutral + empty bar     no answers yet OR
 *                                             threshold not configured
 *
 * The renderer passes raw values; this component handles the math and
 * the formatting. Returns "0/0" gracefully when both are null (form
 * just opened, no answers yet).
 *
 * See docs/phase-2-pillar-5-scoring-findings.md "UX wireframes —
 * Section header — accessible score badge".
 */
export default class NeuraFormScoreBadge extends LightningElement {
    /** Current score; usually Linked_Form__c.Score__c or Form_Section__c
     *  rollup. Null / undefined treated as 0. */
    @api score;

    /** Maximum possible score (sum of catalog Weight__c for active
     *  questions in the scope). Null / undefined / 0 treated as
     *  "not evaluable" — the badge renders the neutral state. */
    @api maxScore;

    /** Optional pass threshold as a percent (0-100). If omitted, the
     *  badge cannot mark pass/fail and stays in the neutral state. */
    @api threshold;

    /** Optional label shown to the left of the numerical score
     *  (e.g. "Pest Prevention"). Omit for a compact badge. */
    @api label;

    get scoreNum() {
        const n = Number(this.score);
        return Number.isFinite(n) ? n : 0;
    }

    get maxScoreNum() {
        const n = Number(this.maxScore);
        return Number.isFinite(n) && n > 0 ? n : 0;
    }

    get thresholdNum() {
        const n = Number(this.threshold);
        return Number.isFinite(n) ? n : null;
    }

    /** Percent of max achieved, 0-100. 0 when max is zero/missing. */
    get percent() {
        if (this.maxScoreNum === 0) return 0;
        const raw = (this.scoreNum / this.maxScoreNum) * 100;
        return Math.max(0, Math.min(100, Math.round(raw)));
    }

    /** "passed" | "failed" | "neutral" — drives icon, color, bar style. */
    get state() {
        if (this.maxScoreNum === 0) return 'neutral';
        if (this.thresholdNum === null) return 'neutral';
        return this.percent >= this.thresholdNum ? 'passed' : 'failed';
    }

    get iconName() {
        if (this.state === 'passed') return 'utility:check';
        if (this.state === 'failed') return 'utility:close';
        return 'utility:dash';
    }

    get iconVariant() {
        // Lightning icon variants. The icon CARRIES the signal —
        // color is supplemental (accessibility).
        if (this.state === 'passed') return 'success';
        if (this.state === 'failed') return 'error';
        return 'inverse';
    }

    get badgeClass() {
        // Drives the bar's fill color via CSS class binding.
        return `score-badge score-badge--${this.state}`;
    }

    renderedCallback() {
        // LWC's template compiler rejects dynamic `style={...}` bindings, so
        // the bar-fill width is set imperatively. lwc:ref keeps the lookup
        // cheap and avoids querySelector traversal cost on each rerender.
        const fill = this.refs && this.refs.fill;
        if (fill) {
            fill.style.width = `${this.percent}%`;
        }
    }

    get scoreLabel() {
        // Display "X / Y" with no trailing zeros on decimals.
        // Use Math.round when fractional Weight__c is in play but the
        // raw values are integers in the common case.
        const s = formatNumber(this.scoreNum);
        const m = formatNumber(this.maxScoreNum);
        return `${s} / ${m}`;
    }

    get percentLabel() {
        return `${this.percent}%`;
    }

    /** Used for the alternative-text on the icon — screen readers
     *  hear the state, not just the visual cue. */
    get stateLabel() {
        if (this.state === 'passed') return 'Pass';
        if (this.state === 'failed') return 'Fail';
        return 'Not evaluated';
    }

    get hasLabel() {
        return Boolean(this.label && String(this.label).trim().length > 0);
    }
}

function formatNumber(n) {
    if (!Number.isFinite(n)) return '0';
    return Number.isInteger(n) ? String(n) : n.toFixed(1).replace(/\.0$/, '');
}
