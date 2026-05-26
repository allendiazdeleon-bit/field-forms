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
