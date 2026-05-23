import { LightningElement, api, track } from 'lwc';

/**
 * Checklist — admin-defined fixed list of items, each scored Pass / Fail / N-A.
 *
 * Composes the Pass/Fail/N-A pattern (wave 7) with the array-JSON storage
 * approach (wave 10). Differs from Repeatable in that the rows are
 * defined by the admin (via Value_Set__c) rather than the user.
 *
 * Use cases: pre-flight checks, safety inspections, multi-point QA.
 *
 * Configuration: the parent (`neuraFormAnswer`) passes the existing
 * `options` getter (parsed Value_Set__c) as the `options` prop. Each
 * option's `label` becomes a row label.
 *
 * Public API:
 *   @api val      JSON string: [{ label, state }, ...]
 *   @api options  array of { label, value } from Value_Set__c
 *
 * Emits 'change' with detail { value } on each per-row state change.
 */
const STATES = ['pass', 'fail', 'na'];

export default class NeuraFormAnswerInputChecklist extends LightningElement {
    @api val;
    @api options;

    @track _rows = [];

    connectedCallback() {
        this._rebuild();
    }

    renderedCallback() {
        // Options may arrive after connectedCallback (the parent reads
        // Value_Set__c lazily). Rebuild defensively.
        this._rebuild();
    }

    _rebuild() {
        const labels = this._labelsFromOptions(this.options);
        const stateMap = this._parseExisting(this.val);
        const next = labels.map((label) => ({
            id: label,
            label,
            state: stateMap[label] || null
        }));
        // Skip churn if unchanged.
        if (JSON.stringify(next) === JSON.stringify(this._rows)) return;
        this._rows = next;
    }

    _labelsFromOptions(options) {
        if (!Array.isArray(options)) return [];
        return options
            .map((o) => (o && (o.label || o.value)) || '')
            .filter((s) => s && String(s).trim());
    }

    _parseExisting(raw) {
        if (!raw) return {};
        try {
            const parsed = JSON.parse(raw);
            if (Array.isArray(parsed)) {
                const map = {};
                parsed.forEach((item) => {
                    if (item && item.label && STATES.includes(item.state)) {
                        map[item.label] = item.state;
                    }
                });
                return map;
            }
        } catch (e) {
            // Pre-Checklist answers (plain text) are dropped here — there's
            // no sensible mapping from "free text" to per-row pass/fail/na.
        }
        return {};
    }

    get rows() {
        // Per-row render data with pre-computed class strings so the
        // template stays declarative.
        return this._rows.map((r) => ({
            ...r,
            isPass: r.state === 'pass',
            isFail: r.state === 'fail',
            isNa:   r.state === 'na',
            passClass: this._btnClass('pass', r.state),
            failClass: this._btnClass('fail', r.state),
            naClass:   this._btnClass('na',   r.state)
        }));
    }

    _btnClass(want, actual) {
        const base = `chk-btn chk-btn_${want}`;
        return actual === want ? `${base} chk-btn_active` : base;
    }

    get hasRows() { return this._rows.length > 0; }

    get completionLabel() {
        const total = this._rows.length;
        if (total === 0) return '';
        const done = this._rows.filter((r) => r.state).length;
        return `${done} of ${total}`;
    }

    get progressPercent() {
        const total = this._rows.length;
        if (total === 0) return 0;
        const done = this._rows.filter((r) => r.state).length;
        return Math.round((done / total) * 100);
    }

    get progressStyle() {
        return `width: ${this.progressPercent}%`;
    }

    handleStateClick(event) {
        const id = event.currentTarget && event.currentTarget.dataset.id;
        const state = event.currentTarget && event.currentTarget.dataset.state;
        if (!id || !STATES.includes(state)) return;
        this._rows = this._rows.map((r) => {
            if (r.id !== id) return r;
            // Tap-to-toggle: re-tapping the active state clears it.
            return { ...r, state: r.state === state ? null : state };
        });
        this._emit();
    }

    _emit() {
        const value = JSON.stringify(
            this._rows.map((r) => ({ label: r.label, state: r.state }))
        );
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value },
            bubbles: true,
            composed: true
        }));
    }
}
