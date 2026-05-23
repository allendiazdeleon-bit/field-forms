import { LightningElement, api } from 'lwc';

/**
 * Counter — minus / number / plus. The mobile-friendly alternative to
 * a plain Number input when the typical answer is a small count
 * (parts replaced, units serviced, hours worked). Big tap targets +
 * tap-to-increment is meaningfully faster with gloved hands than
 * keyboard entry.
 *
 * Value contract:
 *   integer (or string parseable to integer) | null
 *
 * Optional bounds via @api min / max / step — wire these from
 * Form_Question__c question metadata in neuraFormAnswer.
 *
 * Emits 'change' on every increment/decrement with detail { value }.
 */
export default class NeuraFormAnswerInputCounter extends LightningElement {
    @api val;
    @api min;
    @api max;
    @api step = 1;

    get currentValue() {
        const n = Number(this.val);
        return Number.isFinite(n) ? n : 0;
    }

    get displayValue() {
        // Show "0" when val is null/undefined (rather than blank) — makes
        // the counter look "ready to use" instead of empty.
        return String(this.currentValue);
    }

    get parsedStep() {
        const s = Number(this.step);
        return Number.isFinite(s) && s > 0 ? s : 1;
    }

    get _hasMin() { return this.min !== undefined && this.min !== null && this.min !== ''; }
    get _hasMax() { return this.max !== undefined && this.max !== null && this.max !== ''; }
    get _minNum() { return Number(this.min); }
    get _maxNum() { return Number(this.max); }

    get decrementDisabled() {
        if (!this._hasMin) return false;
        return this.currentValue - this.parsedStep < this._minNum;
    }

    get incrementDisabled() {
        if (!this._hasMax) return false;
        return this.currentValue + this.parsedStep > this._maxNum;
    }

    handleDecrement() {
        if (this.decrementDisabled) return;
        this._emit(this.currentValue - this.parsedStep);
    }

    handleIncrement() {
        if (this.incrementDisabled) return;
        this._emit(this.currentValue + this.parsedStep);
    }

    handleManualInput(event) {
        const raw = event && event.target && event.target.value;
        const n = Number(raw);
        if (!Number.isFinite(n)) return;
        let next = n;
        if (this._hasMin && next < this._minNum) next = this._minNum;
        if (this._hasMax && next > this._maxNum) next = this._maxNum;
        this._emit(next);
    }

    _emit(value) {
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }
}
