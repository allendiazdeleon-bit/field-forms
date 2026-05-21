import { api, LightningElement } from 'lwc';

// Import custom labels
const DFP_Complete = 'Complete';
const DFP_Current = 'Current';
const DFP_Upcoming = 'Upcoming';

export default class NeuraFormProgress extends LightningElement {
    _indicatorType; // Vertical, Horizontal, Path, Bar, VertNav, or Ring
    @api
    get indicatorType() {
        return this._indicatorType;
    }

    set indicatorType(value) {
        this._indicatorType = value;
        this.updateProgressIndicator();
    }
   
    _stepList;
    @api
    get stepList() {
        return this._stepList;
    }

    set stepList(value) {
        this._stepList = value;
        this.updateProgressIndicator();
    }

    _currentStep;
    @api
    get currentStep() {
        return this._currentStep;
    }

    set currentStep(value) {
        this._currentStep = value;
        this.updateProgressIndicator();
    }
    @api currentStepPercentage; // currentStepPercentage (optional)

    _currentStepIndex;
    @api
    get currentStepIndex() {
        return this._currentStepIndex;
    }

    set currentStepIndex(value) {
        this._currentStepIndex = value;
        this.updateProgressIndicator();
    }

    _totalSteps;
    @api
    get totalSteps() {
        return this._totalSteps;
    }

    set totalSteps(value) {
        this._totalSteps = value;
        this.updateProgressIndicator();
    }


    // Expose the labels to use in the template
    label = {
        DFP_Complete,
        DFP_Current,
        DFP_Upcoming
    };

    showTypeVertical;
    showTypeVertNav;
    showTypeHorizontal;
    showTypePath;
    showTypeBar;
    showTypeRing;

    stepsArray;
    pathProgress;

    stepPercent;
    countTotalSteps;
    countToCurrent;

    progressLabel;
    
    removeShowTypes(){
        this.showTypeVertical = false;
        this.showTypeVertNav = false;
        this.showTypeHorizontal = false;
        this.showTypePath = false;
        this.showTypeBar = false;
        this.showTypeRing = false;
    }
    
    updateProgressIndicator() {
          if(!this.stepList || !this.currentStep) {
                return;
          }

          // Form_Template.Indicator_Type__c can be null (admin never picked
          // one); the switch below has a "default" branch that handles unknown
          // types, so just fall through to '' here instead of throwing.
          const indicatorDirty = this.indicatorType || '';
          const indicatorClean = String(indicatorDirty).trim().toLowerCase();
          let considerCurrentStepPercentage = false;
  
          // set conditions for which indicator type displays
          this.removeShowTypes();
          switch (indicatorClean) {
              case 'vertical':
                  this.showTypeVertical = true;
                  break;
              case 'vertnav':
                  this.showTypeVertNav = true;
                  break;
              case 'horizontal':
                  this.showTypeHorizontal = true;
                  break;
              case 'path':
                  this.showTypePath = true;
                  break;
              case 'bar':
                  this.showTypeBar = true;
                  considerCurrentStepPercentage = true;
                  break;
              case 'ring':
                  this.showTypeRing = true;
                  considerCurrentStepPercentage = true;
                  break;
              default:
                  this.showTypeHorizontal = true;
                  break;
          }
          
          // convert stepList from string of comma-separated values to an array
          const stepListArray = this.stepList;
  
          let countTotalSteps = stepListArray.length;
          let stepsArrayTemp = [];
          let afterCurrent = false;
          let countToCurrent = 0;
          let currentCount = 0;
  
          for (let i = 0; i < stepListArray.length; i++) {
              currentCount = i+1;
  
              let isFinalStep = false;
              if(currentCount == countTotalSteps){
                  isFinalStep = true;
              }
              
              let cleanArrayValue = String(stepListArray[i] || '').trim();
              
              if(afterCurrent == false) {
                  
                  // this step might be Completed or Current
                  if(cleanArrayValue == this.currentStep) {
                      
                      if(isFinalStep == true) {
                          switch (indicatorClean) {
                              case 'vertical':
                                  // this is the final step for the vertnav indicator type, but it needs to be display as Current
                                  stepsArrayTemp.push({
                                      'label': cleanArrayValue,
                                      'status': 'Complete',
                                      'showCurrent' : false,
                                      'showComplete' : false,
                                      'showFinalComplete' : true,
                                      'showUpcoming' : false,
                                      'finalStep' : true
                                  });
                                  break;
                              case 'vertnav':
                                  // this is the final step for the vertnav indicator type, but it needs to be display as Current
                                  stepsArrayTemp.push({
                                      'label': cleanArrayValue,
                                      'status': 'Complete',
                                      'showCurrent' : false,
                                      'showComplete' : false,
                                      'showFinalComplete' : true,
                                      'showUpcoming' : false,
                                      'finalStep' : true
                                  });
                                  break;
                              default:
                                  // this is the current step, but since it is the final one, it is marked as Complete instead
                                  stepsArrayTemp.push({
                                      'label': cleanArrayValue,
                                      'status': 'Complete',
                                      'showCurrent' : false,
                                      'showComplete' : true,
                                      'showFinalComplete' : false,
                                      'showUpcoming' : false,
                                      'finalStep' : true
                                  });
                                  break;
                          }
  
                          countToCurrent++;
                      }
                      else {
  
                          // this is the current step, but it is not the final one (or it's the final one for the vertnav indicator type)
                          stepsArrayTemp.push({
                              'label': cleanArrayValue,
                              'status': 'Current',
                              'showCurrent' : true,
                              'showComplete' : false,
                              'showUpcoming' : false,
                              'finalStep' : false
                          });
                          
                          // set afterCurrent to true,
                          // so all subsequent steps
                          // are marked as future
                          afterCurrent = 'true';
                          countToCurrent++;
                      }
                  }
                  else {
                      
                      // this is a completed step
                      stepsArrayTemp.push({
                          'label': cleanArrayValue,
                          'status': 'Complete',
                          'showCurrent' : false,
                          'showComplete' : true,
                          'showUpcoming' : false,
                          'finalStep' : isFinalStep
                      });
                      countToCurrent++;
                  }
              }
              else {
                  
                  // this is an upcoming step
                  stepsArrayTemp.push({
                      'label': cleanArrayValue,
                      'status': 'Upcoming',
                      'showCurrent' : false,
                      'showComplete' : false,
                      'showUpcoming' : true,
                      'finalStep' : false
                  });
              }
          }
          
          // this.countToCurrent = countToCurrent;
          // this.countTotalSteps = countTotalSteps;
  
          // set pathProgress to number of steps unless currentStepPercentage is set
          if(considerCurrentStepPercentage == true) {
                let currentStepNum = this.currentStepIndex + 1;
              let percentProperty = (currentStepNum / this.totalSteps) * 100;
              //console.log('currentStepNum: ' + currentStepNum);
              //  console.log('totalSteps: ' + this.totalSteps);
             // console.log('percentProperty: ' + percentProperty);
              if(percentProperty > 0) {
                  this.pathProgress = percentProperty;
  
                  this.stepPercent = percentProperty;
  
                  let testPercent = percentProperty;
  
                  // need a label property for the Bar indicator type that shows completion like "45% Complete"
                  this.progressLabel =`${currentStepNum} of ${this.totalSteps}`;
  
                  // setting dynamic css width value for the Bar and Ring indicator types
                  document.documentElement.style.setProperty('--value', percentProperty);
                  document.documentElement.style.setProperty('--progress-text', `"${this.progressLabel}"`);
              }
  
              else {
                  this.pathProgress = (((countToCurrent-1)/(countTotalSteps-1)*100));
  
                  // need a label property for the Bar indicator type that shows completion like "1 of 5"
  
                  this.progressLabel =`${currentStepNum} of ${this.totalSteps}`;
                    
                  // setting dynamic css width value for the Bar and Ring indicator types
                  document.documentElement.style.setProperty('--value', percentProperty);
                  document.documentElement.style.setProperty('--progress-text', `"${this.progressLabel}"`);
              }
          }
  
          // indicator type is not a bar or ring
          else {
                let currentStepNum = this.currentStepIndex + 1;
              let percentProperty = (currentStepNum / this.totalSteps) * 100;

              this.pathProgress = (((countToCurrent-1)/(countTotalSteps-1)*100));
  
              // need a label property for the Horizontal indicator type that shows completion like "45% Complete"
              this.progressLabel =`${currentStepNum} of ${this.totalSteps}`;
              
              // setting dynamic css width value for the Horizontal indicator type
              document.documentElement.style.setProperty('--value', percentProperty);
              document.documentElement.style.setProperty('--progress-text', `"${this.progressLabel}"`);
          }
  
          // store list of steps to iterate over in the html
          this.stepsArray = stepsArrayTemp;
      
    }

    connectedCallback(){
        this.updateProgressIndicator();
    }
      
}