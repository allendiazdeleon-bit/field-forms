import LightningModal from 'lightning/modal';
import generateTemplateFromPrompt from '@salesforce/apex/NeuraFormAIController.generateTemplateFromPrompt';
import { NavigationMixin } from 'lightning/navigation';

/**
 * Modal that lets an admin describe a form in natural language and have
 * Einstein Generative AI build it. On success the modal closes and the
 * caller (builder header) navigates the user to the newly-created template.
 *
 * Launched via `await NeuraFormAIGenerate.open({ size: 'medium' })`.
 * Resolves to either `{ action: 'cancel' }` or
 * `{ action: 'generated', formTemplateId, formTemplateName, pageCount, questionCount }`.
 */
export default class NeuraFormAIGenerate extends NavigationMixin(LightningModal) {
    prompt = '';
    context = '';
    isGenerating = false;
    errorMessage = '';

    // Stock examples that double as both inspiration and "tap to fill" shortcuts.
    examples = [
        {
            label: 'HVAC inspection',
            prompt: 'HVAC inspection form for residential service calls. Three pages: pre-visit equipment check, on-site readings, customer sign-off with signature.'
        },
        {
            label: 'Roof damage report',
            prompt: 'Roof damage report for insurance claims. Capture address, photos of damage, severity rating per area, and overall recommendation.'
        },
        {
            label: 'Safety audit',
            prompt: 'Construction site safety audit. PPE compliance, hazard observations, near-miss reports, and a final pass/fail with comments.'
        }
    ];

    get disableGenerate() {
        return this.isGenerating || !this.prompt || this.prompt.trim().length < 10;
    }

    get spinnerMessage() {
        return 'Generating form. Einstein is working on it...';
    }

    handlePromptChange(event) {
        this.prompt = event.target.value;
        this.errorMessage = '';
    }

    handleContextChange(event) {
        this.context = event.target.value;
    }

    handleExampleClick(event) {
        const idx = parseInt(event.currentTarget.dataset.index, 10);
        const example = this.examples[idx];
        if (example) {
            this.prompt = example.prompt;
            this.errorMessage = '';
        }
    }

    handleCancel() {
        if (this.isGenerating) return;
        this.close({ action: 'cancel' });
    }

    async handleGenerate() {
        if (this.disableGenerate) return;
        this.isGenerating = true;
        this.errorMessage = '';

        try {
            const result = await generateTemplateFromPrompt({
                prompt: this.prompt,
                context: this.context
            });
            this.close({
                action: 'generated',
                formTemplateId: result.formTemplateId,
                formTemplateName: result.formTemplateName,
                pageCount: result.pageCount,
                questionCount: result.questionCount
            });
        } catch (err) {
            // Apex throws AuraHandledException; the message lands in body.message.
            this.errorMessage = err?.body?.message || err?.message || 'Generation failed.';
            this.isGenerating = false;
        }
    }
}
