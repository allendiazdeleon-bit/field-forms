import {
    parentFieldForHost,
    formatPrefillSuccessMessage,
    PREFILL_MESSAGES
} from '../prefillController';

describe('prefillController.parentFieldForHost', () => {
    it('returns the right lookup field for each supported host', () => {
        expect(parentFieldForHost('WorkOrder')).toBe('Work_Order__c');
        expect(parentFieldForHost('WorkOrderLineItem')).toBe('Work_Order_Line_Item__c');
        expect(parentFieldForHost('ServiceAppointment')).toBe('Service_Appointment__c');
    });

    it('returns null for unknown / unsupported hosts', () => {
        expect(parentFieldForHost('Account')).toBeNull();
        expect(parentFieldForHost('')).toBeNull();
        expect(parentFieldForHost(undefined)).toBeNull();
        expect(parentFieldForHost(null)).toBeNull();
    });
});

describe('prefillController.formatPrefillSuccessMessage', () => {
    it('uses singular "answer" for one', () => {
        expect(formatPrefillSuccessMessage(1)).toBe(
            'Copied 1 answer from the last visit. Review and adjust.'
        );
    });

    it('uses plural "answers" for zero or many', () => {
        expect(formatPrefillSuccessMessage(0)).toBe(
            'Copied 0 answers from the last visit. Review and adjust.'
        );
        expect(formatPrefillSuccessMessage(42)).toBe(
            'Copied 42 answers from the last visit. Review and adjust.'
        );
    });

    it('coerces non-numeric input safely', () => {
        expect(formatPrefillSuccessMessage('3')).toBe(
            'Copied 3 answers from the last visit. Review and adjust.'
        );
        expect(formatPrefillSuccessMessage(null)).toBe(
            'Copied 0 answers from the last visit. Review and adjust.'
        );
    });
});

describe('prefillController.PREFILL_MESSAGES', () => {
    it('exposes the static toast strings', () => {
        expect(PREFILL_MESSAGES.MISSING_CONTEXT).toMatch(/host record context/i);
        expect(PREFILL_MESSAGES.NO_PRIOR_FOUND).toMatch(/no prior completed visit/i);
    });

    it('is frozen so callers cannot accidentally mutate the strings', () => {
        expect(Object.isFrozen(PREFILL_MESSAGES)).toBe(true);
    });
});
