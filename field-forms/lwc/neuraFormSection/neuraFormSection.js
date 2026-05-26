import { LightningElement, api, wire } from 'lwc';
import { FIELDS } from 'c/neuraFormSchemaUtils';

export default class NeuraFormSection extends LightningElement {
	@api recordId;
	@api formSection;
	// Pass-through for Calculation reactivity. See neuraFormRenderer.answerMap.
	@api answerMap;
	@api skippedIds;

	@api checkValidity() {
		const allQuestions = this.template.querySelectorAll(
			'c-neura-form-question'
		);

		let isValid = true;

		allQuestions.forEach((question) => {
			const questionValid = question.checkValidity();
			if (isValid && !questionValid) {
				isValid = false;
			}
		});

		return isValid;
	}

	@api applyDictation(map) {
		const allQuestions = this.template.querySelectorAll('c-neura-form-question');
		allQuestions.forEach((q) => {
			if (typeof q.applyDictation === 'function') q.applyDictation(map);
		});
	}

	/**
	 * Pillar 5 — scroll a specific question into view when the tech taps it
	 * from the findings panel. Returns true if the question lives in this
	 * section so the page can stop iterating. Uses scrollIntoView with
	 * smooth behavior; CSS scroll-margin-top on the wrapper handles the
	 * sticky header overlap.
	 */
	@api scrollToQuestion(questionId) {
		if (!questionId) return false;
		const el = this.template.querySelector(
			`[data-question-id="${questionId}"]`
		);
		if (!el) return false;
		el.scrollIntoView({ behavior: 'smooth', block: 'start' });
		return true;
	}

	formQuestions;

	get showTitle() {
		return this.formSection[FIELDS.Form_Section__c.ShowTitle.fieldApiName];
	}

	get sectionTitle() {
		return this.showTitle
			? this.formSection[FIELDS.Form_Section__c.Title.fieldApiName]
			: '';
	}

	get sectionStyle() {
		const backgroundColor =
			this.formSection[FIELDS.Form_Section__c.BackgroundColor.fieldApiName] ??
			'#FFFFFF';
		const padding =
			this.formSection[FIELDS.Form_Section__c.Padding.fieldApiName] ?? '1rem';
		return `background-color: ${backgroundColor}; padding: ${padding};`;
	}

	get questionClass() {
		const columnSize =
			this.formSection[FIELDS.Form_Section__c.ColumnSize.fieldApiName] ??
			'1-of-1'; // Default column size
		return `form-section slds-col slds-size_${columnSize}`;
	}
}