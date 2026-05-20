import { LightningElement, api } from 'lwc';

export default class NeuraFormSelector extends LightningElement {
    forms = [/*
        { id: 'form1', name: 'Form 1', status: 'In Progress', inProgress: true, progress: "30%", progressStyle: "left: calc(30% - 30px)", style: "width: 30%", class:  "slds-visual-picker slds-visual-picker_medium tile-progress tile-primary"},
        { id: 'form2', name: 'Form 2', status: 'Completed', progress: "100%", inProgress: false, style: "width: 100%", class: "slds-visual-picker slds-visual-picker_medium tile-progress tile-red" },
        { id: 'form3', name: 'Form 3', status: 'Not Started', progress: "0%", inProgress: false, style: "width: 0%", class: "slds-visual-picker slds-visual-picker_medium tile-progress tile-blue" },
        { id: 'form4', name: 'Form 4', status: 'Not Started', progress: "0%", inProgress: false, style: "width: 0%", class: "slds-visual-picker slds-visual-picker_medium tile-progress tile-purple"},
        { id: 'form5', name: 'Form 5', status: 'Not Started', progress: "0%", inProgress: false, style: "width: 0%", class: "slds-visual-picker slds-visual-picker_medium tile-progress tile-pink" },
        { id: 'form6', name: 'Form 6', status: 'Not Started', progress: "0%", inProgress: false, style: "width: 0%", class: "slds-visual-picker slds-visual-picker_medium tile-progress tile-aqua" }
        */
    ];

    @api formOptions;

    connectedCallback() {
        this.initializeForms();
    }

    initializeForms() {
        // loop over formOptions and call determineProgress on each.
        this.forms = this.formOptions.map(form => {
            return this.determineProgress(form);
        })

    }

    determineProgress(form){
        let newForm = {...form};
        // determine progress
        if(form.status === 'In Progress'){
            newForm.inProgress = true;
            newForm.progress = Math.round((form.currentPage / form.totalPages) * 100) + '%';
        } else if (form.status === 'Completed'){
            newForm.inProgress = false;
            newForm.progress = '100%';
        } else {
            newForm.inProgress = false;
            newForm.progress = '0%';
        }

        console.log(JSON.stringify(newForm));
        return newForm;
    }


    handleClick(event) {
        const selectedFormId = event.currentTarget.dataset.id;
        console.log('Selected Form:', selectedFormId);

        // Send Event to parent component
        const customEvent = new CustomEvent('formselected', { detail: selectedFormId });
        this.dispatchEvent(customEvent);
        // Additional logic for form selection can be added here
    }

    isInProgress(status){
        return status === 'In Progress';
    }

    get progressBarStyle() {
        return `width: ${this.progress}%`;
    }

    
}