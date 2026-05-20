import { LightningElement, api } from 'lwc';

export default class NeuraFormAnswerInputRatings extends LightningElement {
    _val

    @api
    get val(){
        return this._val;
    }

    set val(value){
        this._val = value;
        this.updateOptions();
    }

    _options = [];

    @api
    get options() {
        return this._options;
    }
    set options(value) {
        this._options = JSON.parse(value);
        this.updateOptions();
        console.log('options: ', this._options);
    }

    

    updateOptions(){
        // mark all values up to the selected value as selected

        this._options.map(option => ({
            ...option,
            selected: (option.value === this._val)
        }))
        
    }
}