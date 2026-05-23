import { LightningElement, api, track } from 'lwc';

/**
 * Choice-Pills — the modern mobile-first replacement for combobox/dropdown
 * rendering on choice questions. One tap to pick, all options visible,
 * no precision required, responsive wrap on narrow screens.
 *
 * Replaces the combobox rendering used by Multiple Choice / Dropdown /
 * Radio Buttons whenever option count is small enough that pills fit.
 * Bigger lists fall back to the existing combobox via neuraFormAnswer.
 *
 * Public API:
 *   @api options        array of { label, value }
 *   @api val            current selection — string for single-select,
 *                       comma-separated for multi-select (matches the
 *                       existing storage format used elsewhere in the app)
 *   @api isMulti        true to enable multi-select tapping
 *
 * Emits 'change' with detail { value } on every selection change.
 *
 * "Other" handling: if any option's label is "Other" (case-insensitive)
 * and the question is single-select, picking that pill reveals a text
 * input below the pills. The typed text replaces the stored value while
 * the "Other" pill stays visually selected. If the field is empty when
 * the user leaves it, falls back to literal "Other" so the question
 * still has a value. Multi-select keeps "Other" as a plain option for v1.
 */
const OTHER_LABEL = 'other';

export default class NeuraFormAnswerInputChoicePills extends LightningElement {
    @api options;
    @api val;
    @api isMulti = false;

    @track _otherText = '';

    // Optimistic local state. The parent's `value` getter reads from
    // the question's answer record (not local state), which only
    // updates after the form renderer's save pipeline round-trips. If
    // we render based purely on `val`, the tap appears to "do nothing"
    // for the 100-500ms it takes the change to come back. We mirror val
    // locally and update immediately on click; renderedCallback
    // re-syncs from val when the parent catches up.
    @track _localVal;
    _lastSeenVal;

    connectedCallback() {
        this._localVal = this.val;
        this._lastSeenVal = this.val;
    }

    renderedCallback() {
        // The parent moved val to a new value — accept it as the new
        // truth. Compare against _lastSeenVal so this doesn't fight our
        // own optimistic write.
        if (this.val !== this._lastSeenVal) {
            this._lastSeenVal = this.val;
            this._localVal = this.val;
        }
    }

    get _effectiveVal() {
        return this._localVal !== undefined ? this._localVal : this.val;
    }

    // --- Render state -------------------------------------------------------

    get _selectedValues() {
        // Multi-select stores comma-separated; single-select stores plain.
        // Treat empty/undefined consistently to avoid [undefined].
        const v = this._effectiveVal;
        if (!v) return [];
        return this.isMulti
            ? String(v).split(',').map((s) => s.trim()).filter(Boolean)
            : [String(v)];
    }

    get pills() {
        const selected = new Set(this._selectedValues);
        const otherLabel = this._otherOptionLabel; // null if no Other
        const valueIsCustomOther = this._valueIsCustomOther;

        return (this.options || []).map((opt) => {
            const value = opt.value ?? opt.label;
            const label = opt.label ?? opt.value;
            const isOther = this._isOtherLabel(label);
            const isActive = isOther && !this.isMulti && valueIsCustomOther
                ? true
                : selected.has(value);
            return {
                key: value,
                label,
                value,
                isActive,
                isOther,
                cssClass: this._pillClass(isActive, isOther)
            };
        });
    }

    get _otherOptionLabel() {
        const opt = (this.options || []).find((o) => this._isOtherLabel(o.label));
        return opt ? opt.label : null;
    }

    get _otherOptionValue() {
        const opt = (this.options || []).find((o) => this._isOtherLabel(o.label));
        return opt ? (opt.value ?? opt.label) : null;
    }

    _isOtherLabel(label) {
        return String(label || '').trim().toLowerCase() === OTHER_LABEL;
    }

    _pillClass(isActive, isOther) {
        const base = 'pill';
        const parts = [base];
        if (isActive) parts.push('pill_active');
        if (isOther)  parts.push('pill_other');
        return parts.join(' ');
    }

    /**
     * Detects: the current val is NOT one of the known option values, AND
     * an Other option exists. Treated as "Other selected with custom text."
     * Only applies in single-select mode for v1.
     */
    get _valueIsCustomOther() {
        if (this.isMulti) return false;
        if (!this._otherOptionValue) return false;
        const v = this._effectiveVal;
        if (!v) return false;
        const validValues = new Set(
            (this.options || []).map((o) => o.value ?? o.label)
        );
        return !validValues.has(String(v));
    }

    get showOtherInput() {
        if (this.isMulti) return false;
        if (!this._otherOptionValue) return false;
        return this._valueIsCustomOther || this._effectiveVal === this._otherOptionValue;
    }

    get otherInputValue() {
        // If val is "Other" literally, the input is empty; otherwise val IS
        // the custom text the user typed.
        const v = this._effectiveVal;
        if (v === this._otherOptionValue) return '';
        return v || '';
    }

    get groupRole() {
        return this.isMulti ? 'group' : 'radiogroup';
    }

    // --- Interaction handlers -----------------------------------------------

    handlePillClick(event) {
        const value = event.currentTarget && event.currentTarget.dataset.value;
        if (value === undefined || value === null) return;

        if (this.isMulti) {
            this._toggleMulti(value);
        } else {
            // Tap-to-toggle in single-select: re-tapping the active pill clears.
            const current = String(this._effectiveVal || '');
            const isClearingActive =
                current === value ||
                (this._isOtherValue(value) && this._valueIsCustomOther);
            const newValue = isClearingActive ? '' : value;
            this._localVal = newValue;   // optimistic update
            this._emit(newValue);
        }
    }

    _toggleMulti(value) {
        const current = new Set(this._selectedValues);
        if (current.has(value)) {
            current.delete(value);
        } else {
            current.add(value);
        }
        const newValue = Array.from(current).join(',');
        this._localVal = newValue;   // optimistic update
        this._emit(newValue);
    }

    _isOtherValue(value) {
        return value === this._otherOptionValue;
    }

    handleOtherInput(event) {
        const text = event.target && event.target.value;
        // While typing: emit the typed text (so the form sees the change).
        // If user blanks it out, fall back to literal "Other" so the
        // question still has a value indicating Other was selected.
        const newValue = !text ? (this._otherOptionValue || 'Other') : text;
        this._localVal = newValue;   // optimistic update
        this._emit(newValue);
    }

    _emit(value) {
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }
}
