import { LightningElement, api } from 'lwc';

/**
 * Small reusable mic-button that uses the browser's Web Speech API to
 * append the user's spoken words to a parent input. Dispatches a
 * `transcript` event with the final phrase when recognition ends.
 *
 * On platforms without SpeechRecognition (most mobile WebViews), the
 * mic icon hides itself - mobile users rely on the OS keyboard's
 * built-in mic instead.
 *
 * Why no Nimbus speech plugin? lightning/mobileCapabilities exposes
 * barcode / location / NFC / camera / etc., but does not include a
 * built-in speech-to-text service. Adding mobile STT would require
 * lightning/mobileCapabilities.getRecordingService + Apex callout to
 * a transcription provider - out of scope for this slice.
 */
export default class NeuraVoiceCapture extends LightningElement {
    @api ariaLabel = 'Voice input';
    @api disabled = false;

    isListening = false;
    _recognition;

    get isSupported() {
        return typeof window !== 'undefined' &&
            (window.SpeechRecognition || window.webkitSpeechRecognition);
    }

    get iconName() {
        return this.isListening ? 'utility:stop' : 'utility:unmuted';
    }

    get title() {
        return this.isListening ? 'Stop voice input' : 'Start voice input';
    }

    get buttonVariant() {
        return this.isListening ? 'brand' : 'border';
    }

    handleClick(event) {
        event.preventDefault();
        event.stopPropagation();
        if (this.disabled || !this.isSupported) return;
        if (this.isListening) {
            this.stopListening();
        } else {
            this.startListening();
        }
    }

    startListening() {
        const Recognition = window.SpeechRecognition || window.webkitSpeechRecognition;
        if (!Recognition) return;

        try {
            this._recognition = new Recognition();
            // continuous=false: produce one result phrase then stop. Cleaner
            // UX for short-form answers than a streaming session the user has
            // to manually end.
            this._recognition.continuous = false;
            this._recognition.interimResults = false;
            this._recognition.lang = navigator.language || 'en-US';

            this._recognition.onresult = (e) => {
                const result = e.results && e.results[0] && e.results[0][0];
                if (result?.transcript) {
                    this.dispatchEvent(new CustomEvent('transcript', {
                        detail: { text: result.transcript.trim() },
                        bubbles: true,
                        composed: true
                    }));
                }
            };
            this._recognition.onerror = (e) => {
                this.dispatchEvent(new CustomEvent('voiceerror', {
                    detail: { error: e.error || 'unknown' },
                    bubbles: true,
                    composed: true
                }));
                this.isListening = false;
            };
            this._recognition.onend = () => {
                this.isListening = false;
            };

            this._recognition.start();
            this.isListening = true;
        } catch (e) {
            this.isListening = false;
            this.dispatchEvent(new CustomEvent('voiceerror', {
                detail: { error: e?.message || 'start-failed' },
                bubbles: true,
                composed: true
            }));
        }
    }

    stopListening() {
        try {
            this._recognition?.stop();
        } catch (e) {
            // Already stopped or never started; ignore.
        }
        this.isListening = false;
    }

    disconnectedCallback() {
        this.stopListening();
    }
}
