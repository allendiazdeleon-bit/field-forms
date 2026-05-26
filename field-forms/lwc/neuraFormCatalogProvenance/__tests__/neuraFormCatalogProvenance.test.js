import { createElement } from 'lwc';
import NeuraFormCatalogProvenance from 'c/neuraFormCatalogProvenance';

/**
 * c-neura-form-catalog-provenance is a read-only badge rendered above the
 * question editor. It surfaces three states:
 *   - not linked   (no catalog ref on the binding)
 *   - inherited    (linked, no overrides applied)
 *   - overridden   (linked, with question-text or required-flag override)
 *
 * Tests query the shadow DOM rather than reading internal getters —
 * matches the project's existing LWC test convention (see
 * neuraFormAnswer.test.js).
 */

async function mount(selection) {
    const el = createElement('c-neura-form-catalog-provenance', {
        is: NeuraFormCatalogProvenance
    });
    if (selection !== undefined) el.selection = selection;
    document.body.appendChild(el);
    // Let LWC microtask the initial render before assertions.
    await Promise.resolve();
    return el;
}

function readPrimaryText(el) {
    return el.shadowRoot.querySelector('p strong').textContent;
}

function readSecondaryText(el) {
    // Two <p> elements; the second one holds the secondary line.
    return el.shadowRoot.querySelectorAll('p')[1].textContent.trim();
}

function readIcon(el) {
    return el.shadowRoot.querySelector('lightning-icon');
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
});

describe('neuraFormCatalogProvenance — not linked', () => {
    test('selection.attributes is empty → "not linked" badge', async () => {
        const el = await mount({ attributes: {} });
        expect(readPrimaryText(el)).toBe('Not linked to a catalog entry');
        expect(readIcon(el).iconName).toBe('utility:dash');
        expect(readIcon(el).variant).toBe('inverse');
    });

    test('null selection → "not linked" badge (defensive)', async () => {
        const el = await mount(null);
        expect(readPrimaryText(el)).toBe('Not linked to a catalog entry');
    });

    test('null attributes → "not linked" badge (defensive)', async () => {
        const el = await mount({ attributes: null });
        expect(readPrimaryText(el)).toBe('Not linked to a catalog entry');
    });
});

describe('neuraFormCatalogProvenance — linked + inherited', () => {
    test('catalog ref present, no overrides → "inherited" badge', async () => {
        const el = await mount({
            attributes: {
                Form_Question_Catalog__c: 'a01000000ABCDEFGHI',
                Override_Required__c: 'Inherit'
            }
        });
        expect(readPrimaryText(el)).toBe('Inherited from catalog');
        expect(readIcon(el).iconName).toBe('utility:link');
        expect(readIcon(el).variant).toBe('success');
    });

    test('Override_Required__c=Inherit alone is NOT an override', async () => {
        const el = await mount({
            attributes: {
                Form_Question_Catalog__c: 'a01000000ABCDEFGHI',
                Override_Required__c: 'Inherit'
            }
        });
        expect(readPrimaryText(el)).toBe('Inherited from catalog');
    });
});

describe('neuraFormCatalogProvenance — linked + overridden', () => {
    test('Override_Question__c set → "overridden" with "question text"', async () => {
        const el = await mount({
            attributes: {
                Form_Question_Catalog__c: 'a01000000ABCDEFGHI',
                Override_Question__c: 'Per-template override'
            }
        });
        expect(readPrimaryText(el)).toBe('Overridden in this template');
        expect(readIcon(el).iconName).toBe('utility:edit');
        expect(readIcon(el).variant).toBe('warning');
        expect(readSecondaryText(el)).toContain('question text');
    });

    test('Override_Required__c=No → "overridden" with "required"', async () => {
        const el = await mount({
            attributes: {
                Form_Question_Catalog__c: 'a01000000ABCDEFGHI',
                Override_Required__c: 'No'
            }
        });
        expect(readPrimaryText(el)).toBe('Overridden in this template');
        expect(readSecondaryText(el)).toContain('required');
    });

    test('both overrides present → secondary lists both', async () => {
        const el = await mount({
            attributes: {
                Form_Question_Catalog__c: 'a01000000ABCDEFGHI',
                Override_Question__c: 'Override text',
                Override_Required__c: 'Yes'
            }
        });
        const secondary = readSecondaryText(el);
        expect(secondary).toContain('question text');
        expect(secondary).toContain('required');
    });
});

describe('neuraFormCatalogProvenance — action buttons (visibility)', () => {
    function findButton(el, label) {
        return Array.from(
            el.shadowRoot.querySelectorAll('lightning-button')
        ).find((b) => b.label === label) || null;
    }

    test('not linked → no buttons at all', async () => {
        const el = await mount({ attributes: {} });
        expect(findButton(el, 'Open catalog entry')).toBeNull();
        expect(findButton(el, 'Override in this template')).toBeNull();
        expect(findButton(el, 'Revert to catalog default')).toBeNull();
    });

    test('linked + inherited → "Open" + "Override" buttons, no "Revert"', async () => {
        const el = await mount({
            attributes: { Form_Question_Catalog__c: 'a01000000ABCDEFGHI' }
        });
        expect(findButton(el, 'Open catalog entry')).not.toBeNull();
        expect(findButton(el, 'Override in this template')).not.toBeNull();
        expect(findButton(el, 'Revert to catalog default')).toBeNull();
    });

    test('linked + overridden → "Open" + "Revert" buttons, no "Override"', async () => {
        const el = await mount({
            attributes: {
                Form_Question_Catalog__c: 'a01000000ABCDEFGHI',
                Override_Question__c: 'Per-template override'
            }
        });
        expect(findButton(el, 'Open catalog entry')).not.toBeNull();
        expect(findButton(el, 'Revert to catalog default')).not.toBeNull();
        expect(findButton(el, 'Override in this template')).toBeNull();
    });
});

describe('neuraFormCatalogProvenance — action button events', () => {
    test('handleRequestOverride fires requestoverride event with field detail', async () => {
        const el = await mount({
            attributes: { Form_Question_Catalog__c: 'a01000000ABCDEFGHI' }
        });
        const handler = jest.fn();
        el.addEventListener('requestoverride', handler);

        // Invoke directly — lightning-button stub doesn't simulate clicks.
        el.handleRequestOverride();
        await Promise.resolve();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.field).toBe('Override_Question__c');
    });

    test('handleRequestOverride is a no-op when not linked', async () => {
        const el = await mount({ attributes: {} });
        const handler = jest.fn();
        el.addEventListener('requestoverride', handler);
        el.handleRequestOverride();
        await Promise.resolve();
        expect(handler).not.toHaveBeenCalled();
    });

    test('handleRequestOverride is a no-op when already overridden', async () => {
        const el = await mount({
            attributes: {
                Form_Question_Catalog__c: 'a01000000ABCDEFGHI',
                Override_Question__c: 'Already overridden'
            }
        });
        const handler = jest.fn();
        el.addEventListener('requestoverride', handler);
        el.handleRequestOverride();
        await Promise.resolve();
        expect(handler).not.toHaveBeenCalled();
    });

    test('handleRevert fires revert event when overridden', async () => {
        const el = await mount({
            attributes: {
                Form_Question_Catalog__c: 'a01000000ABCDEFGHI',
                Override_Question__c: 'Override'
            }
        });
        const handler = jest.fn();
        el.addEventListener('revert', handler);
        el.handleRevert();
        await Promise.resolve();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail.field).toBe('Override_Question__c');
    });

    test('handleRevert is a no-op when not overridden', async () => {
        const el = await mount({
            attributes: { Form_Question_Catalog__c: 'a01000000ABCDEFGHI' }
        });
        const handler = jest.fn();
        el.addEventListener('revert', handler);
        el.handleRevert();
        await Promise.resolve();
        expect(handler).not.toHaveBeenCalled();
    });
});
