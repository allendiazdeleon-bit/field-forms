import { LightningElement, api } from 'lwc';

export default class NeuraMobileButton extends LightningElement {
    @api title;
    @api variant; // options are brand, neutral, success, destructive
    @api size; // options are stretch, small

    handleClick() {
        console.log('Button clicked: ' + this.title);
        const selectedEvent = new CustomEvent('buttonclick', { detail: this.title });
        this.dispatchEvent(selectedEvent);
    }

    get buttonClass(){
        return 'neura-mobile-button ' + this.variantClass + this.sizeClass;
    }

    get variantClass(){
        return ' neura-mobile-button-' + this.variant;
    }

    get sizeClass(){
        return (this.size === 'stretch') ? ' neura-mobile-button-stretch' : ' neura-mobile-button-small';
    }

    

}