import { createElement } from 'lwc';
import NeuraFormSubmitGuard from 'c/neuraFormSubmitGuard';

async function mount(props = {}) {
    const el = createElement('c-neura-form-submit-guard', {
        is: NeuraFormSubmitGuard
    });
    Object.assign(el, props);
    document.body.appendChild(el);
    await Promise.resolve();
    return el;
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
});

const F = (overrides = {}) => ({
    Id: '001',
    Severity__c: 'Medium',
    Status__c: 'Open',
    Blocks_Submission__c: false,
    ...overrides
});

describe('c-neura-form-submit-guard', () => {
    it('enables submit when no findings exist', async () => {
        const el = await mount({ score: 25, maxScore: 30, threshold: 80, findings: [] });
        expect(el.shadowRoot.querySelector('.submit-guard__submit')).not.toBeNull();
        expect(el.shadowRoot.querySelector('.submit-guard__blocked')).toBeNull();
    });

    it('disables submit when at least one blocking finding is open', async () => {
        const el = await mount({
            findings: [F({ Id: 'a', Blocks_Submission__c: true, Severity__c: 'Critical' })]
        });
        expect(el.shadowRoot.querySelector('.submit-guard__submit')).toBeNull();
        const blocked = el.shadowRoot.querySelector('.submit-guard__blocked');
        expect(blocked).not.toBeNull();
        expect(blocked.textContent).toMatch(/Resolve 1 blocking finding/);
    });

    it('pluralizes the blocking message', async () => {
        const el = await mount({
            findings: [
                F({ Id: 'a', Blocks_Submission__c: true }),
                F({ Id: 'b', Blocks_Submission__c: true })
            ]
        });
        expect(
            el.shadowRoot.querySelector('.submit-guard__blocked-reason').textContent
        ).toMatch(/Resolve 2 blocking findings/);
    });

    it('honors forceDisabled even with no blockers', async () => {
        const el = await mount({
            findings: [],
            forceDisabled: true,
            disabledReason: 'Signature required'
        });
        const blocked = el.shadowRoot.querySelector('.submit-guard__blocked');
        expect(blocked).not.toBeNull();
        expect(blocked.textContent).toMatch(/Signature required/);
    });

    it('emits submit event when CTA tapped (enabled state)', async () => {
        const el = await mount({ score: 20, maxScore: 20, threshold: 80, findings: [] });
        const handler = jest.fn();
        el.addEventListener('submit', handler);
        el.shadowRoot.querySelector('.submit-guard__submit').click();
        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('emits viewfindings event when View findings tapped', async () => {
        const el = await mount({
            findings: [F({ Id: 'a', Blocks_Submission__c: true })]
        });
        const handler = jest.fn();
        el.addEventListener('viewfindings', handler);
        el.shadowRoot.querySelector('.submit-guard__view-findings').click();
        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('shows non-blocking note when submit enabled but findings remain', async () => {
        const el = await mount({
            findings: [
                F({ Id: 'a', Severity__c: 'Medium' }),
                F({ Id: 'b', Severity__c: 'High' })
            ]
        });
        // No blockers → submit enabled, note shown.
        expect(el.shadowRoot.querySelector('.submit-guard__submit')).not.toBeNull();
        const note = el.shadowRoot.querySelector('.submit-guard__note');
        expect(note.textContent).toMatch(/2 open findings/);
    });

    it('renders severity breakdown only for present buckets', async () => {
        const el = await mount({
            findings: [
                F({ Id: 'a', Severity__c: 'Critical', Blocks_Submission__c: true }),
                F({ Id: 'b', Severity__c: 'Medium' })
            ]
        });
        const rows = el.shadowRoot.querySelectorAll('.submit-guard__breakdown-row');
        expect(rows.length).toBe(2);
        expect(rows[0].textContent).toMatch(/1 Critical \(blocks\)/);
        expect(rows[1].textContent).toMatch(/1 Medium/);
    });

    it('emits savedraft from Save draft', async () => {
        const el = await mount({ findings: [] });
        const handler = jest.fn();
        el.addEventListener('savedraft', handler);
        el.shadowRoot.querySelector('.submit-guard__draft').click();
        expect(handler).toHaveBeenCalledTimes(1);
    });
});
