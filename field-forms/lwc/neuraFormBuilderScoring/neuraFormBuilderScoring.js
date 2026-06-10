import { LightningElement, api, track } from 'lwc';
import { FIELDS } from 'c/neuraFormSchemaUtils';

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
 *   Pass_Criteria__c               — JSON ({"all"/"any": [leaf items]});
 *                                    authored via the type-aware quick-rule
 *                                    presets below, hand-editable for the
 *                                    cross-question cases the presets don't
 *                                    cover.
 *
 * No-catalog state: when the question binding has no Form_Question_Catalog__c
 * the panel shows a directive message — scoring needs a catalog entry; the
 * provenance badge's "Create catalog entry" button establishes one.
 */

const CATALOG_API_NAME = 'Form_Question_Catalog__c';

const NUMERIC_TYPES = ['Number', 'Currency', 'Counter', 'Slider', 'Rating', 'Calculation'];
const CHOICE_TYPES = ['Dropdown', 'Multiple Choice', 'Radio Buttons', 'Checkboxes', 'Checklist'];
const BOOLEAN_TYPES = ['Toggle', 'Checkbox'];

export default class NeuraFormBuilderScoring extends LightningElement {
    @api selection;

    // Quick-rule working state. criteriaDraft, once set, drives the
    // Pass_Criteria__c input-field value; undefined leaves the field on
    // the record's stored value.
    @track criteriaDraft;
    @track presetChoiceValue;
    @track presetMin;
    @track presetMax;
    @track presetText = '';

    get catalogId() {
        return this.selection?.attributes?.Form_Question_Catalog__c || null;
    }

    get hasCatalog() {
        return Boolean(this.catalogId);
    }

    get catalogApiName() {
        return CATALOG_API_NAME;
    }

    // Blast radius, made visible at the edit point: how many bindings
    // (across all templates) share this catalog entry. Stamped by the
    // builder's organizeQuestions alongside _exclusiveCatalogEntry.
    get sharedBindingCount() {
        return this.selection?.attributes?._catalogBindingCount || 0;
    }

    get isSharedEntry() {
        return this.sharedBindingCount > 1;
    }

    get blastRadiusLine() {
        return this.isSharedEntry
            ? `Shared entry — changes here re-score all ${this.sharedBindingCount} questions using it, across templates.`
            : 'Only this question uses this entry.';
    }

    // ----- Quick pass rules --------------------------------------------------
    // One tap (or one field + a tap) writes the Pass_Criteria__c JSON for
    // the overwhelmingly common single-question rules. Authoring that JSON
    // by hand was the single most tedious step of setting up scoring.

    get questionType() {
        return this.selection?.attributes?.[FIELDS.Form_Question__c.Type.fieldApiName];
    }

    get isPassFailNa() { return this.questionType === 'Pass Fail NA'; }
    get isBooleanType() { return BOOLEAN_TYPES.includes(this.questionType); }
    get isNumericType() { return NUMERIC_TYPES.includes(this.questionType); }
    get isChoiceType() { return CHOICE_TYPES.includes(this.questionType); }
    get isTextType() {
        return !this.isPassFailNa && !this.isBooleanType
            && !this.isNumericType && !this.isChoiceType;
    }

    get choiceOptions() {
        try {
            const raw = this.selection?.attributes?.[FIELDS.Form_Question__c.ValueSet.fieldApiName];
            const opts = JSON.parse(raw || '[]');
            return (opts || [])
                .filter((o) => o && (o.value != null || o.label != null))
                .map((o) => ({
                    label: o.label != null ? o.label : String(o.value),
                    value: o.value != null ? String(o.value) : o.label
                }));
        } catch (e) {
            return [];
        }
    }

    get hasChoiceOptions() {
        return this.isChoiceType && this.choiceOptions.length > 0;
    }

    _leaf(operator, value) {
        return { resource: 'self', operator, value };
    }

    _applyCriteria(leaves) {
        this.criteriaDraft = JSON.stringify({ all: leaves }, null, 2);
    }

    handlePresetPass() {
        // Pass Fail NA stores lowercase 'pass'/'fail'/'na'.
        this._applyCriteria([this._leaf('equals', 'pass')]);
    }

    handlePresetNotFail() {
        // N/A counts as passing — only an explicit Fail loses the points.
        this._applyCriteria([this._leaf('notEquals', 'fail')]);
    }

    handlePresetChecked() {
        this._applyCriteria([this._leaf('equals', 'true')]);
    }

    handlePresetChoiceChange(event) {
        this.presetChoiceValue = event.detail.value;
    }

    handlePresetChoiceApply() {
        if (!this.presetChoiceValue) return;
        this._applyCriteria([this._leaf('equals', this.presetChoiceValue)]);
    }

    handlePresetMinChange(event) {
        this.presetMin = event.detail.value;
    }

    handlePresetMaxChange(event) {
        this.presetMax = event.detail.value;
    }

    handlePresetRangeApply() {
        const leaves = [];
        if (this.presetMin !== undefined && this.presetMin !== '' && this.presetMin !== null) {
            leaves.push(this._leaf('greaterThanOrEqual', String(this.presetMin)));
        }
        if (this.presetMax !== undefined && this.presetMax !== '' && this.presetMax !== null) {
            leaves.push(this._leaf('lessThanOrEqual', String(this.presetMax)));
        }
        if (leaves.length) this._applyCriteria(leaves);
    }

    handlePresetTextChange(event) {
        this.presetText = event.detail.value;
    }

    handlePresetTextApply() {
        if (!(this.presetText || '').trim()) return;
        this._applyCriteria([this._leaf('contains', this.presetText.trim())]);
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
        // The draft is persisted; let the field show the record value again.
        this.criteriaDraft = undefined;
        this.dispatchEvent(
            new CustomEvent('scoringsavesuccess', {
                bubbles: true,
                composed: true
            })
        );
    }
}
