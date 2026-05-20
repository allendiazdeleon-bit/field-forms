import { LightningElement, api } from 'lwc';
const COLORMAP = {
    'Not Started': '#7699AE',
    'In Progress': '#0075BD',
    'Completed': '#3D8D36'
};
export default class NeuraFormSelectorItem extends LightningElement {
    @api form;

    renderedCallback() {
        var css = this.template.host.style;
        css.setProperty('--tile-bg-color', this.standardColor);
        css.setProperty('--progress-bar-width', this.progressWidth);
        css.setProperty('--element-left-position', this.progressBar);
    }
    get progressText(){
        return this.isComplete ? '✓  ' + this.form.progress : this.form.progress;
    }
    get remainingClass(){
        return this.isNotStarted ? 'progress-text-center' : 'hide-element';
    }
    
    get progressClass(){
        return !this.isNotStarted ? this.alignmentClass : 'hide-element';
    }


    get alignmentClass(){
        return this.isInProgress ? 'progress-text-right' : 'progress-text-center';
    }

    get color(){
        return this.form.color ?? '#303641';
    }

    get standardColor(){
        return COLORMAP[this.form.status] ?? this.color;
    }

    get progressWidth(){
        return this.form.progress ?? '0%';
    }

    get progressBar(){
        return 'calc(' + this.form.progress + ' - 30px)';
    }

    get isNotStarted(){
        return this.form.status === 'Not Started';
    }

    get isInProgress(){
        return this.form.status === 'In Progress';
    }

    get isComplete(){
        return this.form.status === 'Completed';
    }

    get progressTextClass(){
        return this.form.inProgress ? 'progress-bar-text' : '';
    }

    handleClick() {
        const selectedFormId = this.form.id
        console.log('Selected Form:', selectedFormId);

        // Send Event to parent component
        const customEvent = new CustomEvent('formselected', { 
            bubbles: true,
            composed: true,
            detail: selectedFormId });
        this.dispatchEvent(customEvent);
        // Additional logic for form selection can be added here
    }
}