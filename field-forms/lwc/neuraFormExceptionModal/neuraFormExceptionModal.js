import { LightningElement, api, track } from 'lwc';

/**
 * Pillar 5 exception override modal. Opens when a tech taps "Mark
 * exception" on a blocking finding (from c-neura-form-findings-panel)
 * and lets them justify why the failure should not block submit.
 *
 * The per-question / per-template policy is surfaced via @api
 * exceptionPolicy (Allow / Require photo / Disallow). When the policy
 * is Disallow, the modal renders an explanatory message instead of
 * the form — the override path is closed at the question level.
 *
 * The component is controlled — parent owns `open` and toggles it
 * after the `confirm` or `cancel` event fires.
 *
 * Events:
 *   confirm { findingId, reason, detail, willAttachPhoto }
 *     reason: one of "Customer waived", "Out of scope",
 *             "Pre-existing condition", "Other"
 *     detail: free-text justification (required when reason = Other)
 *     willAttachPhoto: true when the policy required a photo and the
 *             tech indicated they'll attach next
 *
 *   cancel {}
 *
 * See docs/phase-2-pillar-5-scoring-findings.md "Allow exception
 * override tri-state" — the modal honors the per-question / template
 * setting cascade.
 */

const POLICY_ALLOW = 'Allow';
const POLICY_PHOTO = 'Require photo';
const POLICY_DISALLOW = 'Disallow';

const REASON_OPTIONS = [
    { value: 'Customer waived', label: 'Customer waived' },
    { value: 'Out of scope', label: 'Out of scope for this visit' },
    { value: 'Pre-existing condition', label: 'Pre-existing condition' },
    { value: 'Other', label: 'Other (provide detail below)' }
];

export default class NeuraFormExceptionModal extends LightningElement {
    @api open;
    @api findingId;
    @api findingName;
    @api findingSeverity;

    /** Allow / Require photo / Disallow — passed from per-question
     *  Allow_Exception_Override__c (with template-level fallback). */
    @api exceptionPolicy;

    @track reason = '';
    @track detail = '';
    @track willAttachPhoto = false;

    get reasonOptions() {
        return REASON_OPTIONS;
    }

    get isAllowed() {
        return this.exceptionPolicy !== POLICY_DISALLOW;
    }

    get requiresPhoto() {
        return this.exceptionPolicy === POLICY_PHOTO;
    }

    get headerLabel() {
        return this.isAllowed
            ? 'Mark exception'
            : 'Exception not allowed';
    }

    get isOtherSelected() {
        return this.reason === 'Other';
    }

    /** Confirm disabled until reason is set AND (if Other) detail is
     *  provided AND (if photo required) tech has acknowledged. */
    get isConfirmDisabled() {
        if (!this.isAllowed) return true;
        if (!this.reason) return true;
        if (this.isOtherSelected && !String(this.detail || '').trim())
            return true;
        if (this.requiresPhoto && !this.willAttachPhoto) return true;
        return false;
    }

    get severityClass() {
        const sev = (this.findingSeverity || 'medium').toLowerCase();
        return `exception-modal__severity exception-modal__severity--${sev}`;
    }

    handleReasonChange(event) {
        this.reason = event.detail?.value ?? event.target.value;
    }

    handleDetailChange(event) {
        this.detail = event.detail?.value ?? event.target.value;
    }

    handlePhotoToggle(event) {
        this.willAttachPhoto =
            event.detail?.checked ?? event.target.checked ?? false;
    }

    handleConfirm() {
        if (this.isConfirmDisabled) return;
        this.dispatchEvent(
            new CustomEvent('confirm', {
                detail: {
                    findingId: this.findingId,
                    reason: this.reason,
                    detail: this.detail,
                    willAttachPhoto: this.willAttachPhoto
                },
                bubbles: true,
                composed: true
            })
        );
        this.resetState();
    }

    handleCancel() {
        this.dispatchEvent(
            new CustomEvent('cancel', { bubbles: true, composed: true })
        );
        this.resetState();
    }

    handleBackdropClick(event) {
        // Ignore clicks that bubble up from inside the dialog itself.
        if (event.target === event.currentTarget) {
            this.handleCancel();
        }
    }

    resetState() {
        this.reason = '';
        this.detail = '';
        this.willAttachPhoto = false;
    }
}
