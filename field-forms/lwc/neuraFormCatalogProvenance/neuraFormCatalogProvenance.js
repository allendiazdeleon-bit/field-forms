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
}
