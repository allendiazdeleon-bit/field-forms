const ERROR_EVENT_NAME = 'error';

export class ErrorEvent extends CustomEvent {
    constructor(errors) {
        super(ErrorEvent.type, { detail: errors })
    } 

    static get type() {
        return ERROR_EVENT_NAME;
    }
}