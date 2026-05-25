import { createElement } from 'lwc';
import NeuraFormQuestion from 'c/neuraFormQuestion';

// Smoke coverage for the offline rich-text sanitizer added in Wave 1 (M4).
// lightning-formatted-rich-text strips target="_blank" silently inside the FSL
// Mobile WebView; we replace it with rel="noopener" at the source so admins
// don't ship dead links into the field.

describe('c-neura-form-question rich text sanitizer', () => {
    afterEach(() => {
        while (document.body.firstChild) {
            document.body.removeChild(document.body.firstChild);
        }
    });

    // neuraFormQuestion reads fields via getValue(obj, fieldName) which is
    // flat (obj[fieldName]) — NOT the LDS-style fields.X.value wrapper.
    // The renderer pre-processes the LDS shape into flat objects before
    // passing them down. Tests must mirror the post-processed shape.
    function mountWithDisplayText(richText) {
        const element = createElement('c-neura-form-question', {
            is: NeuraFormQuestion
        });
        element.formQuestion = {
            Id: 'q-test',
            Type__c: 'Display Text',
            Display_Rich_Text__c: richText
        };
        document.body.appendChild(element);
        return element;
    }

    it('strips target="_blank" from anchor tags in the rich text', () => {
        const element = mountWithDisplayText(
            '<p>See <a href="https://example.com" target="_blank">docs</a>.</p>'
        );
        return Promise.resolve().then(() => {
            const rt = element.shadowRoot.querySelector(
                'lightning-formatted-rich-text'
            );
            expect(rt.value).not.toMatch(/target=["']_blank["']/i);
            expect(rt.value).toMatch(/rel=["']noopener["']/i);
        });
    });

    it('passes other rich-text content through unchanged', () => {
        const html = '<p><strong>Inspect roof</strong> for damage.</p>';
        const element = mountWithDisplayText(html);
        return Promise.resolve().then(() => {
            const rt = element.shadowRoot.querySelector(
                'lightning-formatted-rich-text'
            );
            expect(rt.value).toBe(html);
        });
    });

    it('handles null/empty rich text without throwing', () => {
        const element = mountWithDisplayText('');
        return Promise.resolve().then(() => {
            const rt = element.shadowRoot.querySelector(
                'lightning-formatted-rich-text'
            );
            expect(rt.value).toBe('');
        });
    });
});
