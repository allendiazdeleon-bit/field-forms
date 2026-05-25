/**
 * Jest mock for lightning/modal — the LightningModal base class used by
 * neuraFormFileBulkNameUpdateModal. Not bundled in sfdx-lwc-jest's
 * default mock set, so test runs that transitively import a Modal
 * subclass crash during module resolution.
 *
 * Mock is a no-op base class — extends LightningElement so subclass
 * behavior compiles; .open() / .close() are stubbed for any caller.
 */
import { LightningElement } from 'lwc';

export default class LightningModal extends LightningElement {
    static open() {
        return Promise.resolve(null);
    }
    close() {
        return undefined;
    }
}
