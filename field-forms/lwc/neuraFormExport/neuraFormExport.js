import { LightningElement, wire } from 'lwc';
import fetchTemplatesData from '@salesforce/apex/neuraFormExportController.fetchTemplatesData';
import listAccessibleTemplates from '@salesforce/apex/neuraFormExportController.listAccessibleTemplates';
import { getListInfoByName } from 'lightning/uiListsApi';
import { getListUi } from 'lightning/uiListApi';
import FORM_TEMPLATE_OBJECT from '@salesforce/schema/Form_Template__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceError } from 'c/nfCommonUtility';

export default class NeuraFormExport extends LightningElement {
    columns = [
        { label: 'Name', fieldName: 'Name', type: 'text', sortable: true },
        { label: 'External Reference', fieldName: 'External_Reference__c', type: 'text', sortable: true }
    ];
    records;
    selectedTemplateIds = [];
    loading = false;
    usingFallback = false;
    fallbackMessage;

    get templatesNotSelected() {
        return this.selectedTemplateIds.length <= 0;
    }

    get buttonLabel() {
        return 'Export Selected Templates ' + (this.selectedTemplateIds.length > 0 ? '(' + this.selectedTemplateIds.length + ')' : '');
    }

    // Primary path: drive the datatable off the standard List View metadata
    // so admins see the columns they configured. The wire's column list
    // overwrites the default columns above.
    @wire(getListInfoByName, { objectApiName: FORM_TEMPLATE_OBJECT.objectApiName, listViewApiName: 'All' })
    listViewInfo({ error, data }) {
        if (data) {
            this.columns = data.displayColumns.map(column => ({
                label: column.label,
                fieldName: column.fieldApiName,
                type: this.determineType(column.type),
                sortable: true
            }));
        } else if (error) {
            this.activateFallback(error);
        }
    }

    @wire(getListUi, { objectApiName: FORM_TEMPLATE_OBJECT.objectApiName, listViewApiName: 'All' })
    listViewData({ error, data }) {
        if (data) {
            this.records = data.records.records.map(record => ({
                id: record.id,
                ...Object.keys(record.fields).reduce((acc, fieldName) => {
                    const field = record.fields[fieldName];
                    return {
                        ...acc,
                        [fieldName]: field.displayValue !== undefined && field.displayValue !== null ? field.displayValue : field.value
                    };
                }, {})
            }));
        } else if (error) {
            this.activateFallback(error);
        }
    }

    // Secondary path: query templates via Apex when the List View wires
    // fail (deleted list view, restricted access, etc.).
    @wire(listAccessibleTemplates)
    fallbackTemplates({ error, data }) {
        if (!this.usingFallback) return;
        if (data) {
            this.records = data;
        } else if (error) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Could not load templates',
                message: reduceError(error),
                variant: 'error'
            }));
        }
    }

    activateFallback(error) {
        if (this.usingFallback) return;
        this.usingFallback = true;
        this.fallbackMessage = 'Standard "All" list view was not available; showing accessible templates from a direct query.';
        this.records = undefined;
        console.warn('neuraFormExport list view fallback engaged', error);
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedTemplateIds = selectedRows.map(row => row.Id || row.id);
    }

    handleExport() {
        this.loading = true;
        fetchTemplatesData({ templateIds: this.selectedTemplateIds })
            .then(result => {
                const blob = new Blob([result], { type: 'application/json' });
                const link = document.createElement('a');
                link.href = window.URL.createObjectURL(blob);
                link.download = 'ExportedTemplates.json';
                link.click();

                this.dispatchEvent(new ShowToastEvent({
                    title: 'Success',
                    message: 'Data exported successfully!',
                    variant: 'success'
                }));
                this.loading = false;
            })
            .catch(error => {
                this.loading = false;
                this.dispatchEvent(new ShowToastEvent({
                    title: 'Error exporting data',
                    message: reduceError(error),
                    variant: 'error'
                }));
            });
    }

    // Map Salesforce field types to lightning-datatable types.
    determineType(fieldType) {
        switch (fieldType) {
            case 'string':
            case 'email':
            case 'text':
            case 'textarea':
            case 'phone':
            case 'url':
                return 'text';
            case 'boolean':
                return 'boolean';
            case 'currency':
                return 'currency';
            case 'date':
                return 'date';
            case 'datetime':
                return 'date-local';
            case 'percent':
            case 'double':
            case 'integer':
                return 'number';
            default:
                return 'text';
        }
    }
}
