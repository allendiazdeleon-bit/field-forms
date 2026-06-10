import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceError } from 'c/nfCommonUtility';
import getWorkTypeAssignments from '@salesforce/apex/NeuraFormBrandController.getWorkTypeAssignments';
import searchWorkTypes from '@salesforce/apex/NeuraFormBrandController.searchWorkTypes';
import assignWorkType from '@salesforce/apex/NeuraFormBrandController.assignWorkType';
import removeWorkTypeAssignment from '@salesforce/apex/NeuraFormBrandController.removeWorkTypeAssignment';

/**
 * "Appears on these jobs" — the Default_Form__c mappings for one template,
 * editable inline. Shared by the builder's Form settings panel and the
 * brand hub's "Assign to Work Types" row action, so admins wire forms to
 * work without ever touching the raw mapping object.
 *
 * Shape: pills for current work-type assignments (x to remove) + a
 * debounced search box whose results add on click. Assignment is
 * idempotent server-side.
 */
export default class NeuraFormWorkTypeAssignments extends LightningElement {
    @api formTemplateId;
    // The hub passes the template's status so we can warn that Draft forms
    // don't provision; the builder panel may omit it.
    @api templateStatus;

    @track assignments = [];
    @track results = [];
    searchTerm = '';
    loading = false;
    busy = false;
    _searchTimer;
    _loadedFor;

    connectedCallback() {
        this.load();
    }

    renderedCallback() {
        // The hub reuses one instance across row-action opens with a new
        // formTemplateId — reload when the target changes.
        if (this.formTemplateId && this._loadedFor !== this.formTemplateId) {
            this.load();
        }
    }

    @api
    async load() {
        if (!this.formTemplateId) return;
        this._loadedFor = this.formTemplateId;
        this.loading = true;
        try {
            this.assignments = await getWorkTypeAssignments({ formTemplateId: this.formTemplateId });
        } catch (error) {
            this.toastError('Could not load work type assignments', reduceError(error));
        } finally {
            this.loading = false;
        }
    }

    get hasAssignments() {
        return this.assignments.length > 0;
    }

    get showDraftWarning() {
        return this.hasAssignments && this.templateStatus && this.templateStatus !== 'Active';
    }

    get hasResults() {
        return this.results.length > 0;
    }

    get emptyLine() {
        return this.loading ? '' : 'Not assigned to any work types yet — it only appears where a tech adds it manually.';
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
        clearTimeout(this._searchTimer);
        if (this.searchTerm.trim().length < 2) {
            this.results = [];
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this._searchTimer = setTimeout(() => this.runSearch(), 300);
    }

    async runSearch() {
        try {
            const found = await searchWorkTypes({ searchTerm: this.searchTerm.trim() });
            const assigned = new Set(this.assignments.map((a) => a.workTypeId));
            this.results = (found || []).filter((r) => !assigned.has(r.workTypeId));
        } catch (error) {
            this.toastError('Work type search failed', reduceError(error));
        }
    }

    async handleAdd(event) {
        const workTypeId = event.currentTarget.dataset.id;
        this.busy = true;
        try {
            await assignWorkType({ formTemplateId: this.formTemplateId, workTypeId });
            this.searchTerm = '';
            this.results = [];
            await this.load();
            this.dispatchEvent(new CustomEvent('assignmentschange'));
        } catch (error) {
            this.toastError('Could not assign work type', reduceError(error));
        } finally {
            this.busy = false;
        }
    }

    async handleRemove(event) {
        const defaultFormId = event.currentTarget.dataset.id;
        this.busy = true;
        try {
            await removeWorkTypeAssignment({ defaultFormId });
            await this.load();
            this.dispatchEvent(new CustomEvent('assignmentschange'));
        } catch (error) {
            this.toastError('Could not remove assignment', reduceError(error));
        } finally {
            this.busy = false;
        }
    }

    toastError(title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error' }));
    }
}
