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
        });
    }

    // First in-progress form gets pinned to a "Resume" hero card above the
    // list. Common field-service pattern: techs almost always have one
    // active form they're returning to, and showing it as a primary CTA
    // beats making them scan the list to find it.
    get resumeForm() {
        return (this.forms || []).find((f) => f.inProgress) || null;
    }

    get hasResumeForm() {
        return !!this.resumeForm;
    }

    // The non-resume forms render in the list below the hero card.
    get otherForms() {
        const resumeId = this.resumeForm?.id;
        return (this.forms || []).filter((f) => f.id !== resumeId);
    }

    determineProgress(form){
        let newForm = {...form};
        // determine progress
        if(form.status === 'In Progress'){
            newForm.inProgress = true;
            newForm.isComplete = false;
            newForm.isNotStarted = false;
            newForm.progressPct = form.totalPages
                ? Math.round((form.currentPage / form.totalPages) * 100)
                : 0;
            newForm.progress = newForm.progressPct + '%';
            newForm.progressBarStyle = 'width: ' + newForm.progressPct + '%';
            newForm.statusPillClass = 'status-pill status-pill_inprogress';
            newForm.statusIcon = 'utility:pause';
        } else if (form.status === 'Completed' || form.status === 'Complete') {
            newForm.inProgress = false;
            newForm.isComplete = true;
            newForm.isNotStarted = false;
            newForm.progressPct = 100;
            newForm.progress = '100%';
            newForm.progressBarStyle = 'width: 100%';
            newForm.statusPillClass = 'status-pill status-pill_complete';
            newForm.statusIcon = 'utility:check';
        } else {
            newForm.inProgress = false;
            newForm.isComplete = false;
            newForm.isNotStarted = true;
            newForm.progressPct = 0;
            newForm.progress = '0%';
            newForm.progressBarStyle = 'width: 0%';
            newForm.statusPillClass = 'status-pill status-pill_notstarted';
            newForm.statusIcon = 'utility:dash';
        }
        newForm.detailLine = form.totalPages
            ? `Step ${form.currentPage || 0} of ${form.totalPages}`
            : form.status;
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