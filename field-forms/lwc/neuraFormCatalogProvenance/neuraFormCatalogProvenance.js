import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';

/**
 * Reads catalog-provenance fields off a question binding and renders a
 * compact informational badge: "linked + inherited", "linked + overridden",
 * or "not linked" (mid-migration).
 *
 * Read surface today:
 *   - Badge primary text + icon + variant (visual state)
 *   - "Open catalog entry" button when linked — navigates to the catalog
 *     record so admins can edit content via the native Salesforce UI
 *
 * Not yet:
 *   - In-place "override in this template" / "revert to catalog default"
 *     buttons. Those require switching the parent's lightning-input-field
 *     binding between Question__c and Override_Question__c — meaningful
 *     refactor scheduled as its own wave.
 *
 * The host (neuraFormBuilderAttributes) passes the current selection. We
 * read attributes off it directly; no Apex roundtrip needed because
 * neuraFormBuilderController.getFormDetails already returns the binding's
 * Form_Question_Catalog__c / Override_Question__c / Override_Required__c
 * fields on the wire.
 */
export default class NeuraFormCatalogProvenance extends NavigationMixin(LightningElement) {
    @api selection;

    get attributes() {
        return this.selection && this.selection.attributes;
    }

    get hasCatalogLink() {
        return Boolean(this.attributes && this.attributes.Form_Question_Catalog__c);
    }

    get hasQuestionOverride() {
        return Boolean(this.attributes && this.attributes.Override_Question__c);
    }

    get hasRequiredOverride() {
        const v = this.attributes && this.attributes.Override_Required__c;
        return Boolean(v) && v !== 'Inherit';
    }

    get isOverridden() {
        return this.hasQuestionOverride || this.hasRequiredOverride;
    }

    get badgeIcon() {
        if (!this.hasCatalogLink) return 'utility:dash';
        return this.isOverridden ? 'utility:edit' : 'utility:link';
    }

    get badgeVariant() {
        // Lightning theme variants. "warning" for overrides (admin should
        // know they're diverging from catalog), default for inherited,
        // "inverse" for unlinked.
        if (!this.hasCatalogLink) return 'inverse';
        return this.isOverridden ? 'warning' : 'success';
    }

    get badgePrimaryText() {
        if (!this.hasCatalogLink) return 'Not linked to a catalog entry';
        return this.isOverridden
            ? 'Overridden in this template'
            : 'Inherited from catalog';
    }

    get badgeSecondaryText() {
        if (!this.hasCatalogLink) {
            return 'Add this question to the catalog to share it across templates.';
        }
        if (this.isOverridden) {
            const parts = [];
            if (this.hasQuestionOverride) parts.push('question text');
            if (this.hasRequiredOverride) parts.push('required');
            return 'Overrides: ' + parts.join(', ');
        }
        return 'Edits to the catalog entry will apply to every template using it.';
    }

    /**
     * Navigate to the linked catalog record's view page. Salesforce
     * native UI takes over from there for any editing the admin wants
     * to do. Wired only when the binding actually has a catalog ref —
     * the button is hidden in the unlinked state.
     */
    handleOpenCatalog() {
        if (!this.hasCatalogLink) return;
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.attributes.Form_Question_Catalog__c,
                objectApiName: 'Form_Question_Catalog__c',
                actionName: 'view'
            }
        });
    }

    /**
     * "Override in this template" — when inherited, this is the explicit
     * gesture admins use to start editing the question text per-template
     * instead of the catalog default. Parent picks up the event and
     * seeds Override_Question__c with the current resolved value so the
     * admin has a starting point to edit from (rather than an empty box).
     *
     * @api so unit tests can drive the handler directly. The
     * sfdx-lwc-jest lightning-button stub doesn't simulate click
     * events, so direct invocation is the only path to coverage.
     */
    @api
    handleRequestOverride() {
        if (!this.hasCatalogLink || this.hasQuestionOverride) return;
        this.dispatchEvent(new CustomEvent('requestoverride', {
            detail: { field: 'Override_Question__c' }
        }));
    }

    /**
     * "Revert to catalog default" — when overridden, clears the
     * per-binding override and goes back to inheriting from catalog.
     * Parent persists the change. @api for the same testability
     * reason as handleRequestOverride.
     */
    @api
    handleRevert() {
        if (!this.hasQuestionOverride) return;
        this.dispatchEvent(new CustomEvent('revert', {
            detail: { field: 'Override_Question__c' }
        }));
    }

    /**
     * "Create catalog entry" — for saved bindings with no catalog link
     * (imports, clones of unmatched questions, AI drafts). Scoring config
     * lives on the catalog entry, so without this gesture those questions
     * were permanently unscoreable: the scoring panel's directive pointed
     * at a button that didn't exist. The parent calls the Apex promote
     * action and adopts the returned catalog Id. Only offered for
     * bindings that exist as records — unsaved questions get their
     * catalog automatically on first save.
     */
    @api
    handleCreateCatalog() {
        if (this.hasCatalogLink || !this.isSavedBinding) return;
        this.dispatchEvent(new CustomEvent('createcatalog', {
            detail: { questionId: this.selection.id }
        }));
    }

    get isSavedBinding() {
        // Builder selections carry the record Id as selection.id once
        // saved; unsaved drag-drops have a synthetic UUID (no prefix
        // match against an 15/18-char Id shape).
        const id = this.selection && this.selection.id;
        return typeof id === 'string' && /^[a-zA-Z0-9]{15}([a-zA-Z0-9]{3})?$/.test(id) && !id.includes('-');
    }

    get showCreateCatalogButton() {
        return !this.hasCatalogLink && this.isSavedBinding;
    }

    // Wave 35.8a: exclusive catalog (only this binding uses it) — no
    // override button needed because edits flow directly to the catalog.
    get isExclusiveCatalogEntry() {
        return Boolean(this.attributes && this.attributes._exclusiveCatalogEntry);
    }

    // Convenience getters used by the template's conditional rendering.
    // "Override in this template" only makes sense when the catalog is
    // shared (>1 binding); on exclusive entries the admin just edits
    // the Question__c input directly.
    get showOverrideButton() {
        return this.hasCatalogLink && !this.hasQuestionOverride && !this.isExclusiveCatalogEntry;
    }
    get showRevertButton() {
        return this.hasQuestionOverride;
    }
}
