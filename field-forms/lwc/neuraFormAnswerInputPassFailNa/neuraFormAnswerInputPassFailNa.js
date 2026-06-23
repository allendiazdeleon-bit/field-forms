import { LightningElement, api, track } from 'lwc';

/**
 * Pass / Fail / N-A — the canonical three-state inspection input.
 *
 * Picklist value: 'Pass Fail NA' (stored as-is on Form_Question__c.Type__c).
 * Value contract: 'pass' | 'fail' | 'na' | null.
 *
 * Rendering mirrors the choice-pills component exactly — a single computed
 * `buttons` array iterated with for:each, driven by an optimistic local value
 * (_localVal). The parent's `value` getter reads the saved answer record,
 * which only updates after the save round-trip; rendering off that alone makes
 * a tap appear to lag. We mirror the value locally and update it immediately
 * on tap, then re-sync from `val` in renderedCallback once the parent catches
 * up — identical to choice-pills, which paints instantly.
 *
 * Tap the active state again to clear it (single-tap "undo").
 */
const OPTIONS = [
    { value: 'pass', label: 'Pass', icon: 'utility:check', base: 'pfn-button pfn-button_pass' },
    { value: 'fail', label: 'Fail', icon: 'utility:close', base: 'pfn-button pfn-button_fail' },
    { value: 'na',   label: 'N/A',  icon: 'utility:dash',  base: 'pfn-button pfn-button_na' }
];
const VALID = new Set(['pass', 'fail', 'na']);

export default class NeuraFormAnswerInputPassFailNa extends LightningElement {
    @api val;

    @track _localVal;
    _lastSeenVal;

    connectedCallback() {
        this._localVal = this.val;
        this._lastSeenVal = this.val;
    }

    renderedCallback() {
        if (this.val !== this._lastSeenVal) {
            this._lastSeenVal = this.val;
            this._localVal = this.val;
        }
    }

    get _effectiveVal() {
        return this._localVal !== undefined ? this._localVal : this.val;
    }

    get buttons() {
        const sel = this._effectiveVal;
        return OPTIONS.map((o) => {
            const active = o.value === sel;
            return {
                value: o.value,
                label: o.label,
                icon: o.icon,
                ariaChecked: active ? 'true' : 'false',
                cssClass: active ? `${o.base} pfn-button_active` : o.base
            };
        });
    }

    handleSelect(event) {
        const v = event.currentTarget && event.currentTarget.dataset.value;
        if (!VALID.has(v)) return;
        // Tap-to-toggle: re-picking the current state clears it.
        const next = this._effectiveVal === v ? null : v;
        this._localVal = next;   // optimistic — paint the selection immediately
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: next },
            bubbles: true,
            composed: true
        }));
    }
}
