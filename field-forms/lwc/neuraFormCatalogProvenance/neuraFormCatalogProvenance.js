import { LightningElement, api } from 'lwc';

/**
 * Reads catalog-provenance fields off a question binding and renders a
 * compact informational badge: "linked + inherited", "linked + overridden",
 * or "not linked" (mid-migration). Read-only in v1 — the future LWC pass
 * adds the override / revert actions sketched in the design doc wireframe.
 *
 * The host (neuraFormBuilderAttributes) passes the current selection. We
 * read attributes off it directly; no Apex roundtrip needed because
 * neuraFormBuilderController.getFormDetails already returns the binding's
 * Form_Question_Catalog__c / Override_Question__c / Override_Required__c
 * fields on the wire.
 */
export default class NeuraFormCatalogProvenance extends LightningElement {
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
}
