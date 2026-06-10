/**
 * @description Brand form-management hub for the Account record page. Lets an
 *  onboarding admin stand up a brand's forms without engineering: see the
 *  templates in this brand's Scope partition, create a blank one, clone an
 *  existing one, import from JSON, and flip Draft<->Active.
 *
 *  Brand <-> forms linkage is the Scope__c partition key. The Account carries
 *  Form_Scope__c; templates created/cloned/imported here are stamped to match.
 *  Until the Account has a Form_Scope__c, the hub shows a one-field setup step
 *  (the start of "onboard a new brand"). Renaming the Account never orphans the
 *  forms because the partition key lives on Form_Scope__c, independent of Name.
 *
 *  @author Field Forms
 */
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { loadScript } from 'lightning/platformResourceLoader';
import JSZIP_RESOURCE from '@salesforce/resourceUrl/jszip';
import PDFJS_RESOURCE from '@salesforce/resourceUrl/pdfjs';
import PDFJS_WORKER_RESOURCE from '@salesforce/resourceUrl/pdfjsworker';
import { reduceError } from 'c/nfCommonUtility';
import { extractDocumentText, requiredLibFor, DocExtractionError } from './docTextExtractor';

import getBrandContext from '@salesforce/apex/NeuraFormBrandController.getBrandContext';
import setAccountScope from '@salesforce/apex/NeuraFormBrandController.setAccountScope';
import listTemplatesForScope from '@salesforce/apex/NeuraFormBrandController.listTemplatesForScope';
import listClonableTemplates from '@salesforce/apex/NeuraFormBrandController.listClonableTemplates';
import createBlankTemplate from '@salesforce/apex/NeuraFormBrandController.createBlankTemplate';
import cloneTemplate from '@salesforce/apex/NeuraFormBrandController.cloneTemplate';
import assignScope from '@salesforce/apex/NeuraFormBrandController.assignScope';
import setTemplateStatus from '@salesforce/apex/NeuraFormBrandController.setTemplateStatus';
import generateTemplateFromDocument from '@salesforce/apex/NeuraFormAIController.generateTemplateFromDocument';
import draftOutputTemplateFromDocument from '@salesforce/apex/NeuraFormAIController.draftOutputTemplateFromDocument';

const ACTION_EDIT = 'edit';
const ACTION_CLONE = 'clone';
const ACTION_ACTIVATE = 'activate';
const ACTION_DEACTIVATE = 'deactivate';
const ACTION_RETIRE = 'retire';
const ACTION_WORK_TYPES = 'worktypes';

const COLUMNS = [
    { label: 'Form Name', fieldName: 'Name', type: 'text', wrapText: true },
    {
        label: 'Status',
        fieldName: 'Status__c',
        type: 'text',
        cellAttributes: { class: { fieldName: 'statusCellClass' } },
        fixedWidth: 110
    },
    { label: 'Scoring', fieldName: 'Scoring_Enabled__c', type: 'boolean', fixedWidth: 90 },
    { label: 'Max Score', fieldName: 'Max_Score__c', type: 'number', fixedWidth: 110 },
    {
        label: 'Last Modified',
        fieldName: 'LastModifiedDate',
        type: 'date',
        typeAttributes: {
            year: 'numeric', month: 'short', day: '2-digit',
            hour: '2-digit', minute: '2-digit'
        }
    },
    { type: 'action', typeAttributes: { rowActions: { fieldName: 'rowActions' } } }
];

export default class NeuraFormBrandHub extends NavigationMixin(LightningElement) {
    @api recordId; // Account Id

    columns = COLUMNS;
    templates = [];
    loading = false;

    // --- modal state -------------------------------------------------------
    showNewModal = false;
    showCloneModal = false;
    showImportModal = false;
    showScopeSetup = false;
    showDocModal = false;
    showWorkTypesModal = false;
    workTypeTemplateId;
    workTypeTemplateName = '';
    workTypeTemplateStatus;

    // --- import-from-document (AI draft) ---
    docText = '';
    docContext = '';
    docBusy = false;
    alsoDraftTemplate = true; // also draft the branded report output template

    newName = '';
    cloneName = '';
    cloneSourceId;
    scopeDraft = '';

    clonableOptions = [];

    _wiredTemplates; // cached wire result for refreshApex

    // Plain reactive fields (NOT getters) so the templates wire's `$scope`
    // reactive parameter resolves off a simple field. Populated from the brand
    // context Apex wire below.
    scope;          // brand partition key, from Account.Form_Scope__c
    brandName = '';

    _wiredBrand; // cached wire result for refreshApex after saveScope

    // Whether the brand-context wire has resolved at least once. Without it
    // the template treats "still loading" as "no scope" and flashes the
    // "Onboard <blank> for Field Forms" setup prompt at every already-
    // onboarded account while the wire is in flight.
    contextLoaded = false;

    // --- Account / scope ---------------------------------------------------
    // Read via Apex (not lightning/uiRecordApi getRecord): this component uses
    // NavigationMixin, and NavigationMixin + a uiRecordApi wire adapter trips an
    // LWC compiler false-positive (LWC1503) in this API version.
    @wire(getBrandContext, { accountId: '$recordId' })
    wiredBrand(result) {
        this._wiredBrand = result;
        if (result.data) {
            this.contextLoaded = true;
            this.scope = result.data.Form_Scope__c;
            this.brandName = result.data.Name || '';
        } else if (result.error) {
            this.contextLoaded = true;
            this.toastError('Could not load account', reduceError(result.error));
        }
    }

    get hasScope() {
        return !!this.scope;
    }

    get showScopePrompt() {
        return this.contextLoaded && !this.hasScope;
    }

    get contextLoading() {
        return !this.contextLoaded;
    }

    // --- templates list ----------------------------------------------------
    @wire(listTemplatesForScope, { scope: '$scope' })
    wiredTemplates(result) {
        this._wiredTemplates = result;
        if (result.data) {
            this.templates = result.data.map((t) => ({
                ...t,
                rowActions: this.actionsFor(t),
                statusCellClass: this.statusClassFor(t.Status__c)
            }));
        } else if (result.error) {
            this.toastError('Could not load forms', reduceError(result.error));
        }
    }

    actionsFor(tpl) {
        const actions = [{ label: 'Edit in builder', name: ACTION_EDIT }];
        if (tpl.Status__c === 'Active') {
            actions.push({ label: 'Deactivate (set Draft)', name: ACTION_DEACTIVATE });
        } else if (tpl.Status__c === 'Draft') {
            actions.push({ label: 'Activate', name: ACTION_ACTIVATE });
        }
        actions.push({ label: 'Assign to Work Types', name: ACTION_WORK_TYPES });
        actions.push({ label: 'Clone', name: ACTION_CLONE });
        if (tpl.Status__c !== 'Retired') {
            actions.push({ label: 'Retire', name: ACTION_RETIRE });
        }
        return actions;
    }

    statusClassFor(status) {
        if (status === 'Active') return 'slds-text-color_success';
        if (status === 'Retired') return 'slds-text-color_weak';
        return ''; // Draft – default
    }

    get hasTemplates() {
        return this.templates && this.templates.length > 0;
    }

    get showEmptyState() {
        return this.hasScope && !this.loading && !this.hasTemplates;
    }

    // --- modal a11y ----------------------------------------------------------
    // SLDS modal contract: focus moves into the dialog on open and Escape
    // closes it. The hand-rolled sections here don't get that for free.
    _pendingModalFocus = false;

    renderedCallback() {
        if (!this._pendingModalFocus) return;
        const el = this.template.querySelector(
            '.slds-modal lightning-input, .slds-modal lightning-textarea, .slds-modal lightning-combobox'
        );
        if (el && typeof el.focus === 'function') {
            el.focus();
            this._pendingModalFocus = false;
        }
    }

    handleModalKeydown(event) {
        if (event.key !== 'Escape') return;
        event.stopPropagation();
        // closeDocImport keeps its own busy no-op guard.
        if (this.showDocModal) { this.closeDocImport(); return; }
        if (this.showWorkTypesModal) this.closeWorkTypes();
        if (this.showScopeSetup) this.closeScopeSetup();
        if (this.showNewModal) this.closeNew();
        if (this.showCloneModal) this.closeClone();
        if (this.showImportModal) this.closeImport();
    }

    closeWorkTypes() {
        this.showWorkTypesModal = false;
    }

    // --- scope setup (un-onboarded brand) ----------------------------------
    handleScopeDraftChange(event) {
        this.scopeDraft = event.target.value;
    }

    suggestScope() {
        // Default the partition key to an upper-snake of the brand name, which
        // an admin can override. Keeps keys readable (e.g. "BURGER_KING").
        return (this.brandName || '')
            .toUpperCase()
            .replace(/[^A-Z0-9]+/g, '_')
            .replace(/^_+|_+$/g, '')
            .slice(0, 80);
    }

    openScopeSetup() {
        this._pendingModalFocus = true;
        this.scopeDraft = this.scope || this.suggestScope();
        this.showScopeSetup = true;
    }

    closeScopeSetup() {
        this.showScopeSetup = false;
    }

    async saveScope() {
        const value = (this.scopeDraft || '').trim();
        if (!value) {
            this.toastError('Scope required', 'Enter a brand scope key (e.g. BURGER_KING).');
            return;
        }
        this.loading = true;
        try {
            await setAccountScope({ accountId: this.recordId, scope: value });
            this.showScopeSetup = false;
            this.toastSuccess('Brand ready', `Forms for this brand use scope "${value}".`);
            // Refresh the brand context so `scope` updates, which in turn
            // re-runs the templates wire on the new partition.
            await refreshApex(this._wiredBrand);
        } catch (error) {
            this.toastError('Could not save scope', reduceError(error));
        } finally {
            this.loading = false;
        }
    }

    // --- new blank form ----------------------------------------------------
    openNew() {
        this._pendingModalFocus = true;
        this.newName = '';
        this.showNewModal = true;
    }
    closeNew() {
        this.showNewModal = false;
    }
    handleNewNameChange(event) {
        this.newName = event.target.value;
    }
    async createNew() {
        const name = (this.newName || '').trim();
        if (!name) {
            this.toastError('Name required', 'Enter a name for the new form.');
            return;
        }
        this.loading = true;
        try {
            const tpl = await createBlankTemplate({ name, scope: this.scope });
            this.showNewModal = false;
            this.navigateToBuilder(tpl.Id);
        } catch (error) {
            this.toastError('Could not create form', reduceError(error));
        } finally {
            this.loading = false;
        }
    }

    // --- clone -------------------------------------------------------------
    async openClone() {
        this._pendingModalFocus = true;
        this.cloneName = '';
        this.cloneSourceId = undefined;
        this.showCloneModal = true;
        try {
            const rows = await listClonableTemplates({ scope: this.scope });
            this.clonableOptions = (rows || []).map((t) => ({
                label: t.Scope__c ? t.Name : `${t.Name} (global)`,
                value: t.Id
            }));
        } catch (error) {
            this.toastError('Could not load templates', reduceError(error));
        }
    }
    closeClone() {
        this.showCloneModal = false;
    }
    handleCloneSourceChange(event) {
        this.cloneSourceId = event.detail.value;
    }
    handleCloneNameChange(event) {
        this.cloneName = event.target.value;
    }
    async doClone() {
        if (!this.cloneSourceId) {
            this.toastError('Pick a template', 'Choose a template to clone from.');
            return;
        }
        this.loading = true;
        try {
            const tpl = await cloneTemplate({
                sourceId: this.cloneSourceId,
                newName: (this.cloneName || '').trim(),
                scope: this.scope
            });
            this.showCloneModal = false;
            await this.refresh();
            this.navigateToBuilder(tpl.Id);
        } catch (error) {
            this.toastError('Clone failed', reduceError(error));
        } finally {
            this.loading = false;
        }
    }

    // --- import ------------------------------------------------------------
    openImport() {
        this._pendingModalFocus = true;
        this.showImportModal = true;
    }
    closeImport() {
        this.showImportModal = false;
    }
    async handleImported(event) {
        // neuraFormImport already created the templates; stamp them into this
        // brand's scope (importing leaves them Draft) and refresh the list.
        const ids = event.detail && event.detail.templateIds;
        if (ids && ids.length) {
            try {
                await assignScope({ templateIds: ids, scope: this.scope });
                await this.refresh();
                this.toastSuccess('Imported to brand', `${ids.length} form(s) added as Draft.`);
            } catch (error) {
                this.toastError('Imported, but scope not set', reduceError(error));
            }
        }
        this.showImportModal = false;
    }

    // --- import from customer document (AI draft, human polish) ------------
    // The customer sends a Word/PDF audit form they want us to follow. Binary
    // text extraction happens upstream; here the admin pastes the extracted
    // text and the LLM drafts a Field Forms template in this brand's scope,
    // which then opens in the builder for review/polish.
    openDocImport() {
        this._pendingModalFocus = true;
        this.docText = '';
        this.docContext = '';
        this.docFileName = '';
        this.extracting = false;
        this.showDocModal = true;
    }

    // ----- file upload -> client-side text extraction -----------------------
    // The customer hands over a PDF/Word audit form; the admin uploads it
    // here and the extracted text lands in the textarea below as an
    // EDITABLE preview — same review-then-draft pipeline, the paste path
    // stays as the fallback for anything we can't extract (scans, .doc).
    docFileName = '';
    extracting = false;
    _libsLoaded = {};

    get docFileLabel() {
        return this.docFileName ? `Loaded: ${this.docFileName}` : '';
    }

    async _ensureLib(name) {
        if (this._libsLoaded[name]) return;
        if (name === 'jszip') {
            await loadScript(this, JSZIP_RESOURCE);
        } else if (name === 'pdfjs') {
            await loadScript(this, PDFJS_RESOURCE);
            // pdf.js refuses to run without a worker source; point it at
            // the vendored worker (same-origin static resource).
            window.pdfjsLib.GlobalWorkerOptions.workerSrc = PDFJS_WORKER_RESOURCE;
        }
        this._libsLoaded[name] = true;
    }

    async handleDocFileChange(event) {
        const file = event.target.files && event.target.files[0];
        if (!file) return;
        if (file.size > 10 * 1024 * 1024) {
            this.toastError('File too large', 'Documents over 10 MB need their text pasted instead.');
            return;
        }
        this.extracting = true;
        try {
            const lib = requiredLibFor(file.name);
            if (lib) await this._ensureLib(lib);
            const result = await extractDocumentText(file, {
                JSZip: window.JSZip,
                pdfjsLib: window.pdfjsLib
            });
            this.docText = result.text;
            this.docFileName = file.name;
            if (result.truncated) {
                this.toastError(
                    'Document truncated',
                    'Only the first ~200,000 characters were kept — review the text below before drafting.'
                );
            }
        } catch (error) {
            // Full error to the console — extraction failures inside the
            // vendored libs surface as cryptic one-liners in the toast and
            // the stack is what actually identifies them.
            console.error('Document extraction failed', error);
            const message = error instanceof DocExtractionError
                ? error.message
                : reduceError(error);
            this.toastError('Could not read document', message);
        } finally {
            this.extracting = false;
        }
    }
    closeDocImport() {
        if (this.docBusy) return;
        this.showDocModal = false;
    }
    handleDocTextChange(event) {
        this.docText = event.target.value;
    }
    handleDocContextChange(event) {
        this.docContext = event.target.value;
    }
    handleAlsoTemplateChange(event) {
        this.alsoDraftTemplate = event.target.checked;
    }
    get disableDocImport() {
        return this.docBusy || this.extracting || (this.docText || '').trim().length < 20;
    }
    get docImportLabel() {
        return this.docBusy ? 'Drafting…' : 'Draft form';
    }
    async doDocImport() {
        if (this.disableDocImport) return;
        this.docBusy = true;
        this.loading = true;
        const documentText = (this.docText || '').trim();
        const context = (this.docContext || '').trim();
        try {
            // 1) Structure: draft the fillable form (its own transaction).
            const result = await generateTemplateFromDocument({
                documentText, scope: this.scope, context
            });

            // 2) Presentation: optionally draft the branded report output
            //    template from the same doc. This is a SEPARATE Apex call (and
            //    thus a separate transaction) so its LLM callout doesn't trip
            //    the callout-after-DML limit from step 1's import.
            let extra = '';
            if (this.alsoDraftTemplate) {
                try {
                    const tpl = await draftOutputTemplateFromDocument({
                        documentText, scope: this.scope, context
                    });
                    extra = ` Branded report template drafted (${tpl.htmlLength} chars).`;
                } catch (e) {
                    extra = ` (Form created; report-template draft failed: ${reduceError(e)})`;
                }
            }

            this.showDocModal = false;
            await this.refresh();
            this.toastSuccess(
                'Drafted from document',
                `Created "${result.formTemplateName}" — ${result.pageCount} page(s), ` +
                `${result.questionCount} question(s).${extra} Review and polish in the builder.`
            );
            this.navigateToBuilder(result.formTemplateId);
        } catch (error) {
            this.toastError('Could not draft form', reduceError(error));
        } finally {
            this.docBusy = false;
            this.loading = false;
        }
    }

    // --- row actions -------------------------------------------------------
    async handleRowAction(event) {
        const action = event.detail.action.name;
        const row = event.detail.row;
        switch (action) {
            case ACTION_EDIT:
                this.navigateToBuilder(row.Id);
                break;
            case ACTION_ACTIVATE:
                await this.changeStatus(row.Id, 'Active');
                break;
            case ACTION_DEACTIVATE:
                await this.changeStatus(row.Id, 'Draft');
                break;
            case ACTION_RETIRE:
                await this.changeStatus(row.Id, 'Retired');
                break;
            case ACTION_WORK_TYPES:
                this.workTypeTemplateId = row.Id;
                this.workTypeTemplateName = row.Name;
                this.workTypeTemplateStatus = row.Status__c;
                this.showWorkTypesModal = true;
                break;
            case ACTION_CLONE:
                this.cloneName = `${row.Name} (copy)`;
                this.cloneSourceId = row.Id;
                this.showCloneModal = true;
                this.clonableOptions = [{ label: row.Name, value: row.Id }];
                break;
            default:
                break;
        }
    }

    async changeStatus(templateId, status) {
        this.loading = true;
        try {
            await setTemplateStatus({ templateId, status });
            await this.refresh();
            this.toastSuccess('Status updated', `Form set to ${status}.`);
        } catch (error) {
            this.toastError('Could not update status', reduceError(error));
        } finally {
            this.loading = false;
        }
    }

    // --- helpers -----------------------------------------------------------
    navigateToBuilder(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: 'Form_Template__c',
                actionName: 'view'
            }
        });
    }

    async refresh() {
        if (this._wiredTemplates) {
            await refreshApex(this._wiredTemplates);
        }
    }

    toastSuccess(title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'success' }));
    }
    toastError(title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error' }));
    }
}
