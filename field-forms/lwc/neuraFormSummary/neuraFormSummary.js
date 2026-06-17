import { LightningElement, api, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getSummary from '@salesforce/apex/NeuraFormSummaryController.getSummary';
import resolveFinding from '@salesforce/apex/NeuraFormSummaryController.resolveFinding';

/** SLDS pill theme + sort metadata per severity. */
const SEV_THEME = {
    Critical: 'ffs-pill ffs-pill_critical',
    High: 'ffs-pill ffs-pill_high',
    Medium: 'ffs-pill ffs-pill_medium',
    Low: 'ffs-pill ffs-pill_low'
};

/** Anomaly status -> lightning-badge inverse theme hint. */
const ANOMALY_STATUS_CLASS = {
    New: 'ffs-status ffs-status_new',
    Reviewed: 'ffs-status ffs-status_reviewed',
    Sent: 'ffs-status ffs-status_sent',
    Dismissed: 'ffs-status ffs-status_dismissed'
};

export default class NeuraFormSummary extends LightningElement {
    @api recordId;
    /** When true, shows the Resolve action on open findings. Off by default so
     *  the same component is safe to drop on a read-only portal page. */
    @api enableActions = false;

    summary;
    error;
    _loaded = false;
    _wired;
    resolvingId;

    @wire(getSummary, { linkedFormId: '$recordId' })
    wiredSummary(result) {
        this._wired = result;
        const { data, error } = result;
        if (data) {
            this.summary = this.decorate(data);
            this.error = undefined;
            this._loaded = true;
        } else if (error) {
            this.error = this.reduceError(error);
            this.summary = undefined;
            this._loaded = true;
        }
    }

    /** Build display-ready view model (templates can't call functions w/ args). */
    decorate(data) {
        const findings = (data.findings || []).map((f) => ({
            ...f,
            sevClass: SEV_THEME[f.severity] || 'ffs-pill',
            photoLabel: f.photoRequired
                ? (f.photoAttached ? 'Photo attached' : 'Photo missing')
                : null,
            photoClass: f.photoAttached ? 'ffs-photo ffs-photo_ok' : 'ffs-photo ffs-photo_missing',
            photoIcon: f.photoAttached ? 'utility:image' : 'utility:warning',
            // Inline thumbnail + click-through to the full file preview.
            photoThumb: f.photoVersionId
                ? `/sfc/servlet.shepherd/version/download/${f.photoVersionId}`
                : null,
            photoHref: f.photoDocumentId
                ? `/lightning/r/ContentDocument/${f.photoDocumentId}/view`
                : null,
            canResolve: this.enableActions && this.isOpenStatus(f.status),
            resolving: this.resolvingId === f.id
        }));
        const anomalies = (data.anomalies || []).map((a) => ({
            ...a,
            statusClass: ANOMALY_STATUS_CLASS[a.status] || 'ffs-status',
            recurrenceLabel: `${a.recurrenceCount}× recurring`
        }));
        return { ...data, findings, anomalies };
    }

    isOpenStatus(status) {
        return status === 'Open' || status === 'In Progress';
    }

    async handleResolve(event) {
        const findingId = event.currentTarget.dataset.id;
        if (!findingId) return;
        this.resolvingId = findingId;
        this.summary = this.decorate(this._rawData());
        try {
            await resolveFinding({ findingId });
            await refreshApex(this._wired);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Finding resolved', variant: 'success'
            }));
        } catch (e) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Could not resolve finding',
                message: this.reduceError(e), variant: 'error'
            }));
        } finally {
            this.resolvingId = undefined;
            if (this._wired?.data) this.summary = this.decorate(this._wired.data);
        }
    }

    _rawData() {
        return this._wired?.data || this.summary;
    }

    get hasFindings() {
        return this.summary && this.summary.totalFindings > 0;
    }
    get hasAnomalies() {
        return this.summary && this.summary.totalAnomalies > 0;
    }
    get showScore() {
        return this.summary && this.summary.scoringEnabled && this.summary.maxScore;
    }
    get findingsHeading() {
        if (!this.summary) return 'Findings';
        const blk = this.summary.blockingFindings;
        const open = this.summary.openFindings;
        const suffix = blk > 0 ? ` · ${blk} blocking` : '';
        return `Findings (${this.summary.totalFindings}) — ${open} open${suffix}`;
    }
    get anomaliesHeading() {
        return this.summary
            ? `Anomaly Alerts (${this.summary.totalAnomalies})`
            : 'Anomaly Alerts';
    }
    get statusClass() {
        const base = 'ffs-status ';
        const st = this.summary && this.summary.status;
        if (st === 'Completed') return base + 'ffs-status_sent';
        if (st === 'In Progress') return base + 'ffs-status_reviewed';
        return base + 'ffs-status_new';
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) return error.body.map((e) => e.message).join(', ');
        if (error?.body?.message) return error.body.message;
        if (typeof error?.message === 'string') return error.message;
        return 'Unable to load the inspection summary.';
    }
}
