import { LightningElement, api } from 'lwc';

export default class NeuraFormAnswerPrimMultiSelectItem extends LightningElement {
    @api item;
    @api selected;

    get itemClass() {
      return `slds-listbox__item ${this.selected ? 'slds-is-selected' : ''}`;
    }
  
    handleClick() {
      this.dispatchEvent(
        new CustomEvent('change', {
          detail: { item: this.item, selected: !this.selected }
        })
      );
    }

    connectedCallback() {
        console.log('NeuraFormAnswerPrimMultiSelectItem connectedCallback');
        console.log('item: ' + JSON.stringify(this.item));
        console.log('selected: ' + this.selected);
    }
}