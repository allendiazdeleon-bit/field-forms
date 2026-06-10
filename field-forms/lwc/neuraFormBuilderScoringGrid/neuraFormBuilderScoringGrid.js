import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceError } from 'c/nfCommonUtility';
import getScoringGrid from '@salesforce/apex/neuraFormBuilderController.getScoringGrid';
import saveScoringGrid from '@salesforce/apex/neuraFormBuilderController.saveScoringGrid';

/**
 * Template-level scoring grid (modal). Every question on one screen with
 * inline Weight / Severity / failure-policy / quick-rule columns and a live
 * weight total — replacing the click-into-each-question workflow that made
 * scoring setup tedious on real-sized templates.
 *
 * Catalog mechanics are invisible here: rows without a catalog entry are
 * promoted automatically server-side on save (the catalog stays the single
 * source of truth for scoring without being a per-question setup step).
 *
 * Quick rules are the same type-aware presets as the per-question panel,
 * flattened into a combobox per row. Rules the presets can't express
 * (numeric ranges, cross-question criteria) show as "(custom)" and are
 * edited in the per-question panel — the grid never overwrites a rule
 * unless the admin picks a new preset for that row.
 */

const SEVERITY_OPTIONS = [
    { label: '—', value: '' },
    { label: 'Critical', value: 'Critical' },
    { label: 'High', value: 'High' },
    { label: 'Medium', value: 'Medium' },
    { label: 'Low', value: 'Low' }
];

const CHOICE_TYPES = ['Dropdown', 'Multiple Choice', 'Radio Buttons', 'Checkboxes', 'Checklist'];
const BOOLEAN_TYPES = ['Toggle', 'Checkbox'];

const KEEP = '__keep__';
const CLEAR = '__clear__';

export default class NeuraFormBuilderScoringGrid extends LightningElement {
    @api formTemplateId;
    @api declaredMaxScore;

    @track rows = [];
    @track open = false;
    loading = false;
    saving = false;
    severityOptions = SEVERITY_OPTIONS;

    @api
    async show() {
        this.open = true;
        this.loading = true;
        try {
            const data = await getScoringGrid({ formTemplateId: this.formTemplateId });
            this.rows = (data || []).map((r) => this._toViewRow(r));
        } catch (error) {
            this.toastError('Could not load scoring grid', reduceError(error));
            this.open = false;
        } finally {
            this.loading = false;
        }
    }

    close() {
        if (this.saving) return;
        this.open = false;
    }

    handleModalKeydown(event) {
        if (event.key === 'Escape') {
            event.stopPropagation();
            this.close();
        }
    }

    // ----- view model --------------------------------------------------------

    _toViewRow(r) {
        return {
            questionId: r.questionId,
            questionText: r.questionText,
            questionType: r.questionType,
            weight: r.weight,
            failureSeverity: r.failureSeverity || '',
            autoFinding: r.autoFinding === true,
            photoRequired: r.photoRequired === true,
            passCriteria: r.passCriteria,
            ruleChoice: KEEP,
            ruleOptions: this._ruleOptionsFor(r),
            ruleSummary: this._summarizeRule(r.passCriteria),
            dirty: false
        };
    }

    _ruleOptionsFor(r) {
        const opts = [{ label: '(keep current)', value: KEEP }];
        const type = r.questionType;
        if (type === 'Pass Fail NA') {
            opts.push({ label: 'Pass when Pass', value: 'eq:pass' });
            opts.push({ label: 'Pass unless Fail', value: 'neq:fail' });
        } else if (BOOLEAN_TYPES.includes(type)) {
            opts.push({ label: 'Pass when checked / on', value: 'eq:true' });
        } else if (CHOICE_TYPES.includes(type)) {
            try {
                const parsed = JSON.parse(r.valueSet || '[]') || [];
                for (const o of parsed) {
                    const value = o.value != null ? String(o.value) : o.label;
                    const label = o.label != null ? o.label : String(o.value);
                    if (value != null) {
                        opts.push({ label: `Pass when = ${label}`, value: `eq:${value}` });
                    }
                }
            } catch (e) { /* unparseable value set: no presets */ }
        }
        opts.push({ label: '(no rule)', value: CLEAR });
        return opts;
    }

    _summarizeRule(json) {
        if (!json) return '—';
        try {
            const parsed = JSON.parse(json);
            const leaves = parsed.all || parsed.any;
            if (Array.isArray(leaves) && leaves.length === 1 && leaves[0].resource === 'self') {
                const { operator, value } = leaves[0];
                if (operator === 'equals') return `= ${value}`;
                if (operator === 'notEquals') return `≠ ${value}`;
                if (operator === 'contains') return `contains "${value}"`;
                if (operator === 'greaterThanOrEqual') return `≥ ${value}`;
                if (operator === 'lessThanOrEqual') return `≤ ${value}`;
            }
            if (Array.isArray(leaves) && leaves.length === 2
                && leaves.every((l) => l.resource === 'self')) {
                const min = leaves.find((l) => l.operator === 'greaterThanOrEqual');
                const max = leaves.find((l) => l.operator === 'lessThanOrEqual');
                if (min && max) return `${min.value} – ${max.value}`;
            }
            return '(custom)';
        } catch (e) {
            return '(custom)';
        }
    }

    get weightTotal() {
        return this.rows.reduce((sum, r) => sum + (Number(r.weight) || 0), 0);
    }

    get totalLine() {
        let line = `Weights total: ${this.weightTotal}`;
        if (this.declaredMaxScore != null && this.declaredMaxScore !== '') {
            line += ` · Max Score: ${this.declaredMaxScore}`;
        }
        return line;
    }

    get totalClass() {
        return this.totalMismatch
            ? 'scoring-grid__total_mismatch'
            : 'slds-text-color_weak';
    }

    get totalMismatch() {
        return this.declaredMaxScore != null && this.declaredMaxScore !== ''
            && Number(this.weightTotal) !== Number(this.declaredMaxScore);
    }

    get dirtyCount() {
        return this.rows.filter((r) => r.dirty).length;
    }

    get saveDisabled() {
        return this.saving || this.dirtyCount === 0;
    }

    get saveLabel() {
        return this.saving
            ? 'Saving…'
            : (this.dirtyCount ? `Save ${this.dirtyCount} question(s)` : 'Save');
    }

    // ----- edits --------------------------------------------------------------

    _patchRow(questionId, patch) {
        this.rows = this.rows.map((r) =>
            r.questionId === questionId ? { ...r, ...patch, dirty: true } : r
        );
    }

    handleWeightChange(event) {
        this._patchRow(event.target.dataset.id, { weight: event.detail.value });
    }

    handleSeverityChange(event) {
        this._patchRow(event.target.dataset.id, { failureSeverity: event.detail.value });
    }

    handleAutoFindingChange(event) {
        this._patchRow(event.target.dataset.id, { autoFinding: event.target.checked });
    }

    handlePhotoChange(event) {
        this._patchRow(event.target.dataset.id, { photoRequired: event.target.checked });
    }

    handleRuleChange(event) {
        const choice = event.detail.value;
        const id = event.target.dataset.id;
        const row = this.rows.find((r) => r.questionId === id);
        if (!row) return;
        let passCriteria = row.passCriteria;
        let ruleSummary = row.ruleSummary;
        if (choice === CLEAR) {
            passCriteria = null;
            ruleSummary = '—';
        } else if (choice !== KEEP) {
            const [op, ...valueParts] = choice.split(':');
            const value = valueParts.join(':');
            const operator = op === 'eq' ? 'equals' : 'notEquals';
            passCriteria = JSON.stringify({ all: [{ resource: 'self', operator, value }] });
            ruleSummary = this._summarizeRule(passCriteria);
        }
        this._patchRow(id, { ruleChoice: choice, passCriteria, ruleSummary });
    }

    // ----- save ----------------------------------------------------------------

    async handleSave() {
        const dirty = this.rows.filter((r) => r.dirty);
        if (!dirty.length) return;
        this.saving = true;
        try {
            const payload = dirty.map((r) => ({
                questionId: r.questionId,
                weight: r.weight === '' || r.weight === null || r.weight === undefined
                    ? null : Number(r.weight),
                failureSeverity: r.failureSeverity || null,
                autoFinding: r.autoFinding,
                photoRequired: r.photoRequired,
                passCriteria: r.passCriteria || null
            }));
            const data = await saveScoringGrid({
                formTemplateId: this.formTemplateId,
                rows: payload
            });
            this.rows = (data || []).map((r) => this._toViewRow(r));
            this.dispatchEvent(new ShowToastEvent({
                title: 'Scoring saved',
                message: `${dirty.length} question(s) updated.`,
                variant: 'success'
            }));
            this.dispatchEvent(new CustomEvent('scoringsaved'));
        } catch (error) {
            this.toastError('Could not save scoring', reduceError(error));
        } finally {
            this.saving = false;
        }
    }

    toastError(title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error' }));
    }
}
