import { LightningElement, api, wire } from 'lwc';
import { FIELDS } from 'c/neuraFormSchemaUtils';

export default class NeuraFormSection extends LightningElement {
	@api recordId;
	@api formSection;
	// Pass-through for Calculation reactivity. See neuraFormRenderer.answerMap.
	@api answerMap;

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