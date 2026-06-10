import { createElement } from 'lwc';
import NeuraFormBrandHub from 'c/neuraFormBrandHub';
import getBrandContext from '@salesforce/apex/NeuraFormBrandController.getBrandContext';
import listTemplatesForScope from '@salesforce/apex/NeuraFormBrandController.listTemplatesForScope';

// @wire(apexMethod) needs a real test wire adapter to .emit() through — the
// default apex transform stubs the import as a plain resolved function with
// no emit(). Mock each wired method explicitly.
jest.mock(
    '@salesforce/apex/NeuraFormBrandController.getBrandContext',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);
jest.mock(
    '@salesforce/apex/NeuraFormBrandController.listTemplatesForScope',
    () => {
        const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
        return { default: createApexTestWireAdapter(jest.fn()) };
    },
    { virtual: true }
);

/**
 * Tests for c-neura-form-brand-hub. Cover the render branches that drive
 * the onboarding flow:
 *   - context wire unresolved -> loading spinner, no premature setup prompt
 *   - no Form_Scope__c on the Account -> scope-setup prompt (start onboarding)
 *   - scope set, no templates -> empty state
 *   - scope set, templates present -> datatable of the brand's forms
 *   - "New Form" toolbar action opens the create modal
 */

const ACCOUNT_WITH_SCOPE = {
    Id: '001000000000001',
    Name: 'Burger King',
    Form_Scope__c: 'BURGER_KING'
};

const ACCOUNT_NO_SCOPE = {
    Id: '001000000000001',
    Name: 'Burger King',
    Form_Scope__c: null
};

const TEMPLATE_ROW = {
    Id: 'a01000000000001',
    Name: 'BK Opening Checklist',
    Status__c: 'Active',
    Scope__c: 'BURGER_KING',
    Scoring_Enabled__c: true,
    Max_Score__c: 100,
    LastModifiedDate: '2026-06-01T12:00:00.000Z'
};

async function mount() {
    const el = createElement('c-neura-form-brand-hub', { is: NeuraFormBrandHub });
    el.recordId = '001000000000001';
    document.body.appendChild(el);
    await Promise.resolve();
    return el;
}

function buttonLabels(el) {
    return Array.from(el.shadowRoot.querySelectorAll('lightning-button')).map((b) => b.label);
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
});

describe('c-neura-form-brand-hub', () => {
    it('shows a loading state (not the setup prompt) before the context wire resolves', async () => {
        const el = await mount();

        expect(el.shadowRoot.querySelector('lightning-spinner')).not.toBeNull();
        expect(buttonLabels(el)).not.toContain('Set up brand forms');
    });

    it('shows the scope-setup prompt when the Account has no Form_Scope__c', async () => {
        const el = await mount();
        getBrandContext.emit(ACCOUNT_NO_SCOPE);
        listTemplatesForScope.emit([]);
        await Promise.resolve();

        expect(buttonLabels(el)).toContain('Set up brand forms');
        // Toolbar actions are hidden until the brand is onboarded.
        expect(buttonLabels(el)).not.toContain('New Form');
        expect(el.shadowRoot.querySelector('lightning-datatable')).toBeNull();
    });

    it('shows the empty state when scoped but no templates exist', async () => {
        const el = await mount();
        getBrandContext.emit(ACCOUNT_WITH_SCOPE);
        listTemplatesForScope.emit([]);
        await Promise.resolve();

        expect(buttonLabels(el)).toContain('New Form');
        expect(el.shadowRoot.querySelector('lightning-datatable')).toBeNull();
        expect(el.shadowRoot.textContent).toContain('No forms for this brand yet');
    });

    it('renders the datatable of the brand templates', async () => {
        const el = await mount();
        getBrandContext.emit(ACCOUNT_WITH_SCOPE);
        listTemplatesForScope.emit([TEMPLATE_ROW]);
        await Promise.resolve();

        const table = el.shadowRoot.querySelector('lightning-datatable');
        expect(table).not.toBeNull();
        expect(table.data).toHaveLength(1);
        expect(table.data[0].Name).toBe('BK Opening Checklist');
        // Each row gets per-status actions computed by the component.
        expect(Array.isArray(table.data[0].rowActions)).toBe(true);
    });

    it('opens the new-form modal from the toolbar', async () => {
        const el = await mount();
        getBrandContext.emit(ACCOUNT_WITH_SCOPE);
        listTemplatesForScope.emit([]);
        await Promise.resolve();

        const newBtn = Array.from(el.shadowRoot.querySelectorAll('lightning-button')).find(
            (b) => b.label === 'New Form'
        );
        newBtn.click();
        await Promise.resolve();

        expect(el.shadowRoot.querySelector('.slds-modal')).not.toBeNull();
    });

    it('closes the new-form modal on Escape', async () => {
        const el = await mount();
        getBrandContext.emit(ACCOUNT_WITH_SCOPE);
        listTemplatesForScope.emit([]);
        await Promise.resolve();

        Array.from(el.shadowRoot.querySelectorAll('lightning-button'))
            .find((b) => b.label === 'New Form')
            .click();
        await Promise.resolve();

        const modal = el.shadowRoot.querySelector('.slds-modal');
        expect(modal).not.toBeNull();
        modal.dispatchEvent(
            new KeyboardEvent('keydown', { key: 'Escape', bubbles: true })
        );
        await Promise.resolve();

        expect(el.shadowRoot.querySelector('.slds-modal')).toBeNull();
    });
});
