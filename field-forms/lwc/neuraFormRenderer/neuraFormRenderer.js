import { LightningElement, api } from 'lwc';
import { updateRecord } from 'lightning/uiRecordApi';

import AnswerField from '@salesforce/schema/Form_Answer__c.Answer__c';
import CommentField from '@salesforce/schema/Form_Answer__c.Related_Comment__c';
import TypeField from '@salesforce/schema/Form_Answer__c.Type__c';
import FormQuestionField from '@salesforce/schema/Form_Answer__c.Form_Question__c';
import IdField from '@salesforce/schema/Form_Answer__c.Id';

import LinkedFormIdField from '@salesforce/schema/Linked_Form__c.Id';
import LinkedFormStatusField from '@salesforce/schema/Linked_Form__c.Status__c';
import LinkedFormPageField from '@salesforce/schema/Linked_Form__c.Current_Page__c';

import formFactorPropertyName from '@salesforce/client/formFactor';

import { FIELDS } from 'c/neuraFormSchemaUtils';
import {
	OPERATOR_MAP,
	STRING_LIST_OPERATORS,
	NEGATION_STRING_LIST_OPERATORS,
	ELEMENT_TYPE
} from './constants';

import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import { saveAnswers, deleteAnswers } from './databaseLayer';

import { reduceError } from 'c/nfCommonUtility';

export default class NeuraFormRenderer extends LightningElement {
	// Header Info
	indicatorType = 'Ring';
	pageTitleList = []; // array of page names
	currentPageTitle; // title of the current step
	currentPageIndex; // index of current step in pageTitleList
	totalPageCount; // total number of pages
	currentPage;
	_loaded = false;
	_completed = false;

	_formObject;

	answersToDelete = [];

	@api
	isDesktop = false;

	get isLoaded() {
		return this._loaded && !this._completed;
	}

	get isCompleted() {
		return this._completed && this._loaded;
	}

	@api get formObject() {
		return this._formObject;
	}
	set formObject(value) {
		this._formObject = JSON.parse(JSON.stringify(value));
		if (this.currentPage) {
			this.currentPage = this._formObject.pages[this.currentPageIndex];
		}
	}

	@api recordId;

	questionAnswerMap = new Map();

	connectedCallback() {
		if (this._formObject) {
			try {
				this.setInitialValues();
				this.loadComplete();
			} catch (error) {
				this.dispatchEvent(new CustomEvent('error', { detail: error }));
			}
		}
	}
	loadComplete() {
		this._loaded = true;
	}
	setInitialValues() {
		this.indicatorType = this.getValue(
			this._formObject,
			FIELDS.Form_Template__c.IndicatorType.fieldApiName,
			'Ring'
		);

		const status = this.getValue(
			this._formObject?.linkedForm,
			LinkedFormStatusField.fieldApiName,
			'Not Started'
		);

		if (status !== 'Completed') {
			this.currentPageIndex =
				this.getValue(
					this._formObject?.linkedForm,
					LinkedFormPageField.fieldApiName,
					1
				) - 1;
		} else {
			this.currentPageIndex = 0;
		}

		this.setupCurrentPage();
		this.checkCurrentPageToLoadOnLoad();
		this.updateBooleanQuestionAnswerMap();

		this.totalPageCount = this._formObject.pages.length;
		this.pageTitleList = this.createPageSteps();

		// print all values
		this.printAllValues();

		this._formObject.pages.forEach((page) => {
			page.sections.forEach((section) => {
				section.questions.forEach((question) => {
					this.updateRendering(question.Id, true);
				});
			});
		});
	}

	checkCurrentPageToLoadOnLoad() {
		if (!this.currentPage.shouldRender) {
			if (this.currentPageIndex !== 0) {
				this.currentPageIndex--;
				this.setupCurrentPage();
				this.checkCurrentPageToLoadOnLoad();
			}
		}
	}

	setupCurrentPage() {
		this.currentPageTitle = this.getValue(
			this._formObject?.pages[this.currentPageIndex],
			FIELDS.Form_Page__c.Title.fieldApiName,
			'Placeholder'
		);
		this.currentPage = this._formObject.pages[this.currentPageIndex];
	}

	updateBooleanQuestionAnswerMap() {
		this.currentPage.sections.forEach((section) => {
			const booleanQuestions = this.getBooleanQuestions(section);

			booleanQuestions.forEach((question) => {
				question.answers.forEach((answer) => {
					const tempAns = {
						uploadCompleted: true
					};

					this.assignFieldValues(
						tempAns,
						AnswerField.fieldApiName,
						answer[AnswerField.fieldApiName]
					);
					this.assignFieldValues(
						tempAns,
						FormQuestionField.fieldApiName,
						question.Id
					);
					this.assignFieldValues(
						tempAns,
						TypeField.fieldApiName,
						question[FIELDS.Form_Question__c.Type.fieldApiName]
					);
					this.assignFieldValues(
						tempAns,
						CommentField.fieldApiName,
						answer[CommentField.fieldApiName]
					);
					this.assignFieldValues(
						tempAns,
						IdField.fieldApiName,
						answer[IdField.fieldApiName]
					);

					this.questionAnswerMap.set(question.Id, tempAns);
				});
			});
		});
	}

	printAllValues() {
		console.log('Indicator Type: ' + this.indicatorType);
		console.log('Current Step Index: ' + this.currentPageIndex);
		console.log('Current Step: ' + this.currentPageTitle);
		console.log('Total Pages: ' + this.totalPageCount);
		console.log('Page Steps: ' + this.pageTitleList);
		console.log('Current Page: ' + JSON.stringify(this.currentPage));
	}

	getValue(object, fieldName, defaultValue) {
		return object && object[fieldName] ? object[fieldName] : defaultValue;
	}

	createFormObject(formTemplate, formPages, formSections, formQuestions) {
		if (formTemplate && formPages && formSections && formQuestions) {
			return {
				name: formTemplate.name,
				pages: formPages.map((page) => ({
					id: page.id,
					fields: page.fields,
					sections: formSections
						.filter(
							(section) =>
								section.fields[FIELDS.Form_Section__c.FormPage.fieldApiName]
									.value === page.id
						)
						.map((section) => ({
							id: section.id,
							fields: section.fields,
							questions: formQuestions
								.filter(
									(question) =>
										question.fields[
											FIELDS.Form_Question__c.FormSection.fieldApiName
										].value === section.id
								)
								.map((question) => ({
									id: question.id,
									fields: question.fields
								}))
						}))
				}))
			};
		}
	}

	createPageSteps() {
		// return an array of page names
		return this._formObject.pages.map(
			(page) => page[FIELDS.Form_Page__c.Title.fieldApiName]
		);
	}

	/**
	 * Handles the click event of the footer buttons.
	 * @param {Event} event - The click event.
	 * @returns {void}
	 */
	async handleFooterButtonClick(event) {
		const actionType = event.detail.actionType;

		if (actionType === 'backToForms') {
			this.dispatchEvent(
				new CustomEvent('returnhome', {
					bubbles: true,
					composed: true
				})
			);
			return;
		}

		console.log('Answers creation started');

		this.dispatchEvent(
			new CustomEvent('footerclick', {
				detail: true
			})
		);

		if (actionType === 'previous' || this.checkValidations()) {
			const isDeleteSucces = await this.deleteAnswers();

			let isUploadSuccess = false;
			if (isDeleteSucces) {
				isUploadSuccess = await this.uploadAnswers();
			}

			if (isUploadSuccess) {
				this.updateFormObjectWithNewAnswers();

				console.log('Answers submitted');

				switch (actionType) {
					case 'previous':
						await this.changePage(-1);
						break;
					case 'next':
						await this.changePage(1);
						break;
					case 'finish':
						await this.handleFinish();
						break;
					default:
						console.warn('Unhandled action type:', actionType);
				}
			}
		} else {
			this.showToastMessage(
				'Error',
				'Correct the errors below to continue.',
				'error'
			);
		}

		this.dispatchEvent(
			new CustomEvent('footerclick', {
				detail: false
			})
		);
	}

	checkValidations() {
		let valid = true;

		valid = this.refs.formPage.checkValidity();

		// if (valid) {
		// 	this.currentPage.sections.forEach((section) => {
		// 		if (valid) {
		// 			const requiredQuestions = section.questions.filter((item) => {
		// 				return (
		// 					item[FIELDS.Form_Question__c.Required.fieldApiName] &&
		// 					item.shouldRender
		// 				);
		// 			});

		// 			requiredQuestions.forEach((question) => {
		// 				if (valid) {
		// 					const answer = this.questionAnswerMap.get(question.Id);

		// 					if (
		// 						question.Type__c === 'File Upload' ||
		// 						question.Type__c === 'Signature'
		// 					) {
		// 						if (
		// 							answer &&
		// 							(!answer.filesData ||
		// 								(answer.filesData && answer.filesData.length === 0))
		// 						) {
		// 							valid = false;
		// 						}

		// 						if (
		// 							valid &&
		// 							!answer &&
		// 							question.answers &&
		// 							(!question.answers.length ||
		// 								(question.answers.length &&
		// 									question.answers[0].filesData &&
		// 									question.answers[0].filesData.length === 0))
		// 						) {
		// 							valid = false;
		// 						}
		// 					} else {
		// 						if (
		// 							answer &&
		// 							answer.hasOwnProperty(AnswerField.fieldApiName) &&
		// 							!answer[AnswerField.fieldApiName]
		// 						) {
		// 							valid = false;
		// 						}

		// 						if (
		// 							valid &&
		// 							(!answer ||
		// 								(answer &&
		// 									!answer.hasOwnProperty(AnswerField.fieldApiName))) &&
		// 							question.answers &&
		// 							!question.answers.length
		// 						) {
		// 							valid = false;
		// 						}
		// 					}
		// 				} else {
		// 					valid = false;
		// 				}
		// 			});
		// 		}
		// 	});
		// }

		return valid;
	}

	showToastMessage(title, message, variant) {
		this.dispatchEvent(
			new ShowToastEvent({
				title: title,
				message: message,
				variant: variant
			})
		);
	}

	async deleteAnswers() {
		let isSuccess = true;

		if (this.answersToDelete.length) {
			try {
				await deleteAnswers(this.answersToDelete, formFactorPropertyName);
				this.answersToDelete = [];
			} catch (error) {
				this.showToastMessage('Error', reduceError(error), 'error');
				isSuccess = false;
			}
		}

		return isSuccess;
	}

	async uploadAnswers() {
		let isSuccess = true;
		try {
			this.setDefaultsToBooleanQuestions();

			await saveAnswers(
				this.questionAnswerMap,
				this._formObject.linkedForm.Id,
				formFactorPropertyName
			);
		} catch (error) {
			isSuccess = false;
			this.showToastMessage('Error', reduceError(error), 'error');
		} finally {
			return isSuccess;
		}
	}

	setDefaultsToBooleanQuestions() {
		this.currentPage.sections.forEach((section) => {
			const booleanQuestions = this.getBooleanQuestions(section);

			booleanQuestions.forEach((question) => {
				if (!this.questionAnswerMap.has(question.Id)) {
					const tempAns = {
						uploadCompleted: false
					};

					this.assignFieldValues(tempAns, AnswerField.fieldApiName, 'false');
					this.assignFieldValues(
						tempAns,
						FormQuestionField.fieldApiName,
						question.Id
					);
					this.assignFieldValues(
						tempAns,
						TypeField.fieldApiName,
						question[FIELDS.Form_Question__c.Type.fieldApiName]
					);
					this.assignFieldValues(tempAns, CommentField.fieldApiName, null);
					this.assignFieldValues(tempAns, 'filesData', []);

					this.questionAnswerMap.set(question.Id, tempAns);
				}
			});
		});
	}

	updateFormObjectWithNewAnswers() {
		this._formObject.pages[this.currentPageIndex].sections.forEach(
			(section) => {
				const questionHasAnswers = section.questions.filter((item) => {
					if (this.questionAnswerMap.has(item.Id)) {
						const answer = this.questionAnswerMap.get(item.Id);
						return answer.uploadCompleted;
					}
					return false;
				});

				questionHasAnswers.forEach((item) => {
					const answer = { ...this.questionAnswerMap.get(item.Id) };

					if (item.answers.length) {
						const existingFilesData = item.answers[0].filesData
							? item.answers[0].filesData
							: [];

						if (answer.filesData && answer.filesData.length) {
							answer.filesData = [...existingFilesData, ...answer.filesData];
						} else {
							answer.filesData = [...existingFilesData];
						}

						item.answers[0] = {
							...item.answers[0],
							...answer
						};

						answer.filesData = [];
						this.questionAnswerMap.set(item.Id, answer);
					} else {
						item.answers = [answer];
					}
				});
			}
		);

		this.dispatchUpdateFormDataEvent();
	}

	assignFieldValues(targetObj, fieldApiName, value) {
		if (value !== undefined) {
			targetObj[fieldApiName] = value;
		}
	}

	async handleFinish() {
		await this.updateLinkedForm('Completed');
		this._completed = true;
	}

	/**
	 * Changes the current page index and updates the current page based on the given delta.
	 * @param {number} delta - The change in page index.
	 */
	async changePage(delta) {
		const newIndex = this.currentPageIndex + delta;
		if (newIndex >= 0 && newIndex < this.totalPageCount) {
			this.currentPageIndex = newIndex;
			const tempCurrentPage = { ...this._formObject.pages[newIndex] };

			if (!tempCurrentPage.shouldRender) {
				await this.changePage(delta);
			} else {
				this.currentPage = { ...tempCurrentPage };

				this.currentPageTitle = this.pageTitleList[newIndex];

				this.updateBooleanQuestionAnswerMap();

				if (
					this._formObject.linkedForm[LinkedFormStatusField.fieldApiName] !==
					'Completed'
				) {
					await this.updateLinkedForm('In Progress');
				}
			}
			this.scrollToFormHeader();
		} else {
			await this.handleFinish();
		}
	}

	async updateLinkedForm(status) {
		const fields = {};
		this.assignFieldValues(
			fields,
			LinkedFormIdField.fieldApiName,
			this._formObject.linkedForm.Id
		);
		this.assignFieldValues(fields, LinkedFormStatusField.fieldApiName, status);
		this.assignFieldValues(
			fields,
			LinkedFormPageField.fieldApiName,
			this.currentPageIndex + 1
		);

		const updateLinkedFormInput = { fields };

		await updateRecord(updateLinkedFormInput);

		this.dispatchEvent(
			new CustomEvent('updatelinkedformdetails', {
				detail: {
					value: fields
				}
			})
		);
	}

	handleAnswerChange(event) {
		const questionId = event.detail.answer[FormQuestionField.fieldApiName];

		let answerObject = { ...event.detail.answer, uploadCompleted: false };

		if (this.questionAnswerMap.has(questionId)) {
			const questionAnswer = this.questionAnswerMap.get(questionId);

			if (answerObject.filesData && answerObject.filesData.length) {
				const filesData =
					questionAnswer.filesData && questionAnswer.filesData.length
						? questionAnswer.filesData
						: [];

				answerObject.filesData = [...filesData, ...answerObject.filesData];
			} else if (questionAnswer.filesData && questionAnswer.filesData.length) {
				answerObject.filesData = [...questionAnswer.filesData];
			}

			answerObject = { ...questionAnswer, ...answerObject };
		}

		this.questionAnswerMap.set(questionId, answerObject);

		if (
			answerObject.hasOwnProperty(FIELDS.Form_Answer__c.Answer.fieldApiName)
		) {
			this.updateRendering(questionId, false);
			this.dispatchUpdateFormDataEvent();
		}
	}

	getBooleanQuestions(section) {
		return section.questions.filter((item) => {
			return (
				item[FIELDS.Form_Question__c.Type.fieldApiName] === 'Toggle' ||
				item[FIELDS.Form_Question__c.Type.fieldApiName] === 'Checkbox'
			);
		}); //Add the type accordingly in future when more boolean type fields are introduced
	}

	updateRendering(questionId, initialLoad) {
		this._formObject.pages.forEach((page) => {
			if (
				page.renderingCondition &&
				page.renderingCondition.conditions.length
			) {
				page.shouldRender = this.checkRenderingConditions(
					questionId,
					page.renderingCondition,
					page.shouldRender,
					initialLoad,
					ELEMENT_TYPE.PAGE
				);
			}
			page.sections.forEach((section) => {
				if (
					section.renderingCondition &&
					section.renderingCondition.conditions.length
				) {
					section.shouldRender = this.checkRenderingConditions(
						questionId,
						section.renderingCondition,
						section.shouldRender,
						initialLoad,
						ELEMENT_TYPE.SECTION
					);
				}
				section.questions.forEach((question) => {
					if (
						question.renderingCondition &&
						question.renderingCondition.conditions.length
					) {
						question.shouldRender = this.checkRenderingConditions(
							questionId,
							question.renderingCondition,
							question.shouldRender,
							initialLoad,
							ELEMENT_TYPE.QUESTION
						);
					}
				});
			});
		});
	}

	checkRenderingConditions(
		questionId,
		renderingCondition,
		shouldRender,
		initialLoad,
		elementType
	) {
		const checkConditionExist = renderingCondition.conditions.findIndex(
			(condition) => {
				return condition.resource === questionId;
			}
		);

		if (checkConditionExist > -1) {
			let keyConditionMap = this.getKeyConditionMap(
				renderingCondition.conditions
			);

			let conditionsString = false;

			if (keyConditionMap.size === renderingCondition.conditions.length) {
				conditionsString = renderingCondition.customLogic;

				conditionsString = conditionsString.replace('AND', '&&');
				conditionsString = conditionsString.replace('OR', '||');

				for (let [key, value] of keyConditionMap) {
					conditionsString = conditionsString.replace(key, value);
				}
			}

			const isRender = eval(conditionsString);

			if (!isRender && !initialLoad) {
				let questionIds = [];
				switch (elementType) {
					case ELEMENT_TYPE.PAGE:
						const filteredPage = this._formObject.pages.find((page) => {
							return page.Id === renderingCondition.id;
						});
						if (filteredPage) {
							filteredPage.sections.forEach((section) => {
								section.questions.forEach((question) => {
									questionIds.push(question.Id);
								});
							});
						}
						break;
					case ELEMENT_TYPE.SECTION:
						let filteredSection;
						for (let i = 0; i < this._formObject.pages.length; i++) {
							filteredSection = this._formObject.pages[i].sections.find(
								(section) => {
									return section.Id === renderingCondition.id;
								}
							);
							if (filteredSection) {
								break;
							}
						}
						if (filteredSection) {
							filteredSection.questions.forEach((question) => {
								questionIds.push(question.Id);
							});
						}
						break;
					default:
						questionIds.push(renderingCondition.id);
						break;
				}
				questionIds.forEach((id) => {
					this.removeAnswersOfHiddenQuestions(id);
					this.dispatchUpdateFormDataEvent();
					this.updateRendering(id, initialLoad);
				});
			}

			return isRender;
		}

		return shouldRender;
	}

	getKeyConditionMap(conditions) {
		let keyConditionMap = new Map();
		conditions.forEach((item) => {
			let answerValue;
			const questionId = item.resource;

			if (this.questionAnswerMap.has(questionId)) {
				const answerAvailable = this.questionAnswerMap.get(questionId);
				if (
					answerAvailable.hasOwnProperty(
						FIELDS.Form_Answer__c.Answer.fieldApiName
					)
				) {
					answerValue =
						answerAvailable[FIELDS.Form_Answer__c.Answer.fieldApiName];
				}
			}

			if (!answerValue) {
				const answers = this.checkInSavedAnswers(questionId, false);
				if (answers && answers.length) {
					const answerAvailable = answers[0];
					answerValue =
						answerAvailable[FIELDS.Form_Answer__c.Answer.fieldApiName];
				}
			}

			let condition;

			if (STRING_LIST_OPERATORS.includes(item.operator)) {
				if (Array.isArray(item.value)) {
					let stringArray = new String();
					item.value.forEach((val) => {
						stringArray += `'${val}',`;
					});
					stringArray = stringArray.substring(0, stringArray.length - 1);
					condition = `[${stringArray}].${OPERATOR_MAP.get(item.operator)}('${answerValue}')`;
				} else {
					condition = `'${answerValue}'.${OPERATOR_MAP.get(item.operator)}('${item.value}')`;
				}

				if (NEGATION_STRING_LIST_OPERATORS.includes(item.operator)) {
					condition = `!${condition}`;
				}
			} else {
				if (
					this.isNumericValue(answerValue) &&
					this.isNumericValue(item.value)
				) {
					condition = `${answerValue} ${OPERATOR_MAP.get(item.operator)} ${item.value}`;
				} else {
					condition = `'${answerValue}' ${OPERATOR_MAP.get(item.operator)} '${item.value}'`;
				}
			}

			keyConditionMap.set(item.key, eval(condition));
		});

		return keyConditionMap;
	}

	isNumericValue(str) {
		if (typeof str != 'string') return false; // we only process strings!
		return (
			!isNaN(str) && // use type coercion to parse the _entirety_ of the string (`parseFloat` alone does not do this)...
			!isNaN(parseFloat(str))
		); // ...and ensure strings of whitespace fail
	}

	removeAnswersOfHiddenQuestions(questionId) {
		if (this.questionAnswerMap.has(questionId)) {
			this.questionAnswerMap.delete(questionId);
		}

		this.checkInSavedAnswers(questionId, true);
	}

	checkInSavedAnswers(questionId, removeAnswers) {
		let questionToFind;
		this._formObject.pages.forEach((page) => {
			page.sections.forEach((section) => {
				const tempQuestion = section.questions.find((question) => {
					return question.Id === questionId && question.answers.length;
				});
				if (tempQuestion) {
					questionToFind = tempQuestion;
					if (removeAnswers) {
						this.answersToDelete.push(tempQuestion.answers[0]);
						//deleteRecord(tempQuestion.answers[0].Id);
						tempQuestion.answers = [];
					}
				}
			});
		});

		return questionToFind?.answers;
	}

	scrollToTop() {
		const scrollableDiv = this.template.querySelector('.renderer-wrapper');
		if (scrollableDiv) {
			scrollableDiv.scrollTop = 0;
		}
	}

	scrollToFormHeader() {
		const formHeader = this.template.querySelector('.temp-test');
		if (formHeader) {
			const formHeaderRect = formHeader.getBoundingClientRect();
			window.scrollTo({
				top: window.scrollY + formHeaderRect.top,
				behavior: 'smooth'
			});
		}
	}

	dispatchUpdateFormDataEvent() {
		this.dispatchEvent(
			new CustomEvent('updateformdata', {
				detail: {
					value: this._formObject
				}
			})
		);
	}
}