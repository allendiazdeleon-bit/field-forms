/**
 * Jest mock for lightning/mediaUtils. Used by imageCapture for image
 * processing (resize / compress before upload). Not bundled in
 * sfdx-lwc-jest defaults.
 */
export function processImage(file /*, options */) {
    // Pass-through stub — return the file unchanged so callers can
    // continue their flow. Production behavior is platform-driven.
    return Promise.resolve(file);
}
