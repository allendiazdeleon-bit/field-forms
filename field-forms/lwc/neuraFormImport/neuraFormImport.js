import { LightningElement } from 'lwc';
import importTemplates from '@salesforce/apex/neuraFormExportController.importTemplates';
import runTemplateRollup from '@salesforce/apex/neuraFormExportController.runTemplateRollup';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { reduceError } from 'c/nfCommonUtility';

export default class NeuraFormImport extends LightningElement {
    importedTemplates;
    importTemplateIds = [];
    fileName;
    fileContents;
    error;
    loading = false;

    columns = [
        { label: 'Template Name', fieldName: 'Name', type: 'text' },
        { label: 'Template Id', fieldName: 'Id', type: 'text'}
        // Add more columns as needed
    ];

    handleFileChange(event) {
        try {
            const fileReader = new FileReader();
            const file = event.target.files[0];
            this.fileName = file ? file.name : ''; // set the file name


            fileReader.onload = () => {
                this.fileContents = fileReader.result;
            };
            fileReader.readAsText(file);
        } catch(error) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: reduceError(error),
                    variant: 'error'
                })
            );
        }
    }

    async importData() {
        this.loading = true;
        this.importedTemplates = [];
        this.importedTemplateIds = [];
        try {
            const result = await importTemplates({ jsonContent: this.fileContents });
            console.log('Form Template creation completed');
            console.log('Here is the result: ' + JSON.stringify(result));
            this.importedTemplates = result;
            this.importedTemplateIds = this.importedTemplates.map(template => template.Id);
            
    
            try {
                const returnVal = await runTemplateRollup({formTemplateIdsList: this.importedTemplateIds});
                console.log('Template rollup completed');
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Success',
                        message: 'Records imported successfully!',
                        variant: 'success'
                    })
                );
            } catch (rollupError) {
                this.error = rollupError;
                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Error during template rollup',
                        message: reduceError(rollupError),
                        variant: 'error'
                    })
                );
            }
        } catch (error) {
            this.error = error;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error importing data',
                    message: reduceError(error),
                    variant: 'error'
                })
            );
        } finally {
            this.loading = false;
        }
    }

    
}