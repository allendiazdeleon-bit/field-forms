import {
    extractDocumentText,
    requiredLibFor,
    DocExtractionError
} from '../docTextExtractor';

describe('docTextExtractor', () => {
    it('routes extensions to the right library requirement', () => {
        expect(requiredLibFor('audit.pdf')).toBe('pdfjs');
        expect(requiredLibFor('audit.DOCX')).toBe('jszip');
        expect(requiredLibFor('audit.txt')).toBeNull();
        expect(requiredLibFor('audit.html')).toBeNull();
    });

    it('extracts plain text files', async () => {
        const file = new File(['Section 1: Safety\n1. Extinguisher present?'], 'audit.txt', {
            type: 'text/plain'
        });
        const result = await extractDocumentText(file, {});
        expect(result.text).toContain('Extinguisher present?');
        expect(result.truncated).toBe(false);
    });

    it('strips markup from HTML files', async () => {
        const file = new File(
            ['<html><body><h1>Audit</h1><p>Check the &amp; freezer</p><script>evil()</script></body></html>'],
            'audit.html', { type: 'text/html' }
        );
        const result = await extractDocumentText(file, {});
        expect(result.text).toContain('Audit');
        expect(result.text).toContain('Check the & freezer');
        expect(result.text).not.toContain('<p>');
    });

    it('rejects unsupported extensions with an actionable message', async () => {
        const file = new File(['x'], 'audit.doc', { type: 'application/msword' });
        await expect(extractDocumentText(file, {})).rejects.toThrow(DocExtractionError);
        await expect(extractDocumentText(file, {})).rejects.toThrow(/paste the text/);
    });

    it('rejects empty documents instead of drafting from nothing', async () => {
        const file = new File(['   \n  '], 'blank.txt', { type: 'text/plain' });
        await expect(extractDocumentText(file, {})).rejects.toThrow(/No readable text/);
    });

    it('truncates very large documents and flags it', async () => {
        const big = 'word '.repeat(50000); // 250k chars
        const file = new File([big], 'big.txt', { type: 'text/plain' });
        const result = await extractDocumentText(file, {});
        expect(result.truncated).toBe(true);
        expect(result.text.length).toBeLessThanOrEqual(200000);
    });

    it('requires the pdf library to be passed for PDFs', async () => {
        const file = new File(['%PDF-1.4'], 'audit.pdf', { type: 'application/pdf' });
        await expect(extractDocumentText(file, {})).rejects.toThrow(/PDF library/);
    });
});
