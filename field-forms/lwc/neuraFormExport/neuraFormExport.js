import { LightningElement, wire } from 'lwc';
import fetchTemplatesData from '@salesforce/apex/neuraFormExportController.fetchTemplatesData';
import { getListInfoByName } from 'lightning/uiListsApi';
import { getListUi } from "lightning/uiListApi";
import FORM_TEMPLATE_OBJECT from '@salesforce/schema/Form_Template__c';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceError } from 'c/nfCommonUtility';

export default class NeuraFormExport extends LightningElement {
    templates;
    columns = []; // For datatable columns
    records; // For storing fetched records
    listViewData; // For storing list view metadata
    selectedTemplateIds = [];
    loading = false;

    get templatesNotSelected() {
        return this.selectedTemplateIds.length <= 0;
    }

    get buttonLabel() {
        return 'Export Selected Templates ' + (this.selectedTemplateIds.length > 0 ? '(' + this.selectedTemplateIds.length + ')' : '');
    }
    @wire(getListInfoByName, { objectApiName: FORM_TEMPLATE_OBJECT.objectApiName, listViewApiName: 'All' })
    listViewInfo({ error, data }) {
        if (data) {
            this.listViewData = data;
            this.columns = data.displayColumns.map(column => ({
                label: column.label,
                fieldName: column.fieldApiName,
                type: this.determineType(column.type),
                sortable: true
            }));
            this.error = undefined;
        } else if (error) {
            this.listViewData = undefined;
            this.error = error;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: reduceError(error),
                    variant: 'error'
                })
            );
        }
    }

    @wire(getListUi, { objectApiName: FORM_TEMPLATE_OBJECT.objectApiName, listViewApiName: 'All' })
    listViewData({ error, data }) {
        if (data) {
            this.records = data.records.records.map(record => ({
                id: record.id,
                // Process each field to use displayValue if available, otherwise use value
                ...Object.keys(record.fields).reduce((acc, fieldName) => {
                    const field = record.fields[fieldName];
                    return {
                        ...acc,
                        [fieldName]: field.displayValue !== undefined && field.displayValue != null ? field.displayValue : field.value
                    };
                }, {})
            }));
        } else if (error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: reduceError(error),
                    variant: 'error'
                })
            );
        }
    }


    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        this.selectedTemplateIds = selectedRows.map(row => row.Id);
        console.log('selectedTemplateIds: ', this.selectedTemplateIds);
    }

    handleExport() {
        this.loading = true;
        fetchTemplatesData({ templateIds: this.selectedTemplateIds })
            .then(result => {
                let blob = new Blob([result], { type: 'application/json' });
                let link = document.createElement('a');
                link.href = window.URL.createObjectURL(blob);
                link.download = 'ExportedTemplates.json';
                link.click();

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Data exported successfully!',
                        variant: 'success'
                    })
                );

                this.loading = false;
            })
            .catch(error => {
                this.loading = false;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error exporting data',
                        message: reduceError(error),
                        variant: 'error'
                    })
                );
            });
    }

    // Helper function to map Salesforce field types to lightning-datatable types
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
                return 'text'; // default to text if type is not recognized
        }
    }
}