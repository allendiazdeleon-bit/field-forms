import { LightningElement, api } from 'lwc';

/**
 * Pillar 5 builder Scoring panel — sub-component mounted inside the
 * neuraFormBuilderAttributes question editor. Renders the scoring policy
 * fields that live on Form_Question_Catalog__c (the asset). Scoring
 * fields are catalog-only (not binding-level override) per the Pillar 2
 * design — when an admin tweaks weight or severity here, every binding
 * that references this catalog entry inherits the change.
 *
 * Fields shown:
 *   Weight__c                      — points the question is worth
 *   Failure_Severity__c            — Critical / High / Medium / Low
 *   Failure_Auto_Finding__c        — auto-create Form_Finding__c on fail
 *   Failure_Photo_Required__c      — sets Photo_Required__c on the finding
 *   Allow_Exception_Override__c    — per-question policy (Inherit default)
 *   Pass_Criteria__c               — JSON, edited inline as a textarea in
 *                                    v1. A guided criteria builder is a
 *                                    follow-up (the JSON shape mirrors
 *                                    Form_Question__c.Conditions__c so the
 *                                    existing c-neura-form-criteria-builder
 *                                    can be wired in later).
 *
 * No-catalog state: when the question binding has no Form_Question_Catalog__c
 * the panel shows a directive message — scoring needs a catalog entry, so
 * the admin should "Override" or "Create catalog entry" from the Pillar 2
 * provenance badge first.
 *
 * See docs/phase-2-pillar-5-scoring-findings.md "Builder — Scoring tab on
 * a question".
 */

const CATALOG_API_NAME = 'Form_Question_Catalog__c';

export default class NeuraFormBuilderScoring extends LightningElement {
    @api selection;

    get catalogId() {
        return this.selection?.attributes?.Form_Question_Catalog__c || null;
    }

    get hasCatalog() {
        return Boolean(this.catalogId);
    }

    get catalogApiName() {
        return CATALOG_API_NAME;
    }

    handleSubmit(event) {
        // lightning-record-edit-form handles the save itself; we only
        // re-emit so the builder can refresh the in-memory selection (the
        // parent picks the new field values up via wire next tick).
        this.dispatchEvent(
            new CustomEvent('scoringsave', {
                detail: { fields: event.detail.fields },
                bubbles: true,
                composed: true
            })
        );
    }

    handleSuccess() {
        this.dispatchEvent(
            new CustomEvent('scoringsavesuccess', {
                bubbles: true,
                composed: true
            })
        );
    }
}
