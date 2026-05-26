import { createElement } from 'lwc';
import NeuraFormExceptionModal from 'c/neuraFormExceptionModal';

async function mount(props = {}) {
    const el = createElement('c-neura-form-exception-modal', {
        is: NeuraFormExceptionModal
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

describe('c-neura-form-exception-modal', () => {
    it('renders nothing when closed', async () => {
        const el = await mount({ open: false });
        expect(el.shadowRoot.querySelector('.exception-modal__backdrop')).toBeNull();
    });

    it('renders the panel when open', async () => {
        const el = await mount({
            open: true,
            findingId: 'a',
            findingName: 'Cooler temp out of range',
            findingSeverity: 'Critical',
            exceptionPolicy: 'Allow'
        });
        expect(el.shadowRoot.querySelector('.exception-modal__backdrop')).not.toBeNull();
        expect(el.shadowRoot.querySelector('lightning-combobox')).not.toBeNull();
    });

    it('shows the locked message when policy is Disallow', async () => {
        const el = await mount({
            open: true,
            findingId: 'a',
            exceptionPolicy: 'Disallow'
        });
        expect(el.shadowRoot.querySelector('.exception-modal__locked')).not.toBeNull();
        expect(el.shadowRoot.querySelector('lightning-combobox')).toBeNull();
    });

    it('emits cancel when Cancel clicked', async () => {
        const el = await mount({ open: true, exceptionPolicy: 'Allow' });
        const handler = jest.fn();
        el.addEventListener('cancel', handler);
        const cancelBtn = Array.from(
            el.shadowRoot.querySelectorAll('.exception-modal__button')
        ).find((b) => b.textContent.trim() === 'Cancel');
        cancelBtn.click();
        expect(handler).toHaveBeenCalledTimes(1);
    });

    it('disables Mark exception until reason is set', async () => {
        const el = await mount({
            open: true,
            findingId: 'a',
            exceptionPolicy: 'Allow'
        });
        const primary = el.shadowRoot.querySelector(
            '.exception-modal__button--primary'
        );
        expect(primary.disabled).toBe(true);

        // Simulate reason selection via component-level change handler.
        const combo = el.shadowRoot.querySelector('lightning-combobox');
        combo.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'Customer waived' } })
        );
        await Promise.resolve();
        expect(primary.disabled).toBe(false);
    });

    it('requires detail when reason is Other', async () => {
        const el = await mount({
            open: true,
            findingId: 'a',
            exceptionPolicy: 'Allow'
        });
        const combo = el.shadowRoot.querySelector('lightning-combobox');
        combo.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'Other' } })
        );
        await Promise.resolve();

        const primary = el.shadowRoot.querySelector(
            '.exception-modal__button--primary'
        );
        expect(primary.disabled).toBe(true);

        const textarea = el.shadowRoot.querySelector('lightning-textarea');
        textarea.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'Customer accepted risk.' } })
        );
        await Promise.resolve();
        expect(primary.disabled).toBe(false);
    });

    it('requires photo acknowledgement when policy is Require photo', async () => {
        const el = await mount({
            open: true,
            findingId: 'a',
            exceptionPolicy: 'Require photo'
        });
        const combo = el.shadowRoot.querySelector('lightning-combobox');
        combo.dispatchEvent(
            new CustomEvent('change', { detail: { value: 'Customer waived' } })
        );
        await Promise.resolve();

        const primary = el.shadowRoot.querySelector(
            '.exception-modal__button--primary'
        );
        // Reason picked, but photo checkbox unchecked → still disabled.
        expect(primary.disabled).toBe(true);

        const checkbox = el.shadowRoot.querySelector('lightning-input');
        checkbox.dispatchEvent(
            new CustomEvent('change', { detail: { checked: true } })
        );
        await Promise.resolve();
        expect(primary.disabled).toBe(false);
    });

    it('emits confirm with full payload', async () => {
        const el = await mount({
            open: true,
            findingId: 'a-id',
            exceptionPolicy: 'Require photo'
        });
        const handler = jest.fn();
        el.addEventListener('confirm', handler);

        el.shadowRoot
            .querySelector('lightning-combobox')
            .dispatchEvent(
                new CustomEvent('change', { detail: { value: 'Customer waived' } })
            );
        await Promise.resolve();
        el.shadowRoot
            .querySelector('lightning-input')
            .dispatchEvent(
                new CustomEvent('change', { detail: { checked: true } })
            );
        await Promise.resolve();

        el.shadowRoot
            .querySelector('.exception-modal__button--primary')
            .click();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({
            findingId: 'a-id',
            reason: 'Customer waived',
            detail: '',
            willAttachPhoto: true
        });
    });
});
