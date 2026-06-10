/**
 * Client-side document text extraction for the "Draft a form from the
 * customer's document" flow. Runs in the Brand Hub (desktop record page),
 * so static-resource libraries are available — this does NOT run in the
 * FSL Mobile offline runtime.
 *
 * Supported:
 *   .pdf          pdf.js (v2.16, the LWS-compatible line) page text
 *   .docx         JSZip -> word/document.xml -> text with paragraph breaks
 *   .txt/.md/.csv FileReader as text
 *   .html/.htm    DOMParser -> body textContent
 *
 * Deliberately NOT supported: scanned/image PDFs (no OCR — pdf.js returns
 * empty text; we surface a clear error), legacy .doc (binary format).
 *
 * Library loading is the caller's job (loadScript needs a component
 * context); pass the loaded globals in. Both libs load lazily on first
 * use of their format.
 */

const MAX_CHARS = 200000; // keep the LLM prompt sane; ~50 pages of text

export class DocExtractionError extends Error {}

function checkLength(text, fileName) {
    const trimmed = (text || '').trim();
    if (!trimmed) {
        throw new DocExtractionError(
            `No readable text found in ${fileName}. Scanned/image documents need OCR — paste the text instead.`
        );
    }
    if (trimmed.length > MAX_CHARS) {
        return {
            text: trimmed.slice(0, MAX_CHARS),
            truncated: true
        };
    }
    return { text: trimmed, truncated: false };
}

function readAs(file, mode) {
    return new Promise((resolve, reject) => {
        const reader = new FileReader();
        reader.onload = () => resolve(reader.result);
        reader.onerror = () => reject(new DocExtractionError(`Could not read ${file.name}.`));
        if (mode === 'text') reader.readAsText(file);
        else reader.readAsArrayBuffer(file);
    });
}

async function extractPdf(file, pdfjsLib) {
    const buffer = await readAs(file, 'buffer');
    // Lightning's security membrane (LWS/Locker) hardening, all three
    // load-bearing:
    //   - Uint8Array, not the raw ArrayBuffer: the proxied buffer fails
    //     pdf.js's instanceof check and it goes down a wrong branch that
    //     dies with "String.prototype.split called on null or undefined".
    //   - isEvalSupported false: font code paths use eval, which the
    //     sandbox blocks mid-parse.
    //   - disableFontFace: we only want text, never rendered glyphs.
    const doc = await pdfjsLib.getDocument({
        data: new Uint8Array(buffer),
        isEvalSupported: false,
        disableFontFace: true
    }).promise;
    const pages = [];
    for (let i = 1; i <= doc.numPages; i++) {
        const page = await doc.getPage(i);
        const content = await page.getTextContent();
        // Join items with spaces; double-newline between pages so section
        // boundaries survive into the LLM prompt.
        pages.push(content.items.map((item) => item.str || '').join(' '));
    }
    return pages.join('\n\n');
}

async function extractDocx(file, JSZip) {
    const buffer = await readAs(file, 'buffer');
    let zip;
    try {
        zip = await JSZip.loadAsync(buffer);
    } catch (e) {
        throw new DocExtractionError(
            `${file.name} isn't a valid .docx (legacy .doc files aren't supported — save as .docx or paste the text).`
        );
    }
    const docXml = zip.file('word/document.xml');
    if (!docXml) {
        throw new DocExtractionError(`${file.name} has no document body.`);
    }
    const xml = await docXml.async('string');
    // Paragraphs (w:p) become newlines, tabs/breaks become spaces/newlines,
    // then strip the remaining tags. Crude but faithful enough for the LLM
    // to see the document's structure.
    const text = xml
        .replace(/<w:p[ >]/g, '\n<w:p ')
        .replace(/<w:tab\/>/g, '\t')
        .replace(/<w:br\/>/g, '\n')
        .replace(/<[^>]+>/g, '')
        .replace(/&amp;/g, '&').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
        .replace(/&quot;/g, '"').replace(/&#?\w+;/g, ' ');
    return text;
}

async function extractHtml(file) {
    const raw = await readAs(file, 'text');
    const parsed = new DOMParser().parseFromString(raw, 'text/html');
    return parsed.body ? parsed.body.textContent : '';
}

/**
 * @param {File} file        The picked file.
 * @param {object} libs      { pdfjsLib?, JSZip? } — pass whichever the
 *                           extension requires (caller lazy-loads).
 * @returns {Promise<{text: string, truncated: boolean}>}
 * @throws {DocExtractionError} with a user-displayable message.
 */
export async function extractDocumentText(file, libs = {}) {
    const fileName = (file && file.name) || '';
    const ext = (fileName.split('.').pop() || '').toLowerCase();
    let raw;
    if (ext === 'pdf') {
        if (!libs.pdfjsLib) throw new DocExtractionError('PDF library not loaded.');
        raw = await extractPdf(file, libs.pdfjsLib);
    } else if (ext === 'docx') {
        if (!libs.JSZip) throw new DocExtractionError('DOCX library not loaded.');
        raw = await extractDocx(file, libs.JSZip);
    } else if (ext === 'html' || ext === 'htm') {
        raw = await extractHtml(file);
    } else if (['txt', 'md', 'csv', 'text', 'log'].includes(ext)) {
        raw = await readAs(file, 'text');
    } else {
        throw new DocExtractionError(
            `.${ext} isn't supported. Upload a PDF, Word (.docx), text, markdown, CSV, or HTML file — or paste the text.`
        );
    }
    return checkLength(raw, file.name);
}

/** Which static-resource library an extension needs (null = none). */
export function requiredLibFor(fileName) {
    const ext = ((fileName || '').split('.').pop() || '').toLowerCase();
    if (ext === 'pdf') return 'pdfjs';
    if (ext === 'docx') return 'jszip';
    return null;
}
