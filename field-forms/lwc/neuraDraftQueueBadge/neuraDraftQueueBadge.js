import { LightningElement, api } from 'lwc';

/**
 * Sync-pending indicator for the FSL Mobile shell.
 *
 * Why this exists:
 *   The FSL Mobile platform deliberately does NOT expose an online/offline
 *   signal — by design, per Salesforce. So instead of "you are offline,"
 *   this badge answers the question a technician actually has: "is my
 *   work safe and will it sync?" — by surfacing the local draft-queue
 *   state (count + last sync time + any sync errors).
 *
 * Public API (driven by parent):
 *   @api pendingCount   number of records in the local draft queue
 *   @api hasError       true if last sync attempt failed
 *   @api lastSyncedAt   ISO timestamp string of last successful sync, or null
 *
 * Three visible states:
 *   "All synced"            pendingCount === 0 && !hasError
 *   "N pending — will sync" pendingCount > 0 && !hasError
 *   "Sync issue"            hasError
 */
export default class NeuraDraftQueueBadge extends LightningElement {
    @api pendingCount = 0;
    @api hasError = false;
    @api lastSyncedAt;

    get isClean() { return !this.hasError && Number(this.pendingCount) === 0; }
    get isPending() { return !this.hasError && Number(this.pendingCount) > 0; }
    get isError() { return Boolean(this.hasError); }

    get badgeClass() {
        if (this.isError) return 'badge badge_error';
        if (this.isPending) return 'badge badge_pending';
        return 'badge badge_clean';
    }

    get iconName() {
        if (this.isError) return 'utility:warning';
        if (this.isPending) return 'utility:sync';
        return 'utility:check';
    }

    get label() {
        if (this.isError) return 'Sync issue — will retry';
        if (this.isPending) {
            const n = Number(this.pendingCount);
            return n === 1 ? '1 pending — will sync' : `${n} pending — will sync`;
        }
        return 'All synced';
    }

    get secondary() {
        if (!this.lastSyncedAt) return '';
        try {
            const d = new Date(this.lastSyncedAt);
            if (Number.isNaN(d.getTime())) return '';
            return `Last sync ${d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' })}`;
        } catch (e) {
            return '';
        }
    }
}
