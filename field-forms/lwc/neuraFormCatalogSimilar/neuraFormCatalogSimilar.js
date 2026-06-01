import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import findSimilar from '@salesforce/apex/neuraFormBuilderController.findSimilarCatalogEntries';

/**
 * Surfaces "did you mean..." suggestions for catalog entries whose
 * content matches the typed question text. Mounted by
 * neuraFormBuilderAttributes inside the exclusive-editable input
 * mode — i.e. when admin is shaping a brand-new question (only this
 * binding uses the catalog entry).
 *
 * Wired imperatively, not via @wire, because we want explicit control
 * over the debounce window. SOSL is cheap but the parent's lightning-
 * input-field already coalesces keystrokes into onchange events, so
 * one extra-light debounce here is enough to avoid spamming as the
 * admin walks the keyboard.
 *
 * Each result exposes two actions:
 *   - "Open" → navigates to the catalog record (inspect before
 *      adopting).
 *   - "Use this" → fires a `useentry` event that the parent handles
 *      by re-pointing the binding's Form_Question_Catalog__c to the
 *      chosen entry (Wave 35.9b).
 *
 * Filter rules applied client-side after the SOSL round-trip:
 *   - Scope filter is applied server-side via the templateScope
 *     parameter on findSimilarCatalogEntries.
 *   - The binding's currently-linked catalog Id (currentCatalogId)
 *     is suppressed — no point suggesting "adopt yourself".
 *   - Any match whose questionText is byte-identical (case-
 *     insensitive, trimmed) to the typed text is suppressed — the
 *     adoption would be a no-op for the user.
 *
 * See docs/phase-2-pillar-2-question-catalog.md "Operating at scale".
 */
const DEBOUNCE_MS = 350;
const SEARCH_LIMIT = 5;
const MIN_QUERY_CHARS = 3;

export default class NeuraFormCatalogSimilar extends NavigationMixin(LightningElement) {
    _text;
    matches = [];
    isLoading = false;
    error;
    _timer;

    @api formTemplateId;
    @api currentCatalogId;

    @api
    get questionText() {
        return this._text;
    }
    set questionText(val) {
        this._text = val;
        this.scheduleSearch();
    }

    disconnectedCallback() {
        clearTimeout(this._timer);
    }

    scheduleSearch() {
        clearTimeout(this._timer);
        const text = (this._text || '').trim();
        if (text.length < MIN_QUERY_CHARS) {
            this.matches = [];
            this.error = null;
            return;
        }
        this._timer = setTimeout(() => this.runSearch(text), DEBOUNCE_MS);
    }

    async runSearch(text) {
        this.isLoading = true;
        try {
            const result = await findSimilar({
                text,
                limitN: SEARCH_LIMIT,
                formTemplateId: this.formTemplateId
            });
            this.matches = this.applyClientFilters(result || [], text);
            this.error = null;
        } catch (e) {
            // Surface the message but don't blow up the builder.
            this.error = (e && e.body && e.body.message) || 'Catalog search failed';
            this.matches = [];
            // eslint-disable-next-line no-console
            console.error('catalog similarity search', e);
        } finally {
            this.isLoading = false;
        }
    }

    applyClientFilters(rows, text) {
        const typed = (text || '').trim().toLowerCase();
        return rows.filter((m) => {
            if (this.currentCatalogId && m.id === this.currentCatalogId) return false;
            const candidate = (m.questionText || '').trim().toLowerCase();
            if (candidate && candidate === typed) return false;
            return true;
        });
    }

    get hasMatches() {
        return this.matches && this.matches.length > 0;
    }

    get hasError() {
        return Boolean(this.error);
    }

    get countLabel() {
        const n = this.matches.length;
        return n === 1
            ? '1 similar question already in the catalog'
            : `${n} similar questions already in the catalog`;
    }

    /**
     * Decorate raw Apex results for the template. Adds a usageLabel so
     * we don't string-build pluralization in the markup, and keeps the
     * Id as data-id for the click handler.
     */
    get decoratedMatches() {
        return this.matches.map((m) => ({
            ...m,
            usageLabel:
                m.usageCount === 1
                    ? '1 template'
                    : `${m.usageCount || 0} templates`
        }));
    }

    handleOpenMatch(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: id,
                objectApiName: 'Form_Question_Catalog__c',
                actionName: 'view'
            }
        });
    }

    handleUseMatch(event) {
        const id = event.currentTarget.dataset.id;
        if (!id) return;
        const match = this.matches.find((m) => m.id === id);
        if (!match) return;
        this.dispatchEvent(
            new CustomEvent('useentry', {
                detail: {
                    catalogId: match.id,
                    type: match.type,
                    questionText: match.questionText
                }
            })
        );
    }
}
