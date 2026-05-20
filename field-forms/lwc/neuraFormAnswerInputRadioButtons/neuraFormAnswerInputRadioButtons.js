import { LightningElement, track, api } from 'lwc';

export default class NeuraFormAnswerInputRadioButtons extends LightningElement {
    @track exampleRadioOptions = [
        { label: 'Good', value: 'Good', selected: false, class: '', icon: 'utility:like' },
        { label: 'Bad', value: 'Bad', selected: false, class: '', icon: 'utility:dislike' },
        { label: 'N/A', value: 'NA', selected: false, class: '', iconName: '' },
        { label: 'SC', value: 'SC', selected: false, class: '', iconName: '' }
    ];

    @track exampleRadioOptions2 = [
        { label: 'N/A', value: 'NA', selected: false, icon: '' },
        { label: 'A', value: 'A', selected: false, icon: '' },
        { label: 'B', value: 'B', selected: false, icon: '' },
        { label: 'C', value: 'C', selected: false, icon: '' },
        { label: 'OK', value: 'OK', selected: false, icon: '' }
    ];

    _radioOptions = [];

    @api
    get radioOptions() {
        return this._radioOptions;
    }
    set radioOptions(value) {
        this._radioOptions = this.calculateDynamicProperties(JSON.parse(value));
        this.updateRadio();
        this.updateLabelWidths();
    }

    @api 
    get val() {
        return this._val;
    }
    set val(value) {
        this._val = value;
        this.updateRadio();
    }

    _val; // internal private property to hold the value of val

    get sliderClass(){
        // return 'slider' if any option is selected or 'slider hidden' if no option is selected
        return this.radioOptions.some(option => option.selected) ? 'slider' : 'slider hidden';
    }



    connectedCallback() {
       // this.initializeRadioOptions(this.exampleRadioOptions2);
        //this.updateLabelWidths();
    }

    renderedCallback() {
        this.updateLabelWidths();
        this.updateSliderPosition();
    }

    initializeRadioOptions(options) {
        this._radioOptions = this.calculateDynamicProperties(options);
    }

    updateRadio() {
        console.log('val: ' + this._val);
        this._radioOptions = this.calculateDynamicProperties(
            this._radioOptions.map(option => ({
                ...option,
                selected: (option.value === this._val)
            }))
        );
        this.updateSliderPosition();
        this.updateLabelWidths(); // Ensuring label widths are updated too
    }

    calculateSliderWidth(numOptions) {
        if (numOptions > 0) {
            return `calc(${100 / numOptions}% + 8px)`;
        }
        return '0%'; // Default width in case of no options
    }

    updateSliderPosition() {
        const slider = this.template.querySelector('.slider');
        if (slider) {
            const selectedOption = this.radioOptions.find(option => option.selected);
            if (selectedOption) {
                // Update the CSS variable
                slider.style.setProperty('--slider-translate-x', selectedOption.dataLocation);
    
                // Update the slider width as necessary
                slider.style.width = this.calculateSliderWidth(this.radioOptions.length);
            }
        }
    }

    updateLabelWidths() {
        const numOptions = this.radioOptions.length;
        const labels = this.template.querySelectorAll('.radio-group-container label');
    
        if (labels.length > 0) {
            const labelWidth = `calc(${100 / numOptions}% - 1px)`;
            labels.forEach(label => {
                label.style.width = labelWidth;
            });
        }
    }

    handleRadioClick(event) {
        if (event.target.tagName.toLowerCase() === 'input') {
            this.val = event.target.value; // Assuming val's setter doesn't call updateRadio
            this.dispatchEvent(new CustomEvent('change', {
                detail: {
                    value: event.target.value
                }
            }))
        }
    }

    calculateDynamicProperties(options) {
        // if options is not an array then set it to an empty array
        if (!Array.isArray(options)) {
            options = [];
        }
        const numOptions = options.length;
        return options.map((option, index) => {
            // Calculate the position as a percentage
            const locationPercent = (index) * 100;
            const locationPixel = index > 0 ? (index) * 8 : 0;
            const newDataLocation = index == 0 ? `0` : `calc(${locationPercent}% - ${locationPixel}px)`;
            const optionClass = option.selected ? 'selected' : '';
            return { ...option, dataLocation: newDataLocation, class: optionClass };
        });
    }
}