/**
 * Jest mock for lightning/confirm — the alert/confirm/prompt modal API
 * used by FSL-Mobile-safe components (per the FSL Mobile LWC skill,
 * toasts don't display so confirm/alert are the substitute).
 *
 * Mock: default-export a function that resolves to true (positive
 * confirmation) so flows that gate on the dialog don't deadlock.
 */
export default function LightningConfirm(/* options */) {
    return Promise.resolve(true);
}
