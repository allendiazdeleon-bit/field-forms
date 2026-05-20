/**
 * @description A custom Neuraflash-branded spinner component.
 * @module c-neuraflash-spinner
 */

import { LightningElement, api, track } from 'lwc';

const SIZES = {
    small: 0.5,
    medium: 1,
    large: 1.5
}

export default class NeuraflashSpinner extends LightningElement {

    /**
     * @description The message to be displayed alongside the spinner.
     * @type {string}
     * @public
     */
    @api message;

    /**
     * @description The size of the spinner. Possible values are 'small', 'medium', or 'large'.
     * @type {string}
     * @default medium
     * @public
     */
    @api size = 'medium';
    @track _size;

    get containerStyle() {
        this._size = SIZES[this.size];
        return `--size: ${this._size}`;
    }
}