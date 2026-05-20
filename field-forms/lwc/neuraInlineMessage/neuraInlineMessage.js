import { LightningElement, api } from 'lwc';
import { CloseEvent } from './events';

export default class NeuraInlineMessage extends LightningElement {
    @api message;

    @api variant;

    @api closable;

    handleCloseClick() {
        this.dispatchEvent(new CloseEvent());
    }

    get altText() {
        return this.variant === 'error' ? 'Error' : this.variant === 'warning' ? 'Warning' : 'Info';
    }

    get iconName() {
        return this.variant === 'error' ? 'utility:error' 
            : this.variant === 'warning' ? 'utility:warning' 
            : 'utility:info_alt';
    }

    get alertClass() {
        return this.variant === 'error' ? 'slds-notify slds-notify_alert slds-alert_error' 
        : this.variant === 'warning' ? 'slds-notify slds-notify_alert slds-alert_warning' 
        : 'slds-notify slds-notify_alert';
    }
}