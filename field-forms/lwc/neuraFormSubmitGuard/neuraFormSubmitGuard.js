import { LightningElement, api } from 'lwc';

/**
 * Pillar 5 submit guard — the review-screen primitive that gates form
 * submission on blocking findings. Renders the aggregate score, the
 * finding breakdown by severity, and a submit button whose state mirrors
 * the server's submit policy:
 *
 *   - At least one blocking finding open  → submit disabled with reason
 *   - All blockers resolved (possibly via exception override) → submit
 *     enabled, with an explanatory note about non-blocking findings
 *     persisting after submit
 *
 * The component dispatches a `submit` event when the user taps the
 * primary CTA (parent owns the actual save). A `viewfindings` event
 * fires when the user taps "View findings" so the parent can open the
 * findings panel pre-expanded.
 *
 * Scoring math is delegated to c-neura-form-score-badge so the same
 * threshold logic powers the header and the submit guard.
 *
 * See docs/phase-2-pillar-5-scoring-findings.md "Submit guard — review
 * screen".
 */

const SEVERITY_BUCKETS = ['Critical', 'High', 'Medium', 'Low'];
const OPEN_STATUSES = new Set(['Open', 'In Progress']);

export default class NeuraFormSubmitGuard extends LightningElement {
    @api score;
    @api maxScore;
    @api threshold;

    /** Form_Finding__c-shaped records. Used for the breakdown count;
     *  the parent decides which findings to pass (all vs. current
     *  Linked_Form). */
    @api findings;

    /** Override hook for parents that compute submittability with
     *  server-side rules the LWC can't see (e.g. signature missing,
     *  required attachment missing). When false, the button is forced
     *  off even if no blocking findings exist. */
    @api forceDisabled;

    /** Custom message shown beneath the disabled button. Falls back to
     *  the blocking-findings reason when not provided. */
    @api disabledReason;

    get openFindings() {
        const list = Array.isArray(this.findings) ? this.findings : [];
        return list.filter((f) => OPEN_STATUSES.has(f.Status__c));
    }

    get blockingFindings() {
        return this.openFindings.filter((f) => f.Blocks_Submission__c === true);
    }

    get blockingCount() {
        return this.blockingFindings.length;
    }

    get openCount() {
        return this.openFindings.length;
    }

    get hasFindings() {
        return this.openCount > 0;
    }

    /** Severity breakdown rows for the open-findings list. */
    get severityRows() {
        const counts = SEVERITY_BUCKETS.reduce((acc, key) => {
            acc[key] = 0;
            return acc;
        }, {});
        for (const f of this.openFindings) {
            const sev = f.Severity__c || 'Medium';
            counts[sev] = (counts[sev] ?? 0) + 1;
        }
        return SEVERITY_BUCKETS.filter((key) => counts[key] > 0).map((key) => {
            const c = counts[key];
            const isCritical = key === 'Critical';
            return {
                key,
                label: key,
                count: c,
                icon: isCritical ? 'utility:warning' : 'utility:info',
                iconVariant: isCritical
                    ? 'error'
                    : key === 'High'
                    ? 'warning'
                    : 'inverse',
                blocksLabel:
                    isCritical && this.blockingCount > 0 ? ' (blocks)' : ''
            };
        });
    }

    get isSubmitDisabled() {
        return this.forceDisabled === true || this.blockingCount > 0;
    }

    get computedDisabledReason() {
        if (this.disabledReason) return this.disabledReason;
        if (this.blockingCount > 0) {
            const n = this.blockingCount;
            const word = n === 1 ? 'finding' : 'findings';
            return `Resolve ${n} blocking ${word} first.`;
        }
        return '';
    }

    /** Note shown when submit is enabled but open non-blocking findings
     *  remain — the wireframe explicitly calls this out as "open findings
     *  stay open after submit" so techs don't misread submit as resolution. */
    get nonBlockingNote() {
        if (this.isSubmitDisabled) return '';
        if (this.openCount === 0) return '';
        const word = this.openCount === 1 ? 'finding' : 'findings';
        return `Form will submit with ${this.openCount} open ${word}. These remain visible to reviewers.`;
    }

    handleSubmit() {
        if (this.isSubmitDisabled) return;
        this.dispatchEvent(
            new CustomEvent('submit', { bubbles: true, composed: true })
        );
    }

    handleViewFindings() {
        this.dispatchEvent(
            new CustomEvent('viewfindings', { bubbles: true, composed: true })
        );
    }

    handleSaveDraft() {
        this.dispatchEvent(
            new CustomEvent('savedraft', { bubbles: true, composed: true })
        );
    }
}
