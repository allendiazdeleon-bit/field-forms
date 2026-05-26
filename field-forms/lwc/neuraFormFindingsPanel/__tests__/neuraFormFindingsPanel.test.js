import { createElement } from 'lwc';
import NeuraFormFindingsPanel from 'c/neuraFormFindingsPanel';

/**
 * Tests for c-neura-form-findings-panel. Cover:
 *   - empty state (no open findings)
 *   - summary text formats (singular/plural, blocking vs non-blocking)
 *   - severity sort (Critical → High → Medium → Low)
 *   - filter to Open / In Progress only
 *   - expand/collapse toggle + forceExpanded override
 *   - event payloads (findingclick, addphoto, markexception)
 *   - photo-required vs photo-attached affordances
 */

async function mount(props = {}) {
    const el = createElement('c-neura-form-findings-panel', {
        is: NeuraFormFindingsPanel
    });
    Object.assign(el, props);
    document.body.appendChild(el);
    await Promise.resolve();
    return el;
}

function findingCards(el) {
    return el.shadowRoot.querySelectorAll('li.finding-card');
}

function summaryText(el) {
    return el.shadowRoot
        .querySelector('.findings-panel__summary')
        .textContent.trim();
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
});

const F = (overrides = {}) => ({
    Id: '001',
    Name: 'Some finding',
    Severity__c: 'Medium',
    Status__c: 'Open',
    Blocks_Submission__c: false,
    Photo_Required__c: false,
    Photo_Attached__c: false,
    External_Reference__c: 'q_1',
    ...overrides
});

describe('c-neura-form-findings-panel', () => {
    it('renders the empty summary when no open findings', async () => {
        const el = await mount({ findings: [] });
        expect(summaryText(el)).toBe('No findings · 0');
    });

    it('summarizes one finding without blocks', async () => {
        const el = await mount({ findings: [F()] });
        expect(summaryText(el)).toBe('1 findings');
    });

    it('summarizes blocking count with singular "blocks" for 1', async () => {
        const el = await mount({
            findings: [
                F({ Id: 'a', Severity__c: 'Critical', Blocks_Submission__c: true }),
                F({ Id: 'b' })
            ]
        });
        expect(summaryText(el)).toBe('2 findings · 1 blocks');
    });

    it('summarizes plural blocks when count > 1', async () => {
        const el = await mount({
            findings: [
                F({ Id: 'a', Blocks_Submission__c: true }),
                F({ Id: 'b', Blocks_Submission__c: true })
            ]
        });
        expect(summaryText(el)).toBe('2 findings · 2 block');
    });

    it('filters out Resolved / Waived findings', async () => {
        const el = await mount({
            forceExpanded: true,
            findings: [
                F({ Id: 'a', Status__c: 'Open' }),
                F({ Id: 'b', Status__c: 'Resolved' }),
                F({ Id: 'c', Status__c: 'Waived' }),
                F({ Id: 'd', Status__c: 'In Progress' })
            ]
        });
        expect(findingCards(el).length).toBe(2);
    });

    it('sorts findings by severity Critical → Low', async () => {
        const el = await mount({
            forceExpanded: true,
            findings: [
                F({ Id: '1', Name: 'low', Severity__c: 'Low' }),
                F({ Id: '2', Name: 'crit', Severity__c: 'Critical' }),
                F({ Id: '3', Name: 'med', Severity__c: 'Medium' }),
                F({ Id: '4', Name: 'high', Severity__c: 'High' })
            ]
        });
        const titles = Array.from(findingCards(el)).map((card) =>
            card.querySelector('.finding-card__title').textContent.trim()
        );
        expect(titles).toEqual(['crit', 'high', 'med', 'low']);
    });

    it('stays collapsed by default', async () => {
        const el = await mount({ findings: [F()] });
        expect(el.shadowRoot.querySelector('.findings-panel__body')).toBeNull();
    });

    it('expands on handle click and emits panelexpand', async () => {
        const el = await mount({ findings: [F()] });
        const expand = jest.fn();
        el.addEventListener('panelexpand', expand);
        el.shadowRoot.querySelector('.findings-panel__handle').click();
        await Promise.resolve();
        expect(el.shadowRoot.querySelector('.findings-panel__body')).not.toBeNull();
        expect(expand).toHaveBeenCalledTimes(1);
    });

    it('forceExpanded overrides internal state and ignores taps', async () => {
        const el = await mount({ findings: [F()], forceExpanded: true });
        const collapse = jest.fn();
        el.addEventListener('panelcollapse', collapse);
        el.shadowRoot.querySelector('.findings-panel__handle').click();
        await Promise.resolve();
        // Body remains rendered; no collapse event fired.
        expect(el.shadowRoot.querySelector('.findings-panel__body')).not.toBeNull();
        expect(collapse).not.toHaveBeenCalled();
    });

    it('emits findingclick with id + external reference', async () => {
        const el = await mount({
            forceExpanded: true,
            findings: [F({ Id: 'x1', External_Reference__c: 'q_42' })]
        });
        const handler = jest.fn();
        el.addEventListener('findingclick', handler);
        el.shadowRoot.querySelector('.finding-card__header').click();
        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({
            findingId: 'x1',
            externalReference: 'q_42'
        });
    });

    it('shows Add photo when required and not yet attached', async () => {
        const el = await mount({
            forceExpanded: true,
            findings: [F({ Id: 'p', Photo_Required__c: true })]
        });
        const photoBtn = el.shadowRoot.querySelector(
            '.finding-card__action--primary'
        );
        expect(photoBtn).not.toBeNull();
        const handler = jest.fn();
        el.addEventListener('addphoto', handler);
        photoBtn.click();
        expect(handler.mock.calls[0][0].detail).toEqual({ findingId: 'p' });
    });

    it('shows "Photo attached" pill when required and attached', async () => {
        const el = await mount({
            forceExpanded: true,
            findings: [
                F({
                    Id: 'p',
                    Photo_Required__c: true,
                    Photo_Attached__c: true
                })
            ]
        });
        expect(
            el.shadowRoot.querySelector('.finding-card__pill--ok')
        ).not.toBeNull();
        expect(
            el.shadowRoot.querySelector('.finding-card__action--primary')
        ).toBeNull();
    });

    it('offers Mark exception only for blocking findings without one set', async () => {
        const el = await mount({
            forceExpanded: true,
            findings: [
                F({ Id: 'b1', Blocks_Submission__c: true }),
                F({ Id: 'b2', Blocks_Submission__c: false }),
                F({
                    Id: 'b3',
                    Blocks_Submission__c: true,
                    Exception_Reason__c: 'Customer waived'
                })
            ]
        });
        const exceptionButtons = el.shadowRoot.querySelectorAll(
            'button.finding-card__action[data-finding-id]:not(.finding-card__action--primary)'
        );
        // b1 is the only one with the "Mark exception" affordance.
        expect(exceptionButtons.length).toBe(1);
        expect(exceptionButtons[0].dataset.findingId).toBe('b1');
        // b3 surfaces its existing exception as a pill.
        const exceptionPill = el.shadowRoot.querySelector(
            '.finding-card__pill--exception'
        );
        expect(exceptionPill.textContent).toMatch(/Customer waived/);
    });
});
