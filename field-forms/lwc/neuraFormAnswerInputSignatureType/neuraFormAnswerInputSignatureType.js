import { LightningElement,api } from 'lwc';
import LightningConfirm from "lightning/confirm";

let isMousePressed, 
    isDotFlag = false,
    prevX = 0,
    currX = 0,
    prevY = 0,
    currY = 0;            
       
let penColor = "#000000"; 
let lineWidth = 1.5;     

let canvasElement, ctx;

export default class neuraFormAnswerInputSignatureType extends LightningElement {    
    @api signaturetype ;
    @api headerText='To process with current application process, sign and upload it';

    name;

    addEvents() {
        if(!this.signaturetype) {
            canvasElement.addEventListener('mousemove', this.handleMouseMove.bind(this));
            canvasElement.addEventListener('mousedown', this.handleMouseDown.bind(this));
            canvasElement.addEventListener('mouseup', this.handleMouseUp.bind(this));
            canvasElement.addEventListener('mouseout', this.handleMouseOut.bind(this));
            canvasElement.addEventListener("touchstart", this.handleTouchStart.bind(this));
            canvasElement.addEventListener("touchmove", this.handleTouchMove.bind(this));
            canvasElement.addEventListener("touchend", this.handleTouchEnd.bind(this));
        }
    }

    handleMouseMove(event){
        if (isMousePressed) {
            this.setupCoordinate(event);
            this.redraw();
        }     
    }    
    
    handleMouseDown(event){
        event.preventDefault();
        this.setupCoordinate(event);           
        isMousePressed = true;
        isDotFlag = true;
        if (isDotFlag) {
            this.drawDot();
            isDotFlag = false;
        }     
    }    

    handleMouseUp(event){
        isMousePressed = false;      
    }

    handleMouseOut(event){
        isMousePressed = false;      
    }

    handleTouchStart(event) {
        // if (event.targetTouches.length == 1) {
        //     this.setupCoordinate(event);     
        // }
        event.preventDefault();
        if (event.targetTouches.length === 1) {
            this.setupCoordinate(event.targetTouches[0]);
        }
    };

    handleTouchMove(event) {
        /* Prevent scrolling.
        event.preventDefault();
        this.setupCoordinate(event);
        this.redraw();*/
        event.preventDefault();
        if (event.targetTouches.length === 1) {
            this.setupCoordinate(event.targetTouches[0]);
            this.redraw();
        }
    };

    handleTouchEnd(event) {
       /* var wasCanvasTouched = event.target === canvasElement;
        if (wasCanvasTouched) {
            event.preventDefault();
            this.setupCoordinate(event);
            this.redraw();
        }*/
        event.preventDefault();
        this.setupCoordinate(event.changedTouches[0]);
        this.redraw();
    };

    renderedCallback() {
        canvasElement = this.template.querySelector('canvas');
        ctx = canvasElement.getContext("2d");
        ctx.lineCap = 'round';
        this.addEvents();
    }

    signIt(e) {
        var signText = e.detail.value;
        this.name = signText;
        ctx.font = "30px GreatVibes-Regular";
        ctx.fillText(signText, 30, canvasElement.height/2);
    }

    async handleDoneClick() {
        const result = await LightningConfirm.open({
            message: "Signature can not be edited once done.",
            variant: "header",
            label: "Do you want to proceed?",
            theme: "success"
        });

        if(result === true) {
            const filesData = [
                {
                    data: canvasElement.toDataURL("image/png"),
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

    handleClearClick(){
        this.name = '';
        ctx.clearRect(0, 0, canvasElement.width, canvasElement.height);
    }

    setupCoordinate(eventParam){
        const clientRect = canvasElement.getBoundingClientRect();
        prevX = currX;
        prevY = currY;
        currX = eventParam.clientX -  clientRect.left;
        currY = eventParam.clientY - clientRect.top;
    }

    redraw() {
        ctx.beginPath();
        ctx.moveTo(prevX, prevY);
        ctx.lineTo(currX, currY);
        ctx.strokeStyle = penColor;
        ctx.lineWidth = lineWidth;        
        ctx.closePath(); 
        ctx.stroke(); 
    }

    drawDot(){
        ctx.beginPath();
        ctx.fillStyle = penColor;
        ctx.fillRect(currX, currY, lineWidth, lineWidth); 
        ctx.closePath();
    }

    handleCancelClick() {
        this.dispatchEvent(new CustomEvent('cancel'));
    }

    handleChangeTypeClick() {
        this.dispatchEvent(new CustomEvent('changetype'));
    }
}