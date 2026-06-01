import { createElement } from 'lwc';
import NeuraFormCatalogSimilar from 'c/neuraFormCatalogSimilar';
import findSimilar from '@salesforce/apex/neuraFormBuilderController.findSimilarCatalogEntries';

/**
 * Apex method is auto-mocked by sfdx-lwc-jest; we control its return
 * value per-test. Resolving the imperative call requires awaiting one
 * microtask after the debounce timer fires, so most tests bracket with
 * jest.useFakeTimers() + jest.runAllTimers().
 */
jest.mock(
    '@salesforce/apex/neuraFormBuilderController.findSimilarCatalogEntries',
    () => ({ default: jest.fn() }),
    { virtual: true }
);

function mount() {
    const el = createElement('c-neura-form-catalog-similar', {
        is: NeuraFormCatalogSimilar
    });
    document.body.appendChild(el);
    return el;
}

afterEach(() => {
    jest.useRealTimers();
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
    findSimilar.mockReset();
});

describe('neuraFormCatalogSimilar — query gating', () => {
    test('short input (< 3 chars) does not fire a search', async () => {
        jest.useFakeTimers();
        findSimilar.mockResolvedValue([]);
        const el = mount();

        el.questionText = 'ab';
        jest.runAllTimers();
        await Promise.resolve();

        expect(findSimilar).not.toHaveBeenCalled();
    });

    test('null input does not fire a search', async () => {
        jest.useFakeTimers();
        findSimilar.mockResolvedValue([]);
        const el = mount();

        el.questionText = null;
        jest.runAllTimers();
        await Promise.resolve();

        expect(findSimilar).not.toHaveBeenCalled();
    });

    test('3+ char input fires after the debounce window', async () => {
        jest.useFakeTimers();
        findSimilar.mockResolvedValue([]);
        const el = mount();
        el.formTemplateId = 'a01000000ABCTPLT1';

        el.questionText = 'date';
        jest.runAllTimers();
        await Promise.resolve();

        expect(findSimilar).toHaveBeenCalledTimes(1);
        expect(findSimilar).toHaveBeenCalledWith({
            text: 'date',
            limitN: 5,
            formTemplateId: 'a01000000ABCTPLT1'
        });
    });

    test('rapid keystrokes collapse to a single search (debounce)', async () => {
        jest.useFakeTimers();
        findSimilar.mockResolvedValue([]);
        const el = mount();

        el.questionText = 'da';   // too short, no fire scheduled
        el.questionText = 'dat';  // 3 chars, scheduled
        el.questionText = 'date'; // resets the timer
        el.questionText = 'date '; // resets again
        jest.runAllTimers();
        await Promise.resolve();

        // Only the final value gets searched.
        expect(findSimilar).toHaveBeenCalledTimes(1);
        expect(findSimilar.mock.calls[0][0].text).toBe('date');
    });
});

describe('neuraFormCatalogSimilar — rendering matches', () => {
    test('shows results inline when Apex returns matches', async () => {
        jest.useFakeTimers();
        findSimilar.mockResolvedValue([
            {
                id: 'a01000000ABCDEFGHI',
                questionText: 'Enter the date of last service',
                type: 'Date',
                tags: 'date',
                externalReference: 'cat-1',
                usageCount: 5
            },
            {
                id: 'a01000000ABCDEFGHJ',
                questionText: 'Enter date of last service',
                type: 'Date',
                tags: '',
                externalReference: 'cat-2',
                usageCount: 1
            }
        ]);
        const el = mount();
        el.questionText = 'Enter the date';

        jest.runAllTimers();
        // Two microtasks: one for the resolved promise, one for the
        // post-update render.
        await Promise.resolve();
        await Promise.resolve();

        const items = el.shadowRoot.querySelectorAll('li');
        expect(items.length).toBe(2);
        const firstText = items[0].textContent;
        expect(firstText).toContain('Enter the date of last service');
        expect(firstText).toContain('Date');
        expect(firstText).toContain('5 templates');
    });

    test('single match uses "1 template" not "1 templates"', async () => {
        jest.useFakeTimers();
        findSimilar.mockResolvedValue([
            {
                id: 'a01',
                questionText: 'Only used once',
                type: 'Text',
                usageCount: 1
            }
        ]);
        const el = mount();
        el.questionText = 'Only used';
        jest.runAllTimers();
        await Promise.resolve();
        await Promise.resolve();

        const li = el.shadowRoot.querySelector('li');
        expect(li.textContent).toContain('1 template');
        // Singular not plural — defensive check that the trailing 's'
        // isn't there.
        expect(li.textContent).not.toContain('1 templates');
    });

    test('no matches → nothing rendered', async () => {
        jest.useFakeTimers();
        findSimilar.mockResolvedValue([]);
        const el = mount();
        el.questionText = 'Brand new question';
        jest.runAllTimers();
        await Promise.resolve();
        await Promise.resolve();

        expect(el.shadowRoot.querySelector('li')).toBeNull();
    });
});

describe('neuraFormCatalogSimilar — Wave 35.9b adopt action', () => {
    test('"Use this" click fires useentry with the match payload', async () => {
        jest.useFakeTimers();
        findSimilar.mockResolvedValue([
            {
                id: 'a01000000USETHIS1',
                questionText: 'Adopt me',
                type: 'Currency',
                tags: '',
                externalReference: 'cat-use',
                usageCount: 3
            }
        ]);
        const el = mount();
        const handler = jest.fn();
        el.addEventListener('useentry', handler);

        el.questionText = 'Adopt';
        jest.runAllTimers();
        await Promise.resolve();
        await Promise.resolve();

        // Find the "Use this" button — there's also an "Open" button in
        // the same row, so target by label.
        const buttons = el.shadowRoot.querySelectorAll('lightning-button');
        const useBtn = Array.from(buttons).find((b) => b.label === 'Use this');
        expect(useBtn).toBeDefined();
        useBtn.click();

        expect(handler).toHaveBeenCalledTimes(1);
        expect(handler.mock.calls[0][0].detail).toEqual({
            catalogId: 'a01000000USETHIS1',
            type: 'Currency',
            questionText: 'Adopt me'
        });
    });
});

describe('neuraFormCatalogSimilar — suppression filters', () => {
    test('suppresses the binding\'s own currently-linked catalog (self-reference)', async () => {
        jest.useFakeTimers();
        findSimilar.mockResolvedValue([
            {
                id: 'a01000000SELFREFX',
                questionText: 'My own catalog row',
                type: 'Text',
                usageCount: 1
            },
            {
                id: 'a01000000OTHERONE',
                questionText: 'A different entry',
                type: 'Text',
                usageCount: 4
            }
        ]);
        const el = mount();
        el.currentCatalogId = 'a01000000SELFREFX';

        el.questionText = 'something';
        jest.runAllTimers();
        await Promise.resolve();
        await Promise.resolve();

        const items = el.shadowRoot.querySelectorAll('li');
        expect(items.length).toBe(1);
        expect(items[0].textContent).toContain('A different entry');
    });

    test('suppresses byte-identical text matches (case-insensitive, trimmed)', async () => {
        jest.useFakeTimers();
        findSimilar.mockResolvedValue([
            {
                id: 'a01000000EXACTONE',
                questionText: 'Enter the date of last service',
                type: 'Date',
                usageCount: 2
            },
            {
                id: 'a01000000NEARDUPE',
                questionText: 'Enter date of last service',
                type: 'Date',
                usageCount: 1
            }
        ]);
        const el = mount();
        // Typed text matches the first row exactly (case/whitespace
        // differences are normalized).
        el.questionText = '  ENTER THE DATE OF LAST SERVICE  ';
        jest.runAllTimers();
        await Promise.resolve();
        await Promise.resolve();

        const items = el.shadowRoot.querySelectorAll('li');
        expect(items.length).toBe(1);
        expect(items[0].textContent).toContain('Enter date of last service');
    });
});

describe('neuraFormCatalogSimilar — error handling', () => {
    test('Apex rejection surfaces an error message and clears matches', async () => {
        jest.useFakeTimers();
        // Silence the expected console.error so test output stays clean.
        const errSpy = jest.spyOn(console, 'error').mockImplementation(() => {});
        findSimilar.mockRejectedValue({
            body: { message: 'SOSL is broken' }
        });

        const el = mount();
        el.questionText = 'something';
        jest.runAllTimers();
        await Promise.resolve();
        await Promise.resolve();

        const errEl = el.shadowRoot.querySelector('.slds-text-color_error');
        expect(errEl).not.toBeNull();
        expect(errEl.textContent).toContain('SOSL is broken');
        errSpy.mockRestore();
    });
});
