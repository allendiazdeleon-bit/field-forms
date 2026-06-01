import { createElement } from 'lwc';
import NeuraFormBuilderAttributes from 'c/neuraFormBuilderAttributes';
import LightningConfirm from 'lightning/confirm';

/**
 * Scope of this file: Wave 35.9b "Use this catalog entry" adoption
 * handler. The component does a lot more than this, but the broader
 * attribute-rendering behavior is exercised in the form builder's
 * own tests; here we narrow to handleUseCatalogEntry and its event
 * contract with the similarity panel child.
 *
 * getAllAttributes is wired at construction. We mock it to resolve
 * with an empty list so the component mounts cleanly without
 * triggering rendering of attribute groups we don't care about.
 */
jest.mock(
    '@salesforce/apex/neuraFormBuilderController.getAllAttributes',
    () => ({ default: jest.fn().mockResolvedValue([]) }),
    { virtual: true }
);

jest.mock(
    'lightning/confirm',
    () => ({ open: jest.fn() }),
    { virtual: true }
);

function mount(selection) {
    const el = createElement('c-neura-form-builder-attributes', {
        is: NeuraFormBuilderAttributes
    });
    el.selection = selection;
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    LightningConfirm.open.mockReset();
});

function makeSelection({ type = 'Currency', catalogId = 'a01OLDCATALOGXX1' } = {}) {
    return {
        id: '0001',
        type: 'Currency',
        attributes: {
            Type__c: type,
            Question__c: 'How much?',
            Form_Question_Catalog__c: catalogId,
            _exclusiveCatalogEntry: true
        }
    };
}

describe('handleUseCatalogEntry — same-type adoption', () => {
    test('dispatches one update event patching Form_Question_Catalog__c and _exclusiveCatalogEntry', async () => {
        const el = mount(makeSelection({ type: 'Currency' }));
        const handler = jest.fn();
        el.addEventListener('update', handler);

        await el.handleUseCatalogEntry({
            detail: {
                catalogId: 'a01NEWCATALOGXX2',
                type: 'Currency',
                questionText: 'Adopted text'
            }
        });

        expect(LightningConfirm.open).not.toHaveBeenCalled();
        expect(handler).toHaveBeenCalledTimes(1);
        const detail = handler.mock.calls[0][0].detail;
        expect(detail.newSelection.attributes.Form_Question_Catalog__c).toBe(
            'a01NEWCATALOGXX2'
        );
        expect(detail.newSelection.attributes._exclusiveCatalogEntry).toBe(false);
        expect(detail.editedField).toEqual({
            field: 'Form_Question_Catalog__c',
            previousValue: 'a01OLDCATALOGXX1',
            newValue: 'a01NEWCATALOGXX2'
        });
    });

    test('ignores events with no catalogId', async () => {
        const el = mount(makeSelection());
        const handler = jest.fn();
        el.addEventListener('update', handler);

        await el.handleUseCatalogEntry({ detail: {} });

        expect(handler).not.toHaveBeenCalled();
        expect(LightningConfirm.open).not.toHaveBeenCalled();
    });
});

describe('handleUseCatalogEntry — type-mismatch confirm', () => {
    test('shows confirm dialog when types differ; abort on cancel', async () => {
        LightningConfirm.open.mockResolvedValue(false);
        const el = mount(makeSelection({ type: 'Currency' }));
        const handler = jest.fn();
        el.addEventListener('update', handler);

        await el.handleUseCatalogEntry({
            detail: {
                catalogId: 'a01NEWCATALOGXX2',
                type: 'Date',
                questionText: 'When?'
            }
        });

        expect(LightningConfirm.open).toHaveBeenCalledTimes(1);
        const args = LightningConfirm.open.mock.calls[0][0];
        // The user-visible message names both types so they understand
        // what's about to change.
        expect(args.message).toContain('Date');
        expect(args.message).toContain('Currency');
        expect(handler).not.toHaveBeenCalled();
    });

    test('shows confirm dialog when types differ; proceed on accept', async () => {
        LightningConfirm.open.mockResolvedValue(true);
        const el = mount(makeSelection({ type: 'Currency' }));
        const handler = jest.fn();
        el.addEventListener('update', handler);

        await el.handleUseCatalogEntry({
            detail: {
                catalogId: 'a01NEWCATALOGXX2',
                type: 'Date',
                questionText: 'When?'
            }
        });

        expect(LightningConfirm.open).toHaveBeenCalledTimes(1);
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.newSelection.attributes.Form_Question_Catalog__c).toBe(
            'a01NEWCATALOGXX2'
        );
    });
});

describe('currentCatalogId getter', () => {
    test('returns the binding\'s linked catalog id', () => {
        const el = mount(makeSelection({ catalogId: 'a01ABCDEFGHIJKL2' }));
        expect(el.currentCatalogId).toBe('a01ABCDEFGHIJKL2');
    });

    test('returns null when the binding has no catalog link', () => {
        const el = mount(makeSelection({ catalogId: null }));
        expect(el.currentCatalogId).toBeNull();
    });
});
