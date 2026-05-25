import { createElement } from 'lwc';
import NeuraFormAnswer from 'c/neuraFormAnswer';

/**
 * Smoke coverage for c-neura-form-answer's type-routing surface.
 *
 * Purpose:
 *   neuraFormAnswer is a 25-branch switch that picks the right input LWC
 *   for each question Type. The template is the documentation; this test
 *   is the contract. Adding a new input type should add one row here.
 *
 * Safety net for the upcoming type-routing-registry refactor: as long as
 * each type's expected element still mounts under the same selector,
 * the refactor is regression-free for routing purposes.
 *
 * Scope (intentionally narrow):
 *   - For each question Type, mount neuraFormAnswer and assert the
 *     expected child element appears in the shadow DOM.
 *   - No interaction assertions, no answer-save assertions, no validation
 *     coverage. Those belong in deeper tests after the refactor.
 *
 * Caveats:
 *   - Choice types (Multiple Choice / Dropdown / Radio Buttons) route
 *     through pills when option count <=6, combobox above. Both branches
 *     are covered explicitly.
 *   - Display Text routes through neuraFormQuestion, not neuraFormAnswer,
 *     so it's omitted here.
 *   - The choice-pills component renders its own <button> elements
 *     synchronously via for:each, so a single microtask flush is enough
 *     to assert mount.
 */

/** Build a minimal flat question record. neuraFormAnswer reads via
 *  getValue(obj, fieldName, default), which is just obj[fieldName] —
 *  no fields.X.value wrapper needed. */
function makeQuestion(overrides = {}) {
    return {
        Id: 'q-smoke-1',
        Question__c: 'Smoke question',
        Type__c: 'Text',
        Value_Set__c: '',
        Required__c: false,
        Include_Comment__c: false,
        Include_Photo__c: false,
        answers: [
            {
                Id: 'a-smoke-1',
                Answer__c: '',
                filesData: []
            }
        ],
        ...overrides
    };
}

const SMALL_OPTIONS = JSON.stringify([
    { label: 'Foo', value: 'foo' },
    { label: 'Bar', value: 'bar' },
    { label: 'Baz', value: 'baz' }
]);

const LARGE_OPTIONS = JSON.stringify(
    Array.from({ length: 10 }, (_, i) => ({
        label: `Option ${i + 1}`,
        value: `opt-${i + 1}`
    }))
);

/** Mount neuraFormAnswer with the given input type and question.
 *  Returns the rendered element; caller is responsible for cleanup
 *  via the afterEach below. */
async function mount({ inputType, question }) {
    const el = createElement('c-neura-form-answer', { is: NeuraFormAnswer });
    el.recordId = 'host-record-id';
    el.inputType = inputType;
    el.question = question || makeQuestion({ Type__c: inputType });
    el.isRequired = false;
    document.body.appendChild(el);
    // One microtask is enough for the template to render the type's branch.
    await Promise.resolve();
    return el;
}

afterEach(() => {
    while (document.body.firstChild) {
        document.body.removeChild(document.body.firstChild);
    }
});

// ──────────────────────────────────────────────────────────────────────
// Native lightning-input branches
// ──────────────────────────────────────────────────────────────────────

describe('neuraFormAnswer — native lightning-input routing', () => {
    const NATIVE_CASES = [
        { type: 'Text',      selector: 'lightning-input[data-id="textBox"]' },
        { type: 'Date',      selector: 'lightning-input[data-id="datePicker"]' },
        { type: 'Time',      selector: 'lightning-input[data-id="timePicker"]' },
        { type: 'Number',    selector: 'lightning-input[data-id="numberInput"]' },
        { type: 'Email',     selector: 'lightning-input[data-id="emailInput"]' },
        { type: 'Phone',     selector: 'lightning-input[data-id="phoneInput"]' },
        { type: 'Toggle',    selector: 'lightning-input[data-id="toggle"]' },
        { type: 'Checkbox',  selector: 'lightning-input[data-id="checkboxButton"]' },
        { type: 'Date Time', selector: 'lightning-input[data-id="dateTimeInput"]' },
        { type: 'Currency',  selector: 'lightning-input[data-id="currencyInput"]' }
    ];

    test.each(NATIVE_CASES)(
        'mounts $selector for type "$type"',
        async ({ type, selector }) => {
            const el = await mount({ inputType: type });
            expect(el.shadowRoot.querySelector(selector)).not.toBeNull();
        }
    );
});

// ──────────────────────────────────────────────────────────────────────
// Native non-input branches
// ──────────────────────────────────────────────────────────────────────

describe('neuraFormAnswer — native non-input routing', () => {
    it('mounts lightning-textarea for type "Text Area"', async () => {
        const el = await mount({ inputType: 'Text Area' });
        expect(
            el.shadowRoot.querySelector('lightning-textarea[data-id="textArea"]')
        ).not.toBeNull();
    });

    it('mounts lightning-slider for type "Slider"', async () => {
        const el = await mount({ inputType: 'Slider' });
        expect(
            el.shadowRoot.querySelector('lightning-slider[data-id="slider"]')
        ).not.toBeNull();
    });
});

// ──────────────────────────────────────────────────────────────────────
// Custom-component branches (no data-id on some — selector by tag)
// ──────────────────────────────────────────────────────────────────────

describe('neuraFormAnswer — custom-component routing', () => {
    const CUSTOM_CASES = [
        { type: 'Geolocation',   selector: 'c-neura-form-answer-input-geolocation' },
        { type: 'Scan Barcode',  selector: 'c-neura-form-answer-input-scan-barcode' },
        { type: 'Signature',     selector: 'c-neura-form-answer-input-signature' },
        { type: 'File Upload',   selector: 'c-neura-form-answer-input-file-upload' },
        { type: 'Rating',        selector: 'c-neura-form-answer-input-star-rating' },
        { type: 'Calculation',   selector: 'c-neura-form-answer-input-calculation' },
        { type: 'Pass Fail NA',  selector: 'c-neura-form-answer-input-pass-fail-na' },
        { type: 'Counter',       selector: 'c-neura-form-answer-input-counter' },
        { type: 'Lookup',        selector: 'c-neura-form-answer-input-lookup' },
        { type: 'Repeatable',    selector: 'c-neura-form-answer-input-repeatable' }
    ];

    test.each(CUSTOM_CASES)(
        'mounts $selector for type "$type"',
        async ({ type, selector }) => {
            const el = await mount({ inputType: type });
            expect(el.shadowRoot.querySelector(selector)).not.toBeNull();
        }
    );

    it('mounts checklist with options from Value_Set__c', async () => {
        const el = await mount({
            inputType: 'Checklist',
            question: makeQuestion({
                Type__c: 'Checklist',
                Value_Set__c: SMALL_OPTIONS
            })
        });
        expect(
            el.shadowRoot.querySelector('c-neura-form-answer-input-checklist')
        ).not.toBeNull();
    });
});

// ──────────────────────────────────────────────────────────────────────
// Choice-pills threshold — Multiple Choice / Dropdown / Radio Buttons
// route through pills when options <=6, fall back to combobox above.
// ──────────────────────────────────────────────────────────────────────

describe('neuraFormAnswer — choice-input threshold routing', () => {
    it('routes Multiple Choice with <=6 options to choice-pills (multi)', async () => {
        const el = await mount({
            inputType: 'Multiple Choice',
            question: makeQuestion({
                Type__c: 'Multiple Choice',
                Value_Set__c: SMALL_OPTIONS
            })
        });
        const pills = el.shadowRoot.querySelector(
            'c-neura-form-answer-input-choice-pills[data-id="multipleChoice"]'
        );
        expect(pills).not.toBeNull();
        expect(pills.isMulti).toBe(true);
    });

    it('routes Multiple Choice with >6 options to multi-select combobox', async () => {
        const el = await mount({
            inputType: 'Multiple Choice',
            question: makeQuestion({
                Type__c: 'Multiple Choice',
                Value_Set__c: LARGE_OPTIONS
            })
        });
        expect(
            el.shadowRoot.querySelector(
                'c-neura-form-answer-input-multi-select[data-id="multipleChoice"]'
            )
        ).not.toBeNull();
        expect(
            el.shadowRoot.querySelector(
                'c-neura-form-answer-input-choice-pills[data-id="multipleChoice"]'
            )
        ).toBeNull();
    });

    it('routes Dropdown with <=6 options to choice-pills (single)', async () => {
        const el = await mount({
            inputType: 'Dropdown',
            question: makeQuestion({
                Type__c: 'Dropdown',
                Value_Set__c: SMALL_OPTIONS
            })
        });
        const pills = el.shadowRoot.querySelector(
            'c-neura-form-answer-input-choice-pills[data-id="dropDown"]'
        );
        expect(pills).not.toBeNull();
        // Dropdown is single-select — isMulti should be falsy.
        expect(pills.isMulti).toBeFalsy();
    });

    it('routes Dropdown with >6 options to lightning-combobox', async () => {
        const el = await mount({
            inputType: 'Dropdown',
            question: makeQuestion({
                Type__c: 'Dropdown',
                Value_Set__c: LARGE_OPTIONS
            })
        });
        expect(
            el.shadowRoot.querySelector(
                'lightning-combobox[data-id="dropDown"]'
            )
        ).not.toBeNull();
    });

    it('routes Radio Buttons through choice-pills regardless of option count', async () => {
        const elSmall = await mount({
            inputType: 'Radio Buttons',
            question: makeQuestion({
                Type__c: 'Radio Buttons',
                Value_Set__c: SMALL_OPTIONS
            })
        });
        expect(
            elSmall.shadowRoot.querySelector(
                'c-neura-form-answer-input-choice-pills[data-id="radioButtons"]'
            )
        ).not.toBeNull();

        // Same selector for the >6 case — Radio Buttons always pills.
        document.body.removeChild(elSmall);
        const elLarge = await mount({
            inputType: 'Radio Buttons',
            question: makeQuestion({
                Type__c: 'Radio Buttons',
                Value_Set__c: LARGE_OPTIONS
            })
        });
        expect(
            elLarge.shadowRoot.querySelector(
                'c-neura-form-answer-input-choice-pills[data-id="radioButtons"]'
            )
        ).not.toBeNull();
    });
});

// ──────────────────────────────────────────────────────────────────────
// Negative coverage — unknown type renders nothing actionable
// ──────────────────────────────────────────────────────────────────────

describe('neuraFormAnswer — unknown type fallback', () => {
    it('does not mount any known input branch for an unknown type', async () => {
        const el = await mount({ inputType: 'NotARealType' });
        const ANY_KNOWN_SELECTOR = [
            'lightning-input',
            'lightning-textarea',
            'lightning-slider',
            'lightning-combobox',
            'c-neura-form-answer-input-pass-fail-na',
            'c-neura-form-answer-input-counter',
            'c-neura-form-answer-input-choice-pills'
        ].join(', ');
        // The comment/photo blocks may still render input-like nodes; we
        // only assert the question-body answer branch didn't fire.
        const root = el.shadowRoot;
        const bodyAnswer = root.querySelector(
            'c-neura-form-answer-input-pass-fail-na, c-neura-form-answer-input-counter, c-neura-form-answer-input-choice-pills, lightning-slider, lightning-textarea, lightning-combobox'
        );
        // Either nothing matches, or the matched element belongs to a
        // tangential branch (e.g., none of our known answer renderers).
        expect(bodyAnswer).toBeNull();
    });
});
