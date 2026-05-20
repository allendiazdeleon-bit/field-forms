import { LightningElement, api } from 'lwc';

export default class NeuraFormAnswerInputRatingsItem extends LightningElement {
    @api option; 

    defaultClasses = 'number-ratings';

    get classList(){
        return this.option.selected ? this.defaultClasses + ' checked color1' : 'color2';
    }

    get value(){
        return this.option.value ?? '';
    }

    handleClick(){
        this.dispatchEvent(new CustomEvent('optionselected', {detail: this.option}));
    }
}