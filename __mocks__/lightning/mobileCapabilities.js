/**
 * Jest mock for lightning/mobileCapabilities.
 *
 * Why this file exists:
 *   neuraFormAnswerInputScanBarcode imports `getBarcodeScanner` from
 *   `lightning/mobileCapabilities`, which is provided by Salesforce at
 *   runtime in the FSL Mobile WebView. sfdx-lwc-jest doesn't bundle a
 *   stub for it. Without this mock, any test that transitively imports
 *   a scan-barcode-containing component crashes during module
 *   resolution — including the cross-cutting neuraFormAnswer router
 *   smoke test.
 *
 * Mock contract:
 *   getBarcodeScanner() returns an object whose .isAvailable() returns
 *   false (matches the desktop / non-FSL runtime behavior) and whose
 *   .beginCapture() rejects, simulating "no scanner available."
 */
export function getBarcodeScanner() {
    return {
        isAvailable: () => false,
        beginCapture: () => Promise.reject(new Error('Barcode scanner not available in test environment')),
        endCapture: () => undefined,
        scannerTypes: {
            BARCODE: 'BARCODE',
            QR: 'QR'
        },
        barcodeTypes: {
            EAN_13: 'EAN_13',
            UPC_A: 'UPC_A',
            QR: 'QR'
        }
    };
}
