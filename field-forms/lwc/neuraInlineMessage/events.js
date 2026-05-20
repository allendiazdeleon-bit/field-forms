const CloseEventName = 'close';

export class CloseEvent extends CustomEvent {
    constructor() {
        super(CloseEvent.type);
    }

    static get type() {
        return CloseEventName;
    }
}