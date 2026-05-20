import { LightningElement, api } from 'lwc';

export default class NeuraFormAnswerInputStarRating extends LightningElement {
    _options;

    @api
    set options(value){
        // reverse the order of values
        this._options = JSON.parse(value).reverse();
    }

    get options(){
        return this._options;
    }

    @api get val() {
        return this._val;
    } 
    set val(value) {
        this._val = value;

        const index = this._options.findIndex((item) => {
            return item.value === this._val
        });

        if(index != -1) {
            this._options[index] = {
                ...this._options[index],
                checked: true
            };
        }
    } 

    handleRatingClick(event) {
        this.dispatchEvent(new CustomEvent('change', {
            detail: {
                value: event.target.value
            }
        }));
    }
}