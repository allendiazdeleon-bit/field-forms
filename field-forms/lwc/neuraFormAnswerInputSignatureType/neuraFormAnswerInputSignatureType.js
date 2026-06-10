import { LightningElement, api } from 'lwc';
import LightningConfirm from "lightning/confirm";

const PEN_COLOR = "#000000";
const LINE_WIDTH = 1.5;
// Must match the @font-face family in this component's CSS exactly —
// "GreatVibes-Regular" (the file name) silently falls back to the
// default canvas font.
const TYPED_FONT = '30px "Great Vibes", cursive';

export default class neuraFormAnswerInputSignatureType extends LightningElement {
    @api signaturetype;
    @api headerText = 'To process with current application process, sign and upload it';

    name;

    // Canvas refs and stroke coordinates are per-instance: two signature
    // questions on one page each get their own surface (module-level
    // refs made every instance draw on whichever canvas rendered last).
    _canvas;
    _ctx;
    _eventsBound = false;
    _isMousePressed = false;
    _prevX = 0;
    _currX = 0;
    _prevY = 0;
    _currY = 0;

    addEvents() {
        if (!this.signaturetype && !this._eventsBound) {
            // Bound once per instance — renderedCallback fires repeatedly
            // and freshly-bound duplicates can't be removed later.
            this._eventsBound = true;
            this._canvas.addEventListener('mousemove', this.handleMouseMove.bind(this));
            this._canvas.addEventListener('mousedown', this.handleMouseDown.bind(this));
            this._canvas.addEventListener('mouseup', this.handleMouseUp.bind(this));
            this._canvas.addEventListener('mouseout', this.handleMouseOut.bind(this));
            this._canvas.addEventListener("touchstart", this.handleTouchStart.bind(this));
            this._canvas.addEventListener("touchmove", this.handleTouchMove.bind(this));
            this._canvas.addEventListener("touchend", this.handleTouchEnd.bind(this));
        }
    }

    handleMouseMove(event) {
        if (this._isMousePressed) {
            this.setupCoordinate(event);
            this.redraw();
        }
    }

    handleMouseDown(event) {
        event.preventDefault();
        this.setupCoordinate(event);
        this._isMousePressed = true;
        this.drawDot();
    }

    handleMouseUp() {
        this._isMousePressed = false;
    }

    handleMouseOut() {
        this._isMousePressed = false;
    }

    handleTouchStart(event) {
        event.preventDefault();
        if (event.targetTouches.length === 1) {
            this.setupCoordinate(event.targetTouches[0]);
        }
    }

    handleTouchMove(event) {
        // Prevent scrolling while signing.
        event.preventDefault();
        if (event.targetTouches.length === 1) {
            this.setupCoordinate(event.targetTouches[0]);
            this.redraw();
        }
    }

    handleTouchEnd(event) {
        event.preventDefault();
        this.setupCoordinate(event.changedTouches[0]);
        this.redraw();
    }

    renderedCallback() {
        const canvas = this.template.querySelector('canvas');
        if (!canvas) return;
        if (canvas !== this._canvas) {
            this._canvas = canvas;
            this._ctx = canvas.getContext("2d");
            this._ctx.lineCap = 'round';
            this._eventsBound = false;
        }
        this.addEvents();
    }

    signIt(e) {
        const signText = e.detail.value;
        this.name = signText;
        // Repaint from scratch on every keystroke — fillText composites
        // over the previous paint, so without the clear "J/Jo/Joh/John"
        // stack into a smear that ends up in the saved PNG.
        this._ctx.clearRect(0, 0, this._canvas.width, this._canvas.height);
        if (!signText) return;
        this._ctx.fillStyle = PEN_COLOR;
        this._ctx.font = TYPED_FONT;
        this._ctx.fillText(signText, 30, this._canvas.height / 2);
    }

    async handleDoneClick() {
        const result = await LightningConfirm.open({
            message: "Signature can not be edited once done.",
            variant: "header",
            label: "Do you want to proceed?",
            theme: "success"
        });

        if (result === true) {
            const filesData = [
                {
                    data: this._canvas.toDataURL("image/png"),
                    metadata: {
                        fileName: 'sign',
                        ext: 'png'
                    },
                    description: 'E-Sign',
                    editedImageInfo: {}
                }
            ];
            this.dispatchEvent(new CustomEvent('donesignature', {
                detail: {
                    value: filesData
                },
                bubbles: true,
                composed: true
            }));
        }
    }

    handleClearClick() {
        this.name = '';
        this._ctx.clearRect(0, 0, this._canvas.width, this._canvas.height);
    }

    setupCoordinate(eventParam) {
        const clientRect = this._canvas.getBoundingClientRect();
        // The canvas drawing buffer (canvas.width/height) is rarely the
        // same as its rendered CSS size, so a raw clientX/clientY offset lands
        // the pen away from the finger. Scale the pointer position by the
        // buffer-to-display ratio so the stroke tracks the touch point. (Ratio
        // is 1 when sizes already match, so this is a safe no-op in that case.)
        const scaleX = clientRect.width ? this._canvas.width / clientRect.width : 1;
        const scaleY = clientRect.height ? this._canvas.height / clientRect.height : 1;
        this._prevX = this._currX;
        this._prevY = this._currY;
        this._currX = (eventParam.clientX - clientRect.left) * scaleX;
        this._currY = (eventParam.clientY - clientRect.top) * scaleY;
    }

    redraw() {
        this._ctx.beginPath();
        this._ctx.moveTo(this._prevX, this._prevY);
        this._ctx.lineTo(this._currX, this._currY);
        this._ctx.strokeStyle = PEN_COLOR;
        this._ctx.lineWidth = LINE_WIDTH;
        this._ctx.closePath();
        this._ctx.stroke();
    }

    drawDot() {
        this._ctx.beginPath();
        this._ctx.fillStyle = PEN_COLOR;
        this._ctx.fillRect(this._currX, this._currY, LINE_WIDTH, LINE_WIDTH);
        this._ctx.closePath();
    }

    handleCancelClick() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleChangeTypeClick() {
        this.dispatchEvent(new CustomEvent('changetype'));
    }
}
