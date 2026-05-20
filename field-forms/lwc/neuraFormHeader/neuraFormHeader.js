import { LightningElement,api } from 'lwc';

export default class NeuraFormHeader extends LightningElement {
    @api indicatorType;
    @api stepList; // array of steps
    @api currentStep; // value from stepList that is active
    @api currentStepPercentage;
    @api currentStepIndex;
    @api totalSteps;

    get showRightText(){
        return this.indicatorType === 'Ring';
    }
    
    get isNextStep(){
        console.log('currentStepIndex: ' + this.currentStepIndex);
        console.log('totalSteps: ' + this.totalSteps);
        return this.currentStepIndex < this.totalSteps - 1;
    }

    get nextStep(){
        if(this.isNextStep){
            return this.stepList[this.currentStepIndex + 1];
        }
    }

}