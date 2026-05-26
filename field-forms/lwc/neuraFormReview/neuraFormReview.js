import { LightningElement, api, track } from 'lwc';
import { FIELDS } from 'c/neuraFormSchemaUtils';
import { reduceError } from 'c/nfCommonUtility';
import summarizeFormCompletion from '@salesforce/apex/NeuraFormMobileController.summarizeFormCompletion';

/**
 * Final review screen shown before the tech taps Submit. Lists every
 * answered question grouped by page, lets the tech jump back to edit
 * any section, and surfaces an AI-generated summary (via the same
 * aiplatform.ModelsAPI wiring the dictation feature uses).
 *
 * Persistence note: the summary is shown for the tech's benefit but
 * NOT saved to the Linked_Form by default. If you want to retain it,
 * add a Summary__c long-text field on Linked_Form__c and write through
 * before triggering the `submit` event.
 */
export default class NeuraFormReview extends LightningElement {
    @api formObject;
    @api linkedFormId;

    @track summary = '';
    @track summarySource = '';
    @track summaryLoading = false;
    @track summaryError = '';

    /* Pillar 5 — pass-through reads of the scoring fields stashed on
       formObject by neuraFormMobile.constructFormObject. When the template
       isn't scored these are null/0 and the submit-guard hides its scoring
       chrome; the submit button still works as before. */
    get scoringEnabled() {
        return this.formObject?.Scoring_Enabled__c === true;
    }

    get formScore() {
        return this.formObject?.linkedForm?.Score__c ?? null;
    }

    get formMaxScore() {
        return this.formObject?.linkedForm?.Max_Score__c ?? null;
    }

    get formScoreThreshold() {
        return this.formObject?.Pass_Threshold_Percent__c ?? null;
    }

    get findings() {
        return Array.isArray(this.formObject?.findings)
            ? this.formObject.findings
            : [];
    }

    handleSubmitGuardViewFindings() {
        // Re-dispatch so the renderer (or its parent) can open the findings
        // panel pre-expanded. The renderer composes the panel today; this
        // keeps the submit-guard primitive position-agnostic.
        this.dispatchEvent(
            new CustomEvent('viewfindings', { bubbles: true, composed: true })
        );
    }

    handleSubmitGuardSaveDraft() {
        this.dispatchEvent(
            new CustomEvent('savedraft', { bubbles: true, composed: true })
        );
    }

    get pages() {
        return (this.formObject?.pages || []).map((p, idx) => {
            return {
                ...p,
                pageNumber: idx + 1,
                title: p[FIELDS.Form_Page__c.Title.fieldApiName] || p.Name || `Page ${idx + 1}`,
                rows: this._rowsFor(p)
            };
        }).filter((p) => p.rows.length > 0);
    }

    _rowsFor(page) {
        const out = [];
        (page.sections || []).forEach((s) => {
            (s.questions || []).forEach((q) => {
                if (q.shouldRender === false) return;
                const type = q[FIELDS.Form_Question__c.Type.fieldApiName];
                if (type === 'Display Text') return;
                const answerObj = q.answers?.[0];
                const value = answerObj
                    ? answerObj[FIELDS.Form_Answer__c.Answer.fieldApiName]
                    : '';
                out.push({
                    id: q.Id,
                    label: q[FIELDS.Form_Question__c.Question.fieldApiName] || q.Name,
                    value: value || '(no answer)',
                    isMissing: !value,
                    // Precomputed class — LWC templates can't evaluate
                    // ternaries inline in attribute bindings.
                    valueClass: value
                        ? 'review-row__value'
                        : 'review-row__value review-row__value_missing'
                });
            });
        });
        return out;
    }

    connectedCallback() {
        this._loadSummary();
    }

    async _loadSummary() {
        this.summaryLoading = true;
        this.summaryError = '';
        try {
            const snapshots = [];
            (this.formObject?.pages || []).forEach((p) => {
                (p.sections || []).forEach((s) => {
                    (s.questions || []).forEach((q) => {
                        if (q.shouldRender === false) return;
                        const type = q[FIELDS.Form_Question__c.Type.fieldApiName];
                        if (type === 'Display Text' || type === 'Signature') return;
                        const a = q.answers?.[0]?.[FIELDS.Form_Answer__c.Answer.fieldApiName];
                        if (!a) return;
                        snapshots.push({
                            questionLabel: q[FIELDS.Form_Question__c.Question.fieldApiName] || q.Name,
                            answer: String(a)
                        });
                    });
                });
            });

            const result = await summarizeFormCompletion({
                linkedFormId: this.linkedFormId,
                snapshots
            });
            this.summary = result?.summary || '';
            this.summarySource = result?.source || '';
        } catch (e) {
            this.summaryError = reduceError(e);
        } finally {
            this.summaryLoading = false;
        }
    }

    get summarySourceLabel() {
        if (!this.summarySource) return '';
        return this.summarySource === 'agentforce'
            ? 'Generated by Agentforce'
            : 'Quick summary (AI unavailable)';
    }

    handleSummaryEdit(event) {
        this.summary = event?.detail?.value ?? event?.target?.value ?? '';
    }

    handleEditClick(event) {
        const pageNumber = parseInt(event.currentTarget.dataset.page, 10);
        this.dispatchEvent(new CustomEvent('edit', {
            detail: { pageIndex: pageNumber - 1 },
            bubbles: true,
            composed: true
        }));
    }

    handleSubmit() {
        this.dispatchEvent(new CustomEvent('submit', {
            detail: { summary: this.summary },
            bubbles: true,
            composed: true
        }));
    }

    handleRegenerate() {
        this._loadSummary();
    }
}
