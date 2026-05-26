import { LightningElement, api } from 'lwc';

/**
 * Pillar 5 findings panel. Renders a collapsed summary bar
 * ("⚠ N findings · M blocks") that expands into a list of severity-
 * sorted finding cards. Position-agnostic: the renderer chooses where
 * it sits (bottom sheet on mobile, side drawer on desktop) by styling
 * the host element. This component owns content + interaction only.
 *
 * Events emitted (bubble + composed so callers can listen from the
 * renderer or any ancestor):
 *
 *   findingclick   { findingId, externalReference }
 *     Tech tapped the finding header; renderer should scroll the
 *     source question into view.
 *
 *   addphoto       { findingId }
 *     Tech tapped "Add photo" on a photo-required finding.
 *
 *   markexception  { findingId }
 *     Tech tapped "Mark exception" — opens the exception modal.
 *
 *   panelexpand    {}
 *   panelcollapse  {}
 *     For the renderer to adjust surrounding layout (e.g. pad the
 *     scroll container so the expanded sheet doesn't cover content).
 *
 * See docs/phase-2-pillar-5-scoring-findings.md "Findings panel —
 * mobile bottom sheet".
 */

const SEVERITY_ORDER = { Critical: 0, High: 1, Medium: 2, Low: 3 };

/** Status values that mean the finding still needs tech attention. */
const OPEN_STATUSES = new Set(['Open', 'In Progress']);

export default class NeuraFormFindingsPanel extends LightningElement {
    /** Array of Form_Finding__c-shaped records. Caller pre-shapes them
     *  with denormalized sectionName / questionText for display so this
     *  component doesn't need to know about relationship names. */
    @api findings;

    /** Force-expanded — useful for the desktop drawer variant or for
     *  Storybook-style testing. When unset the panel manages its own
     *  expanded state via the handle tap. */
    @api forceExpanded;

    _expanded = false;

    get isExpanded() {
        return this.forceExpanded === true || this._expanded;
    }

    get openFindings() {
        const list = Array.isArray(this.findings) ? this.findings : [];
        return list
            .filter((f) => OPEN_STATUSES.has(f.Status__c))
            .slice()
            .sort((a, b) => {
                const sa = SEVERITY_ORDER[a.Severity__c] ?? 99;
                const sb = SEVERITY_ORDER[b.Severity__c] ?? 99;
                if (sa !== sb) return sa - sb;
                // Stable secondary sort by name so the order doesn't
                // flicker as findings come back from the server in
                // arbitrary order.
                return String(a.Name || a.Id || '').localeCompare(
                    String(b.Name || b.Id || '')
                );
            })
            .map((f) => ({
                ...f,
                rowKey: f.Id || f.Name,
                severityClass: `finding-card finding-card--${(
                    f.Severity__c || 'medium'
                ).toLowerCase()}`,
                severityLabel: (f.Severity__c || 'Medium').toUpperCase(),
                blocksLabel: f.Blocks_Submission__c ? ' · BLOCKS' : '',
                showAddPhoto:
                    f.Photo_Required__c === true && f.Photo_Attached__c !== true,
                photoSatisfied:
                    f.Photo_Required__c === true && f.Photo_Attached__c === true,
                hasNotes: Boolean(f.Notes__c && String(f.Notes__c).trim()),
                canMarkException:
                    f.Blocks_Submission__c === true && !f.Exception_Reason__c
            }));
    }

    get blockingCount() {
        return this.openFindings.filter((f) => f.Blocks_Submission__c === true)
            .length;
    }

    get openCount() {
        return this.openFindings.length;
    }

    get isEmpty() {
        return this.openCount === 0;
    }

    /** Summary line shown in the collapsed handle. */
    get summaryText() {
        if (this.isEmpty) return 'No findings · 0';
        if (this.blockingCount > 0) {
            const noun = this.blockingCount === 1 ? 'blocks' : 'block';
            return `${this.openCount} findings · ${this.blockingCount} ${noun}`;
        }
        return `${this.openCount} findings`;
    }

    get summaryIcon() {
        return this.isEmpty ? 'utility:check' : 'utility:warning';
    }

    get summaryIconVariant() {
        if (this.isEmpty) return 'success';
        return this.blockingCount > 0 ? 'error' : 'warning';
    }

    get rootClass() {
        const state = this.isExpanded ? 'expanded' : 'collapsed';
        const tone = this.isEmpty
            ? 'empty'
            : this.blockingCount > 0
            ? 'blocking'
            : 'open';
        return `findings-panel findings-panel--${state} findings-panel--${tone}`;
    }

    handleToggle() {
        // forceExpanded means the parent owns expanded state; ignore the tap.
        if (this.forceExpanded === true) return;
        this._expanded = !this._expanded;
        const evtName = this._expanded ? 'panelexpand' : 'panelcollapse';
        this.dispatchEvent(
            new CustomEvent(evtName, { bubbles: true, composed: true })
        );
    }

    handleFindingClick(event) {
        const id = event.currentTarget.dataset.findingId;
        const ref = event.currentTarget.dataset.externalReference || null;
        this.dispatchEvent(
            new CustomEvent('findingclick', {
                detail: { findingId: id, externalReference: ref },
                bubbles: true,
                composed: true
            })
        );
    }

    handleAddPhoto(event) {
        // stopPropagation so the card-level findingclick doesn't also fire.
        event.stopPropagation();
        const id = event.currentTarget.dataset.findingId;
        this.dispatchEvent(
            new CustomEvent('addphoto', {
                detail: { findingId: id },
                bubbles: true,
                composed: true
            })
        );
    }

    handleMarkException(event) {
        event.stopPropagation();
        const id = event.currentTarget.dataset.findingId;
        this.dispatchEvent(
            new CustomEvent('markexception', {
                detail: { findingId: id },
                bubbles: true,
                composed: true
            })
        );
    }
}
