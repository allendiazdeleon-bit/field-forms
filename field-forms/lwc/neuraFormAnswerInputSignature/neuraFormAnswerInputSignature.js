import { LightningElement, api, track } from 'lwc';

export default class NeuraFormAnswerInputSignature extends LightningElement {
    @api get filesData() {
        return this._filesData;
    }
    set filesData(value) {
        this._filesData = [...value];
    }

    @track _filesData;

    // Internal step state. Composed into a single 'isSheetOpen' getter
    // so the bottom-sheet template binding stays simple.
    showOption = false;       // Type/Draw chooser is visible (step 1)
    showSignature = false;    // Active capture surface is visible (step 2)
    showTypeSignature = false;

    handleshowOption() {
        this.showOption = true;
    }

    handleTypeSignature() {
        this.showSignature = true;
        this.showTypeSignature = true;
    }

    handleDrawSignature() {
        this.showSignature = true;
        this.showTypeSignature = false;
    }

    handleDoneSignature({ detail }) {
        this._filesData = [...detail.value];
        // Capture succeeded — collapse all the sheet-driving state so the
        // sheet closes and the next interaction starts fresh.
        this._resetSheetState();
    }

    handleCancel() {
        this._resetSheetState();
    }

    handleChangeType() {
        this.showSignature = false;
    }

    // Bottom-sheet wired this up to all dismiss paths (scrim tap, drag,
    // escape). We treat any of those as "cancel" — the capture component
    // is stateful (canvas pixels, typed text), and the safest UX is to
    // drop the in-flight signature rather than silently keep it around.
    handleSheetClose() {
        this._resetSheetState();
    }

    _resetSheetState() {
        this.showSignature = false;
        this.showOption = false;
        this.showTypeSignature = false;
    }

    // The sheet is open whenever the user has started the capture flow —
    // either picking Type/Draw or actively signing.
    get isSheetOpen() {
        return this.showOption || this.showSignature;
    }

    get sheetHeading() {
        if (this.showSignature) {
            return this.showTypeSignature ? 'Type signature' : 'Draw signature';
        }
        return 'Capture signature';
    }

    get existingSignature() {
        if (this._filesData && this._filesData.length) {
            return this._filesData[0].data;
        }
        return false;
    }
}
