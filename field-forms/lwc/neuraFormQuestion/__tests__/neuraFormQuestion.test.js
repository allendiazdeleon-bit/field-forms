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

    function mountWithDisplayText(richText) {
        const element = createElement('c-neura-form-question', {
            is: NeuraFormQuestion
        });
        element.formQuestion = {
            fields: {
                Type__c: { value: 'Display Text' },
                Display_Rich_Text__c: { value: richText }
            }
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
