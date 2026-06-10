import { LightningElement, api } from 'lwc';

/**
 * Page-level dictation panel. Replaces per-field mic buttons with one
 * affordance per page: a collapsible textarea the user can dictate, type,
 * or paste into, then "Apply" to map the content across the page's
 * questions.
 *
 * Why a textarea (not just a mic)? FSL Mobile on iOS uses WKWebView,
 * which doesn't expose window.SpeechRecognition. A mic-only UX would
 * silently no-op there. The textarea path always works — users can use
 * the OS keyboard's built-in dictation key to populate it on any device.
 * When the Web Speech API is available (desktop Chrome / some Android
 * WebViews), the mic also appears as a secondary affordance.
 */
export default class NeuraPageDictation extends LightningElement {
    // Compact mode: icon-only trigger and the panel opens as a popover
    // instead of pushing the page content down. Used by the renderer's
    // toolbar, where the labeled button + inline panel crowded the chrome
    // above the form.
    @api compact = false;

    showPanel = false;
    transcriptText = '';

    get wrapperClass() {
        return this.compact
            ? 'dictation-host dictation-host_compact'
            : 'slds-m-horizontal_small slds-m-bottom_x-small';
    }

    get panelClass() {
        return this.compact
            ? 'slds-box slds-box_x-small slds-m-top_x-small dictation-panel_popover'
            : 'slds-box slds-box_x-small slds-m-top_x-small';
    }

    get isWebSpeechAvailable() {
        return typeof window !== 'undefined' &&
            !!(window.SpeechRecognition || window.webkitSpeechRecognition);
    }

    get togglerLabel() {
        return this.showPanel ? 'Hide dictation' : 'Dictate this page';
    }

    get hasText() {
        return !!(this.transcriptText && this.transcriptText.trim().length);
    }

    get hasNoText() {
        return !this.hasText;
    }

    handleToggle() {
        this.showPanel = !this.showPanel;
    }

    handleTextChange(event) {
        // lightning-textarea fires both `event.target.value` and
        // `event.detail.value` in different LWC releases — accept either so
        // the panel reliably captures what the user typed/dictated.
        this.transcriptText = event?.detail?.value ?? event?.target?.value ?? '';
    }

    handleVoiceTranscript(event) {
        const incoming = (event?.detail?.text || '').trim();
        if (!incoming) return;
        const existing = this.transcriptText ? this.transcriptText.trim() : '';
        const separator = existing && !existing.endsWith('.') ? '. ' : ' ';
        this.transcriptText = (existing ? existing + separator : '') + incoming;
    }

    handleApply() {
        const text = (this.transcriptText || '').trim();
        if (!text) return;
        this.dispatchEvent(new CustomEvent('dictate', {
            detail: { text },
            bubbles: true,
            composed: true
        }));
        // Keep the panel open with the text intact so the user can see what
        // was sent. They can edit and re-Apply if mappings need correction.
    }

    handleClear() {
        this.transcriptText = '';
    }
}
