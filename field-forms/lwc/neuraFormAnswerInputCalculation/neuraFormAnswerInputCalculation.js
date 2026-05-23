import { LightningElement, api } from 'lwc';
import { evaluateFormula, formatResult } from './formulaEvaluator';

/**
 * Read-only display of a computed value derived from other answers on the
 * same form via a small expression language (see formulaEvaluator.js).
 *
 * The parent renderer passes:
 *   - formula: the Calculation_Formula__c text
 *   - format: the Calculation_Result_Format__c picklist value
 *   - answerMap: a plain object { questionId -> answer-value }
 *
 * Reactivity: when the parent re-passes answerMap (any answer change), this
 * component recomputes synchronously inside the answerMap setter. The
 * computed value is also surfaced upward via a 'computed' event so the
 * renderer can persist it as a normal Form_Answer.
 */
export default class NeuraFormAnswerInputCalculation extends LightningElement {
    @api formula;
    @api format = 'Decimal';
    @api questionId;

    _answerMap = {};
    rawValue = '';
    displayValue = '';
    errorMessage = '';

    // True when the question has no formula configured. Used by the
    // template to swap the em-dash for an admin-facing "Set Calculation
    // Formula on this question" hint so the design-time preview reads
    // as actionable rather than "broken." Returns false once the admin
    // populates the formula and the runtime behavior takes over.
    get noFormula() {
        const f = this.formula;
        return f === undefined || f === null || String(f).trim() === '';
    }

    @api
    get answerMap() {
        return this._answerMap;
    }
    set answerMap(value) {
        this._answerMap = value || {};
        this.recompute();
    }

    // The renderer reads this via lwc:ref to harvest the computed answer on
    // save without round-tripping through an event.
    @api
    get val() {
        return this.rawValue === '' || this.rawValue === null || this.rawValue === undefined
            ? ''
            : String(this.rawValue);
    }

    connectedCallback() {
        this.recompute();
    }

    _lastEmitted; // Guard so recompute -> change -> answerMap -> recompute doesn't loop.

    recompute() {
        const resolver = (id) => this._answerMap?.[id];
        const result = evaluateFormula(this.formula, resolver);
        if (result.ok) {
            this.errorMessage = '';
            this.rawValue = result.value === '' ? '' : result.value;
            this.displayValue = formatResult(result.value, this.format);
        } else {
            this.errorMessage = result.error || 'Formula error';
            this.rawValue = '';
            this.displayValue = '';
        }
        const nextVal = this.val;
        if (nextVal !== this._lastEmitted) {
            this._lastEmitted = nextVal;
            this.dispatchEvent(new CustomEvent('change', {
                detail: { value: nextVal },
                bubbles: true,
                composed: true
            }));
        }
    }

    @api
    checkValidity() {
        // A Calculation question is always "valid" - if the formula errored,
        // the renderer will still save an empty answer, not block submission.
        return true;
    }
}
