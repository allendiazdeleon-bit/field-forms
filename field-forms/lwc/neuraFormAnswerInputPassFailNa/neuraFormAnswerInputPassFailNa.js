import { LightningElement, api } from 'lwc';

/**
 * Pass / Fail / N-A — the canonical three-state inspection input.
 *
 * Picklist value: 'Pass Fail NA' (stored as-is on Form_Question__c.Type__c).
 *
 * Value contract:
 *   'pass' | 'fail' | 'na' | null
 *
 * Emits the 'change' event with detail { value } whenever the user picks
 * a new state. Click the same state again to clear (matches the existing
 * Skip / unskip behavior on neuraFormQuestion — gives the technician a
 * single tap path to "I made a mistake, undo").
 *
 * Composition note: the standard "Require comment on Fail" rule isn't
 * baked into this component — that's a property-panel concern that the
 * existing criteria builder can drive declaratively. Keep the component
 * dumb; smart behavior lives in neuraFormAnswer / criteria.
 */
const VALID = ['pass', 'fail', 'na'];

export default class NeuraFormAnswerInputPassFailNa extends LightningElement {
    @api val;

    handleSelect(event) {
        const v = event.currentTarget && event.currentTarget.dataset.value;
        if (!VALID.includes(v)) return;
        // Tap-to-toggle: re-picking the current state clears it.
        const next = this.val === v ? null : v;
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: next },
            bubbles: true,
            composed: true
        }));
    }

    get isPass() { return this.val === 'pass'; }
    get isFail() { return this.val === 'fail'; }
    get isNa()   { return this.val === 'na'; }

    get passButtonClass() { return this.isPass ? 'pfn-button pfn-button_pass pfn-button_active' : 'pfn-button pfn-button_pass'; }
    get failButtonClass() { return this.isFail ? 'pfn-button pfn-button_fail pfn-button_active' : 'pfn-button pfn-button_fail'; }
    get naButtonClass()   { return this.isNa   ? 'pfn-button pfn-button_na pfn-button_active'   : 'pfn-button pfn-button_na';   }
}
