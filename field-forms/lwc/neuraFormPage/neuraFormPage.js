import { LightningElement, wire, api } from 'lwc';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import { getRelatedListRecords } from 'lightning/uiRelatedListApi';
import { FIELDS } from 'c/neuraFormSchemaUtils';

export default class NeuraFormPage extends LightningElement {
	_formPage;

	@api recordId;
	// Threaded through from the renderer; passed down to questions so any
	// Calculation question can evaluate its formula against every other
	// answer on the form. Plain object: { questionId -> answer string }.
	@api answerMap;
	formSections;

	answersToSave = [];
	answersToUpdate = [];

	isOverlayActive = false;

	//clone the formPage
	@api
	get formPage() {
		return this._formPage;
	}

	set formPage(value) {
		this._formPage = { ...value };
		this.formSections = this.formPage?.sections;
	}

	@api checkValidity() {
		const allSections = this.template.querySelectorAll('c-neura-form-section');

		let isValid = true;

		allSections.forEach((section) => {
			const sectionValid = section.checkValidity();
			if (isValid && !sectionValid) {
				isValid = false;
			}
		});

		return isValid;
	}

	handleOverlayStateChange(event) {
		this.isOverlayActive = event.detail;
	}

	// on change update the answer value in the formPage on the related answer
	handleAnswerChange(event) {
		// is the event an update or create
		const isCreate = event.detail.isCreate;
		// get the answer
		const answer = event.detail.answer;

		// if create add to answersToSave, determine if the question already has an answer and if so replace with new answer

		if (isCreate) {
			const existingAnswer = this.answersToSave.find(
				(existingAnswer) =>
					existingAnswer[FIELDS.Form_Answer__c.Question.fieldApiName] ===
					answer[FIELDS.Form_Answer__c.Question.fieldApiName]
			);
			if (existingAnswer) {
				this.answersToSave.splice(
					this.answersToSave.indexOf(existingAnswer),
					1,
					answer
				);
			} else {
				this.answersToSave.push(answer);
			}
		} else {
			// if update add to answersToUpdate
			const existingAnswer = this.answersToUpdate.find(
				(existingAnswer) =>
					existingAnswer[FIELDS.Form_Answer__c.Question.fieldApiName] ===
					answer[FIELDS.Form_Answer__c.Question.fieldApiName]
			);
			if (existingAnswer) {
				this.answersToUpdate.splice(
					this.answersToUpdate.indexOf(existingAnswer),
					1,
					answer
				);
			} else {
				this.answersToUpdate.push(answer);
			}
		}
	}
}