import { LightningElement, api, track } from 'lwc';

/**
 * Repeatable — variable-length list of text values.
 *
 * Use cases: parts lists, meter readings, multiple gauge readings,
 * "list all assets serviced today." The "add another row" pattern.
 *
 * Data model — v1 simplification:
 *   Stores as a JSON-stringified array of strings in the existing
 *   Form_Answer__c.Answer__c long-text field (131k chars cap). No
 *   schema changes needed; the existing save / load / draft pipeline
 *   treats it as any other string. Future v2 can support per-row
 *   sub-fields by changing each element from string → object — the
 *   storage location stays the same.
 *
 * Public API:
 *   @api val          JSON-stringified array (or empty)
 *   @api min          minimum required rows (from Form_Question__c.Min__c)
 *   @api max          maximum allowed rows (from Form_Question__c.Max__c)
 *   @api placeholder  per-row placeholder text
 *
 * Emits 'change' with detail { value } whenever the user mutates a row
 * (add, remove, edit). Empty rows are NOT filtered out on emit — the
 * tech might leave a row blank intentionally as a "to do" placeholder;
 * the form's submit-validation layer can prune if needed.
 */
let _ID_COUNTER = 0;
const _newId = () => `r${++_ID_COUNTER}-${Date.now()}`;

export default class NeuraFormAnswerInputRepeatable extends LightningElement {
    @api val;
    @api min;
    @api max;
    @api placeholder = 'Enter a value';

    @track _rows = [];

    connectedCallback() {
        this._rows = this._parseRows(this.val);
        if (!this._rows.length) {
            this._rows = [this._makeRow('')];
        }
    }

    _parseRows(raw) {
        if (!raw) return [];
        try {
            const parsed = JSON.parse(raw);
            if (Array.isArray(parsed)) {
                return parsed.map((v) => this._makeRow(typeof v === 'string' ? v : String(v)));
            }
        } catch (e) {
            // Treat malformed JSON as a single legacy text answer rather
            // than dropping the user's data. Some answers may have been
            // captured before this question was switched to Repeatable.
            return [this._makeRow(String(raw))];
        }
        return [];
    }

    _makeRow(value) {
        return { id: _newId(), value: value || '' };
    }

    get rows() { return this._rows; }

    get _hasMin() { return this.min !== undefined && this.min !== null && this.min !== ''; }
    get _hasMax() { return this.max !== undefined && this.max !== null && this.max !== ''; }
    get _minNum() { return Number(this.min); }
    get _maxNum() { return Number(this.max); }

    get addDisabled() {
        return this._hasMax && this._rows.length >= this._maxNum;
    }

    get removeDisabled() {
        // Always allow removing down to 1 row (the UI keeps at least
        // one empty input visible for affordance). If admin set a min,
        // honor it.
        if (this._hasMin) {
            return this._rows.length <= Math.max(1, this._minNum);
        }
        return this._rows.length <= 1;
    }

    get addLabel() {
        if (this.addDisabled) return `Max ${this._maxNum} rows`;
        return 'Add row';
    }

    get rowCountLabel() {
        const n = this._rows.length;
        if (this._hasMax) return `${n} of ${this._maxNum}`;
        return `${n} ${n === 1 ? 'row' : 'rows'}`;
    }

    handleAdd() {
        if (this.addDisabled) return;
        this._rows = [...this._rows, this._makeRow('')];
        this._emit();
    }

    handleRemove(event) {
        if (this.removeDisabled) return;
        const id = event.currentTarget && event.currentTarget.dataset.id;
        if (!id) return;
        this._rows = this._rows.filter((r) => r.id !== id);
        if (!this._rows.length) {
            this._rows = [this._makeRow('')];
        }
        this._emit();
    }

    handleRowInput(event) {
        const id = event.currentTarget && event.currentTarget.dataset.id;
        if (!id) return;
        const v = event.target.value;
        this._rows = this._rows.map((r) => (r.id === id ? { ...r, value: v } : r));
        this._emit();
    }

    _emit() {
        const value = JSON.stringify(this._rows.map((r) => r.value));
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }
}
