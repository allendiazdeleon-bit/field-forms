import { LightningElement, api, wire, track } from 'lwc';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';

/**
 * Lookup — pick a Salesforce record from the host's related list.
 *
 * The canonical multi-asset case: a WorkOrder has N WorkOrderLineItems,
 * and a question needs to record "this answer applies to which line
 * item?" Today admins fake this with multi-copies of the same question;
 * this component lets a single question reference any of the host's
 * related records.
 *
 * Public API:
 *   @api parentRecordId       host record id (passed down from the renderer)
 *   @api relatedListApiName   relationship API name (e.g. 'WorkOrderLineItems')
 *   @api childObjectApiName   API name of the child object (e.g. 'WorkOrderLineItem')
 *   @api displayField         field to render in the picker (e.g. 'LineItemNumber')
 *   @api val                  current selected record id
 *   @api placeholder          combobox placeholder text
 *
 * Emits 'change' with detail { value } when the user picks a different
 * record (or clears the selection).
 *
 * FSL Mobile / offline notes:
 * - Uses lightning/uiRelatedListApi.getRelatedListRecords which IS
 *   drafts-aware and works offline as long as the related list is
 *   primed via briefcase rules. Records created/deleted while offline
 *   won't show up (platform limitation; document for admins).
 * - Fields list is materialized via lifecycle hooks (not getters) so
 *   the Komaci graph analyzer can statically detect the data flow.
 */
const FIELDS_FALLBACK = []; // fed before child object api name is known

export default class NeuraFormAnswerInputLookup extends LightningElement {
    @api parentRecordId;
    @api relatedListApiName;
    @api childObjectApiName;
    @api displayField;
    @api val;
    @api placeholder = 'Select…';

    @track _fields = FIELDS_FALLBACK;

    connectedCallback() {
        this._recomputeFields();
    }

    renderedCallback() {
        // @api props arrive via attribute binding from the renderer;
        // recompute defensively in case any landed late.
        this._recomputeFields();
    }

    _recomputeFields() {
        if (!this.childObjectApiName) {
            if (this._fields.length) this._fields = FIELDS_FALLBACK;
            return;
        }
        const next = [`${this.childObjectApiName}.Id`];
        if (this.displayField) {
            next.push(`${this.childObjectApiName}.${this.displayField}`);
        }
        // Only swap when changed, to avoid wire churn.
        const a = JSON.stringify(next);
        const b = JSON.stringify(this._fields);
        if (a !== b) this._fields = next;
    }

    @wire(getRelatedListRecords, {
        parentRecordId: '$parentRecordId',
        relatedListId: '$relatedListApiName',
        fields: '$_fields',
        pageSize: 50
    })
    relatedResult;

    // --- Render state -------------------------------------------------------

    get isConfigured() {
        return Boolean(
            this.parentRecordId &&
            this.relatedListApiName &&
            this.childObjectApiName
        );
    }

    get isLoading() {
        return this.isConfigured && !this.relatedResult;
    }

    get hasError() {
        return Boolean(this.relatedResult && this.relatedResult.error);
    }

    get errorMessage() {
        const err = this.relatedResult && this.relatedResult.error;
        if (!err) return '';
        if (Array.isArray(err.body)) {
            return err.body.map((e) => e.message).join(', ');
        }
        return (err.body && err.body.message) || err.message || 'Unable to load related records.';
    }

    get records() {
        const data = this.relatedResult && this.relatedResult.data;
        return (data && data.records) || [];
    }

    get hasOptions() {
        return this.records.length > 0;
    }

    get options() {
        const displayField = this.displayField;
        return this.records.map((r) => {
            const id = r.id || r.Id;
            const label = this._readField(r, displayField) || id;
            return { label: String(label), value: id };
        });
    }

    _readField(record, field) {
        if (!record || !field) return '';
        const fields = record.fields || {};
        const entry = fields[field];
        if (entry && Object.prototype.hasOwnProperty.call(entry, 'value')) {
            return entry.value;
        }
        // Fallback for records that come back without the wrapping fields/value structure
        return record[field] || '';
    }

    handleChange(event) {
        const value = event && event.detail && event.detail.value;
        this.dispatchEvent(new CustomEvent('change', {
            detail: { value: value || null },
            bubbles: true,
            composed: true
        }));
    }
}
