import { LightningElement } from 'lwc';
import importTemplates from '@salesforce/apex/neuraFormExportController.importTemplates';
import importTemplatesAsNew from '@salesforce/apex/neuraFormExportController.importTemplatesAsNew';
import previewImport from '@salesforce/apex/neuraFormExportController.previewImport';
import getSampleImportJson from '@salesforce/apex/neuraFormExportController.getSampleImportJson';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import { reduceError } from 'c/nfCommonUtility';

// Reject files larger than this. The server-side Apex heap limit is 6 MB and
// FileReader pulls the entire content into the browser tab; 5 MB is a safe
// ceiling that leaves headroom for the round trip.
const MAX_IMPORT_BYTES = 5 * 1024 * 1024;

export default class NeuraFormImport extends LightningElement {
    importedTemplates;
    importedTemplateIds = [];
    importWarnings = [];
    importCreatedCount = 0;
    importUpdatedCount = 0;
    fileName;
    fileContents;
    parsedTemplateCount = 0;
    error;
    loading = false;
    importAsNew = false;

    columns = [
        { label: 'Template Name', fieldName: 'Name', type: 'text' },
        { label: 'Template Id', fieldName: 'Id', type: 'text' }
    ];

    get hasWarnings() {
        return this.importWarnings && this.importWarnings.length > 0;
    }

    // LWC's template syntax doesn't allow {idx} as a for:each key. Wrap each
    // string warning in { id, text } so the template can key off a stable
    // property on the iterated item instead of the index.
    get importWarningItems() {
        return (this.importWarnings || []).map((w, i) => ({ id: 'iw_' + i, text: w }));
    }
    get previewCollisionItems() {
        return (this.preview?.nameCollisions || []).map((w, i) => ({ id: 'pc_' + i, text: w }));
    }
    get previewWarningItems() {
        return (this.preview?.warnings || []).map((w, i) => ({ id: 'pw_' + i, text: w }));
    }

    get importButtonLabel() {
        return this.parsedTemplateCount > 0
            ? `Import ${this.parsedTemplateCount} template(s)`
            : 'Import';
    }

    get countSummary() {
        return `Created ${this.importCreatedCount} • Updated ${this.importUpdatedCount}`;
    }

    handleFileChange(event) {
        // Reset prior state on each new file pick.
        this.fileContents = undefined;
        this.fileName = '';
        this.parsedTemplateCount = 0;

        const file = event.target.files[0];
        if (!file) return;

        if (file.size > MAX_IMPORT_BYTES) {
            this.toastError(
                'File too large',
                `Max import size is ${Math.round(MAX_IMPORT_BYTES / 1024 / 1024)} MB. ` +
                `This file is ${(file.size / 1024 / 1024).toFixed(1)} MB.`
            );
            return;
        }

        const fileReader = new FileReader();
        fileReader.onload = () => {
            const contents = fileReader.result;
            // Validate JSON client-side before letting the user click Import.
            // Round-tripping a malformed file just to get a useless server
            // error is bad UX.
            try {
                const parsed = JSON.parse(contents);
                if (!Array.isArray(parsed)) {
                    throw new Error('Top-level JSON must be an array of template wrappers.');
                }
                this.parsedTemplateCount = parsed.length;
                this.fileContents = contents;
                this.fileName = file.name;
            } catch (err) {
                this.toastError('Invalid JSON', err.message || String(err));
            }
        };
        fileReader.onerror = () => {
            this.toastError('Could not read file', fileReader.error?.message || 'Unknown read error.');
        };
        fileReader.readAsText(file);
    }

    handleImportAsNewChange(event) {
        this.importAsNew = event.target.checked;
    }

    // --- Preview (dry-run) state -------------------------------------------
    preview;
    showPreview = false;
    previewing = false;

    get hasPreviewWarnings() {
        return this.preview?.warnings?.length > 0;
    }
    get hasPreviewCollisions() {
        return this.preview?.nameCollisions?.length > 0;
    }

    async handlePreview() {
        if (!this.fileContents) {
            this.toastError('Select a file', 'Choose a JSON file before previewing.');
            return;
        }
        this.previewing = true;
        try {
            this.preview = await previewImport({ jsonContent: this.fileContents });
            this.showPreview = true;
        } catch (err) {
            this.toastError('Preview failed', reduceError(err));
        } finally {
            this.previewing = false;
        }
    }

    handleClosePreview() {
        this.showPreview = false;
    }

    // --- Sample JSON download ----------------------------------------------
    async handleDownloadSample() {
        try {
            const sample = await getSampleImportJson();
            const blob = new Blob([sample], { type: 'application/json' });
            const link = document.createElement('a');
            link.href = window.URL.createObjectURL(blob);
            link.download = 'sample-field-forms-import.json';
            link.click();
        } catch (err) {
            this.toastError('Could not build sample', reduceError(err));
        }
    }

    async importData() {
        if (!this.fileContents) {
            this.toastError('Select a file', 'Choose a JSON file before clicking Import.');
            return;
        }

        const confirmMsg = this.importAsNew
            ? `Create ${this.parsedTemplateCount} new template(s) in this org. Continue?`
            : `Import ${this.parsedTemplateCount} template(s). Existing templates with the same External Reference will be updated. Continue?`;
        const proceed = await LightningConfirm.open({
            message: confirmMsg,
            label: 'Confirm Import',
            variant: 'header',
            theme: 'warning'
        });
        if (!proceed) return;

        this.loading = true;
        this.importedTemplates = undefined;
        this.importedTemplateIds = [];
        this.importWarnings = [];
        this.importCreatedCount = 0;
        this.importUpdatedCount = 0;

        try {
            const apexCall = this.importAsNew ? importTemplatesAsNew : importTemplates;
            // Apex now returns an ImportResult { templates, createdCount,
            // updatedCount, warnings } and does the snapshot rebuild
            // internally, so this is a single round trip - no follow-up
            // runTemplateRollup call to fail independently.
            const result = await apexCall({ jsonContent: this.fileContents });

            this.importedTemplates = result.templates || [];
            this.importedTemplateIds = this.importedTemplates.map(t => t.Id);
            this.importCreatedCount = result.createdCount || 0;
            this.importUpdatedCount = result.updatedCount || 0;
            this.importWarnings = result.warnings || [];

            if (this.importedTemplates.length === 0) {
                this.toastWarning('No templates imported', 'The file parsed but produced no records.');
            } else if (this.importWarnings.length > 0) {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Imported with warnings',
                    message: `${this.importedTemplates.length} template(s) imported. ${this.importWarnings.length} warning(s) shown below.`,
                    variant: 'warning'
                }));
            } else {
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Imported',
                    message: `${this.importedTemplates.length} template(s) imported successfully.`,
                    variant: 'success'
                }));
            }
        } catch (error) {
            this.error = error;
            this.toastError('Import failed', reduceError(error));
        } finally {
            this.loading = false;
        }
    }

    toastError(title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'error' }));
    }

    toastWarning(title, message) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant: 'warning' }));
    }
}
