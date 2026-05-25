import { LightningElement, api, wire, track } from 'lwc';
import { updateRecord, getRecord } from 'lightning/uiRecordApi';

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

import { saveAnswers, deleteAnswers } from './databaseLayer';
import { createSwipeController } from './swipeController';
import { createAutoSaveController } from './autoSaveController';
import {
	toggleSkipped,
	formatSkippedBadgeLabel,
	formatBlockedSubmitMessage
} from './skipQueueController';
import {
	parentFieldForHost,
	formatPrefillSuccessMessage,
	PREFILL_MESSAGES
} from './prefillController';
import {
	buildKeyConditionMap,
	isNumericValue as _isNumericValueImpl
} from './conditionalRenderingEvaluator';
import { filterBooleanQuestions } from './booleanQuestionUtils';

import { reduceError } from 'c/nfCommonUtility';

import mapTranscriptToQuestions from '@salesforce/apex/NeuraFormMobileController.mapTranscriptToQuestions';
import getLastVisitAnswers from '@salesforce/apex/NeuraFormMobileController.getLastVisitAnswers';
import generatePdfForLinkedForm from '@salesforce/apex/NeuraFormPdfController.generatePdfForLinkedForm';

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

	// Host record context (passed by the mobile parent: Work_Order /
	// Work_Order_Line_Item / Service_Appointment). Used by
	// applyHostRecordDefaults to pre-fill empty answers from the host's
	// fields. Undefined on the desktop preview path, in which case
	// pre-population is skipped.
	@api hostRecordId;
	@api hostObjectApiName;

	// Plain-object view of questionAnswerMap, keyed by Form_Question Id with
	// the answer string as the value. Threaded through page -> section ->
	// question -> answer so Calculation questions can evaluate their formula
	// against the current state of every other answer on the form. Replaced
	// (not mutated) on each answerchange so child @api setters re-fire.
	answerMap = {};

	rebuildAnswerMap() {
		const next = {};
		this.questionAnswerMap.forEach((val, key) => {
			next[key] = val?.[AnswerField.fieldApiName] ?? '';
		});
		this.answerMap = next;
	}

	get isLoaded() {
		// Suppress the form when we're either fully done OR routed into
		// the review screen; the review LWC owns the full viewport.
		return this._loaded && !this._completed && !this._inReview;
	}

	get linkedFormId() {
		return this._formObject?.linkedForm?.Id;
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
				// Apply Default_Value_Static__c synchronously here; source
				// defaults arrive later via the @wire(getRecord) below.
				this.applyStaticDefaults();
			} catch (error) {
				this.dispatchEvent(new CustomEvent('error', { detail: error }));
			}
		}
	}

	// One-shot guard so source defaults don't re-apply on every wire refresh.
	_sourceDefaultsApplied = false;

	/**
	 * Compute the union of all `Default_Value_Source__c` field paths across
	 * the form's questions. Used as the reactive `fields` argument to the
	 * @wire(getRecord) below. Returns undefined to disable the wire when
	 * there's no host context or no source paths to fetch.
	 */
	get hostFieldsForDefaults() {
		if (this._sourceDefaultsApplied) return undefined;
		if (!this._formObject || !this.hostRecordId || !this.hostObjectApiName) return undefined;
		const defaultsFieldSource = FIELDS.Form_Question__c.DefaultValueSource?.fieldApiName;
		if (!defaultsFieldSource) return undefined;

		const fields = new Set();
		this._formObject.pages.forEach((page) => {
			page.sections.forEach((section) => {
				section.questions.forEach((question) => {
					if (this.questionAnswerMap.has(question.Id)) return;
					const sourcePath = question[defaultsFieldSource];
					if (!sourcePath) return;
					// uiRecordApi expects field paths qualified by object,
					// e.g. WorkOrder.Account.Name. Bare paths are prefixed
					// with the host object so admins don't have to repeat it.
					const qualified = sourcePath.includes('.')
						? sourcePath
						: `${this.hostObjectApiName}.${sourcePath}`;
					fields.add(qualified);
				});
			});
		});
		return fields.size > 0 ? Array.from(fields) : undefined;
	}

	/**
	 * Wire on the host record once we know which fields the form's questions
	 * want pre-filled. lightning/uiRecordApi exposes getRecord as a wire
	 * adapter only - the previous imperative call was a compile error.
	 *
	 * Errors are non-fatal: static defaults still apply, the form still
	 * renders, and the field tech can fill the rest manually.
	 */
	@wire(getRecord, {
		recordId: '$hostRecordId',
		fields: '$hostFieldsForDefaults'
	})
	hostRecordForDefaults({ data, error }) {
		if (this._sourceDefaultsApplied) return;
		if (error) {
			console.warn('Host record fetch for default-value sources failed', error);
			// Mark applied so we don't keep retrying; static defaults already
			// ran in connectedCallback so the form is still usable.
			this._sourceDefaultsApplied = true;
			return;
		}
		if (!data) return; // wire still resolving
		this.applySourceDefaults(data);
		this._sourceDefaultsApplied = true;
	}

	/**
	 * Apply only the Default_Value_Static__c literals - runs synchronously on
	 * mount so the user sees their static defaults immediately, without
	 * waiting for the host-record wire to resolve. Source defaults apply
	 * later via applySourceDefaults().
	 */
	applyStaticDefaults() {
		if (!this._formObject) return;
		const fieldStatic = FIELDS.Form_Question__c.DefaultValueStatic?.fieldApiName;
		if (!fieldStatic) return;
		let anyApplied = false;
		this._formObject.pages.forEach((page) => {
			page.sections.forEach((section) => {
				section.questions.forEach((question) => {
					if (this.questionAnswerMap.has(question.Id)) return;
					const staticVal = question[fieldStatic];
					if (!staticVal) return;
					this.storeAnswerForDefault(question, staticVal);
					anyApplied = true;
				});
			});
		});
		if (anyApplied) {
			this.rebuildAnswerMap();
			this._formObject = { ...this._formObject };
		}
	}

	applySourceDefaults(hostRecord) {
		if (!this._formObject || !hostRecord) return;
		const fieldSource = FIELDS.Form_Question__c.DefaultValueSource?.fieldApiName;
		const fieldStatic = FIELDS.Form_Question__c.DefaultValueStatic?.fieldApiName;
		if (!fieldSource) return;

		let anyApplied = false;
		this._formObject.pages.forEach((page) => {
			page.sections.forEach((section) => {
				section.questions.forEach((question) => {
					if (this.questionAnswerMap.has(question.Id)) return;
					const sourcePath = question[fieldSource];
					if (!sourcePath) return;

					let value = this.resolveFieldPath(hostRecord, sourcePath);
					// Fall back to static when the host record resolves to null
					// (e.g. FLS blocked or the field is empty on the host).
					if ((value === undefined || value === null || value === '')
						&& fieldStatic && question[fieldStatic]) {
						value = question[fieldStatic];
					}
					if (value === undefined || value === null || value === '') return;

					this.storeAnswerForDefault(question, value);
					anyApplied = true;
				});
			});
		});
		if (anyApplied) {
			this.rebuildAnswerMap();
			this._formObject = { ...this._formObject };
		}
	}

	storeAnswerForDefault(question, value) {
		const tempAns = { uploadCompleted: false };
		this.assignFieldValues(tempAns, AnswerField.fieldApiName, String(value));
		this.assignFieldValues(tempAns, FormQuestionField.fieldApiName, question.Id);
		this.assignFieldValues(
			tempAns,
			TypeField.fieldApiName,
			question[FIELDS.Form_Question__c.Type.fieldApiName]
		);
		this.questionAnswerMap.set(question.Id, tempAns);
	}

	/**
	 * Walks a getRecord result via a dotted path like
	 * "WorkOrder.Account.Name". Returns the resolved primitive, or undefined.
	 *
	 * uiRecordApi nests spanning lookups under `fields.<lookup>.value.fields`
	 * - this walker handles both shapes: bare values and the nested-record
	 * containers. Tolerant to missing intermediates.
	 */
	resolveFieldPath(record, fullPath) {
		if (!record || !fullPath) return undefined;
		// Drop the leading object name if present (WorkOrder.Account.Name -> Account.Name).
		const parts = fullPath.split('.');
		if (parts.length > 1 && parts[0] === record.apiName) parts.shift();

		let current = record.fields;
		for (let i = 0; i < parts.length; i++) {
			if (!current) return undefined;
			const node = current[parts[i]];
			if (node === undefined) return undefined;
			const isLast = i === parts.length - 1;
			if (isLast) {
				// Leaf: extract .value or the bare value.
				return node && typeof node === 'object' && 'value' in node ? node.value : node;
			}
			// Spanning: follow into the related record's fields.
			current = node?.value?.fields ?? node?.fields ?? undefined;
		}
		return undefined;
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

		// Seed the answer map from the existing questionAnswerMap so any
		// Calculation questions on the first render see their dependencies.
		this.rebuildAnswerMap();
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

		// Block final submit until the skip-and-return queue is cleared.
		// "Next" / "Previous" stay free so the tech can still navigate
		// between pages to revisit each skipped question.
		if (actionType === 'finish' && this.hasSkipped) {
			this.showToastMessage(
				'Info',
				formatBlockedSubmitMessage(this.skippedCount),
				'warning'
			);
			this.dispatchEvent(new CustomEvent('footerclick', { detail: false }));
			return;
		}

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
			// Collect the labels of required questions that weren't answered so
			// the user knows which field to fix, instead of the generic
			// "errors below" message that's useless on mobile when the form is
			// long enough to scroll.
			const missing = this.collectMissingRequiredLabels();
			const detail = missing.length
				? 'Please complete: ' + missing.join(', ')
				: 'Some required fields are missing or invalid.';
			this.showToastMessage('Error', detail, 'error');
		}

		this.dispatchEvent(
			new CustomEvent('footerclick', {
				detail: false
			})
		);
	}

	// Force a full re-mount of the form template. lightning-input doesn't
	// always re-read its `value` prop after the initial render — toggling
	// _loaded tears down the renderer's children and rebuilds them with
	// the current _formObject state. Necessary after programmatic
	// answer mutations (dictation, prefill) that the user didn't trigger
	// through normal typing.
	//
	// Before tearing down, we mirror everything in questionAnswerMap into
	// the corresponding question.answers[0]. Manually-typed values live in
	// the answer map but aren't copied into the form object until the
	// user advances pages — without this sync, the remount would render
	// blank inputs for any field the user had already filled in.
	async forceRerender() {
		const wasLoaded = this._loaded;
		const newPages = this._formObject.pages.map((p) => ({
			...p,
			sections: (p.sections || []).map((s) => ({
				...s,
				questions: (s.questions || []).map((q) => {
					if (!this.questionAnswerMap.has(q.Id)) return q;
					const ans = this.questionAnswerMap.get(q.Id);
					const merged = { ...(q.answers?.[0] || {}), ...ans };
					return { ...q, answers: [merged] };
				})
			}))
		}));
		this._formObject = { ...this._formObject, pages: newPages };
		this.currentPage = this._formObject.pages[this.currentPageIndex];

		this._loaded = false;
		// Give LWC one render cycle to unmount the children before we
		// flip the flag back. Promise.resolve() defers to the microtask
		// queue, which fires after the current synchronous task.
		await Promise.resolve();
		this._loaded = wasLoaded;
	}

	// Page-level dictation entry point. Wired to c-neura-voice-capture's
	// ontranscript event in the renderer template; receives the raw spoken
	// text, asks Apex to map it across the current page's questions, then
	// applies each suggestion through the same path manual edits use.
	async handlePageDictation(event) {
		const transcript = (event?.detail?.text || '').trim();
		if (!transcript) return;

		const questions = [];
		(this.currentPage?.sections || []).forEach((s) => {
			(s.questions || []).forEach((q) => {
				if (q.shouldRender === false) return;
				let allowed = [];
				try {
					const raw = q[FIELDS.Form_Question__c.ValueSet.fieldApiName];
					if (raw) {
						allowed = JSON.parse(raw).map((o) => o.value).filter(Boolean);
					}
				} catch (e) {
					allowed = [];
				}
				questions.push({
					questionId: q.Id,
					label: q[FIELDS.Form_Question__c.Question.fieldApiName] || q.Name,
					type: q[FIELDS.Form_Question__c.Type.fieldApiName],
					allowedValues: allowed
				});
			});
		});

		try {
			const result = await mapTranscriptToQuestions({ transcript, questions });
			const mappings = result?.mappings || [];
			if (!mappings.length) {
				const qCount = result?.questionCount;
				let detail;
				if (qCount === 0) {
					detail = "No questions visible on this page to match against.";
				} else if (result?.diagnostic) {
					detail = result.diagnostic;
				} else {
					detail = `Couldn't match any fields to what you said (${qCount} questions on page). Try mentioning the field name, like "the customer is John Doe".`;
				}
				this.showToastMessage('Info', detail, 'warning');
				return;
			}

			// 1) Update the data layer so question.answers[0] is right for
			//    every subsequent read (validation, save, future renders).
			mappings.forEach((r) => this.applyDictatedAnswer(r.questionId, r.value));

			// 2) Imperatively push values into the live input DOM via the
			//    setExternalValue chain. On FSL Mobile WKWebView, the
			//    @api -> getter -> lightning-input reactivity chain doesn't
			//    reliably update the visible value after first render.
			//    Walking the component tree and calling setExternalValue
			//    on each matching answer sidesteps that gap.
			const dictMap = {};
			mappings.forEach((m) => { dictMap[m.questionId] = m.value; });
			this.refs.formPage?.applyDictation?.(dictMap);

			const src = result?.source === 'agentforce' ? ' (Agentforce)' : '';
			this.showToastMessage(
				'Info',
				`Filled ${mappings.length} field${mappings.length === 1 ? '' : 's'} from dictation${src}. Review before continuing.`,
				'info'
			);
		} catch (err) {
			this.showToastMessage('Error', reduceError(err), 'error');
		}
	}

	// Plug a dictated value into the questionAnswerMap AND mirror it into
	// the question's answers array on the form object. The input components
	// read their displayed value from question.answers[0] (via
	// neuraFormAnswer's `value` getter), so updating only the answer map
	// wouldn't update what the user sees — the toast would claim "Filled N
	// fields" but the fields would still look empty.
	applyDictatedAnswer(questionId, value) {
		if (!questionId || value === null || value === undefined) return;

		// Locate the question on the current page (we need its type for the
		// Form_Answer payload, and we'll mutate its answers array below).
		let targetQuestion = null;
		(this.currentPage?.sections || []).forEach((s) => {
			(s.questions || []).forEach((q) => {
				if (q.Id === questionId) targetQuestion = q;
			});
		});

		const questionType = targetQuestion
			? targetQuestion[FIELDS.Form_Question__c.Type.fieldApiName]
			: null;

		const existing = this.questionAnswerMap.get(questionId) || {};
		const next = { ...existing, uploadCompleted: false };
		next[AnswerField.fieldApiName] = String(value);
		next[FormQuestionField.fieldApiName] = questionId;
		if (questionType) next[TypeField.fieldApiName] = questionType;

		this.questionAnswerMap.set(questionId, next);

		// Mirror the value into the question's answers array so the
		// neuraFormAnswer component's `value` getter picks it up. LWC's
		// @api setters only refire when the *reference* changes, so we
		// rebuild the whole page → section → question chain with new
		// object identities. Just mutating question.answers in place
		// leaves all parent refs identical and no setter fires.
		const newPages = this._formObject.pages.map((p, pIdx) => {
			if (pIdx !== this.currentPageIndex) return p;
			return {
				...p,
				sections: (p.sections || []).map((s) => ({
					...s,
					questions: (s.questions || []).map((q) => {
						if (q.Id !== questionId) return q;
						const merged = { ...(q.answers?.[0] || {}), ...next };
						return { ...q, answers: [merged] };
					})
				}))
			};
		});

		this._formObject = { ...this._formObject, pages: newPages };
		this.currentPage = this._formObject.pages[this.currentPageIndex];

		this.rebuildAnswerMap();
		this.updateRendering(questionId, false);
		this.dispatchUpdateFormDataEvent();
	}

	collectMissingRequiredLabels() {
		const out = [];
		try {
			(this.currentPage?.sections || []).forEach((section) => {
				(section.questions || []).forEach((q) => {
					const required = q[FIELDS.Form_Question__c.Required.fieldApiName];
					if (!required || q.shouldRender === false) return;
					const answer = this.questionAnswerMap?.get?.(q.Id);
					const value = answer?.[AnswerField.fieldApiName];
					const empty = value === undefined || value === null || String(value).trim() === '';
					if (empty) {
						const label = q[FIELDS.Form_Question__c.Question.fieldApiName] || q.Name || 'Unnamed question';
						out.push(label);
					}
				});
			});
		} catch (e) {
			console.warn('collectMissingRequiredLabels failed', e);
		}
		return out;
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
			new CustomEvent('message', {
				detail: { title, message, variant },
				bubbles: true,
				composed: true
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

	// Tracked review-mode flag. When the tech taps "Finish" on the last
	// page, we route them to the review screen FIRST (lists every answer,
	// includes an AI-generated summary). They submit from there; that's
	// what calls completeFinish() to mark the Linked_Form Completed.
	@track _inReview = false;
	get inReview() { return this._inReview; }

	async handleFinish() {
		// Save what we have before opening the review screen, so the
		// summary AI call sees the latest answers.
		try {
			await this.uploadAnswers();
		} catch (e) {
			// Non-fatal — review screen still shows what's in the in-memory
			// form object; tech can edit and resubmit.
			console.warn('Auto-save before review failed:', e);
		}
		this._inReview = true;
	}

	// Final commit. Wired to the review screen's `submit` event.
	// Persists the (possibly tech-edited) service summary, marks the LF
	// Completed, and triggers PDF generation. PDF generation is fire-and-
	// forget — we surface the resulting ContentDocumentId via state so
	// the completion screen can show a Download link, but a PDF failure
	// doesn't block the completion (the data is already saved).
	@track _generatedPdfId = null;
	@track _pdfGenerationStatus = 'idle'; // 'idle' | 'generating' | 'done' | 'error'
	@track _pdfGenerationError = '';
	get pdfGenerating() { return this._pdfGenerationStatus === 'generating'; }
	get pdfReady() { return this._pdfGenerationStatus === 'done' && !!this._generatedPdfId; }
	get pdfDownloadUrl() {
		return this._generatedPdfId
			? `/sfc/servlet.shepherd/document/download/${this._generatedPdfId}`
			: null;
	}

	async completeFinish(opts) {
		const summaryText = opts?.summary || '';
		try {
			// Save the summary to Linked_Form__c.Service_Summary__c so the
			// PDF, reports, and Chatter posts can all read it.
			if (summaryText && this.linkedFormId) {
				await updateRecord({
					fields: {
						Id: this.linkedFormId,
						Service_Summary__c: summaryText
					}
				});
			}
		} catch (e) {
			console.warn('Failed to save service summary:', e);
		}
		await this.updateLinkedForm('Completed');
		this._inReview = false;
		this._completed = true;

		// Kick off PDF generation. Awaited so the success screen can show
		// the download link the moment it's ready, but errors don't roll
		// back the completion.
		this._pdfGenerationStatus = 'generating';
		try {
			const docId = await generatePdfForLinkedForm({
				linkedFormId: this.linkedFormId
			});
			this._generatedPdfId = docId;
			this._pdfGenerationStatus = 'done';
		} catch (e) {
			this._pdfGenerationStatus = 'error';
			this._pdfGenerationError = reduceError(e);
		}
	}

	// "Edit" link from the review screen jumps the tech back to a specific
	// page so they can fix anything without losing context.
	handleReviewEdit(event) {
		const pageIndex = event?.detail?.pageIndex ?? 0;
		this._inReview = false;
		this.currentPageIndex = pageIndex;
		this.currentPage = this._formObject.pages[pageIndex];
	}

	handleReviewSubmit(event) {
		this.completeFinish({ summary: event?.detail?.summary });
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
		this.rebuildAnswerMap();

		if (
			answerObject.hasOwnProperty(FIELDS.Form_Answer__c.Answer.fieldApiName)
		) {
			this.updateRendering(questionId, false);
			this.dispatchUpdateFormDataEvent();
		}

		// Auto-save the in-flight answer to the offline draft queue so a
		// crash, phone call, or app kill doesn't lose this question's
		// value. Debounced 1500ms so a rapid burst of keystrokes coalesces
		// into a single save round-trip.
		this.scheduleAutoSave();
	}

	// --- Auto-save -----------------------------------------------------------
	//
	// Reactive state lives here so the template re-renders on transitions;
	// the actual state machine (debounce timer, dirty-check, save call,
	// error handling) lives in ./autoSaveController.js. The controller
	// is constructed in connectedCallback below.
	@track autoSaveStatus = 'idle'; // 'idle' | 'pending' | 'saving' | 'saved' | 'error'
	@track autoSaveLabel = '';
	_autoSave;
	_lastSavedAt = null;

	// --- Skip-and-return queue ---
	// Reactive @track array stays here so the template + the c-neura-form-page
	// child see updates; toggle + label formatting live in
	// ./skipQueueController.js.
	@track _skippedIds = [];
	get skippedCount() { return this._skippedIds.length; }
	get hasSkipped() { return this._skippedIds.length > 0; }
	get skippedBadgeLabel() { return formatSkippedBadgeLabel(this._skippedIds.length); }

	// --- Same-as-last-visit prefill ---
	// Pure helpers (host->parent-field map + message formatting) live in
	// ./prefillController.js; the orchestration here owns the Apex call,
	// the reactive answer-application, and the refs.formPage child poke.

	async handlePrefillLastVisit() {
		const parentField = parentFieldForHost(this.hostObjectApiName);
		const templateId = this._formObject?.Id;
		if (!parentField || !this.hostRecordId || !templateId) {
			this.showToastMessage('Info', PREFILL_MESSAGES.MISSING_CONTEXT, 'warning');
			return;
		}
		try {
			const prior = await getLastVisitAnswers({
				currentLinkedFormId: this.linkedFormId,
				formTemplateId: templateId,
				parentId: this.hostRecordId,
				parentField
			});
			if (!prior || !prior.length) {
				this.showToastMessage('Info', PREFILL_MESSAGES.NO_PRIOR_FOUND, 'info');
				return;
			}
			const dictMap = {};
			prior.forEach((p) => {
				this.applyDictatedAnswer(p.questionId, p.value);
				dictMap[p.questionId] = p.value;
			});
			this.refs.formPage?.applyDictation?.(dictMap);
			this.showToastMessage(
				'Info',
				formatPrefillSuccessMessage(prior.length),
				'info'
			);
		} catch (e) {
			this.showToastMessage('Error', reduceError(e), 'error');
		}
	}

	handleSkipToggle(event) {
		const id = event?.detail?.questionId;
		this._skippedIds = toggleSkipped(this._skippedIds, id);
	}

	get autoSaveBadgeClass() {
		const base = 'autosave-badge';
		return `${base} ${base}_${this.autoSaveStatus}`;
	}

	// Page-transition class. Toggles between two animation-name buckets
	// so the browser re-runs the enter animation on every page change.
	// (CSS animations don't re-fire unless the animation-name changes.)
	get pageWrapperClass() {
		const idx = Number(this.currentPageIndex) || 0;
		return `page-wrapper page-wrapper_${idx % 2 === 0 ? 'a' : 'b'}`;
	}

	// --- Swipe-between-pages gesture ----------------------------------------
	// Logic lives in ./swipeController.js. The renderer just owns the
	// callback that translates a 'previous'|'next' direction into the
	// existing footer-click navigation path (so validation, save, and
	// the page animation all run identically to a button-driven flow).
	_swipe = createSwipeController({
		onNavigate: (direction) => {
			this.handleFooterButtonClick({ detail: { actionType: direction } });
		}
	});

	handlePageSwipeStart(event) { this._swipe.onTouchStart(event); }
	handlePageSwipeEnd(event)   { this._swipe.onTouchEnd(event); }
	// --- /Swipe-between-pages -----------------------------------------------

	// Bridge the auto-save controller's state-change callback into the
	// renderer's reactive @track fields + the draftstate CustomEvent
	// consumed by c-neura-draft-queue-badge in the mobile shell.
	_handleAutoSaveStateChange(state) {
		this.autoSaveStatus = state.status;
		this.autoSaveLabel = state.label;
		this._lastSavedAt = state.lastSavedAt;
		this.dispatchEvent(new CustomEvent('draftstate', {
			detail: state.draftState,
			bubbles: true,
			composed: true
		}));
	}

	_initAutoSave() {
		if (this._autoSave) return;
		this._autoSave = createAutoSaveController({
			getDirtyAnswers: () => this.questionAnswerMap,
			getLinkedFormId: () => this._formObject?.linkedForm?.Id,
			getFormFactor: () => formFactorPropertyName,
			save: saveAnswers,
			onStateChange: (state) => this._handleAutoSaveStateChange(state)
		});
	}

	scheduleAutoSave() {
		this._initAutoSave();
		this._autoSave.schedule();
	}
	// --- /Auto-save ----------------------------------------------------------

	getBooleanQuestions(section) {
		// Delegates to ./booleanQuestionUtils.js — the boolean-type
		// registry lives there so adding a new boolean-flavored type is
		// a one-line change, not a hunt through this class.
		return filterBooleanQuestions(
			section && section.questions,
			FIELDS.Form_Question__c.Type.fieldApiName
		);
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
		// Per-condition answer resolution stays here because it consults
		// both the in-memory questionAnswerMap (live edits) and the
		// server-side persisted answers via checkInSavedAnswers. The
		// expression-building + eval is in
		// ./conditionalRenderingEvaluator.js so each operator branch is
		// directly unit-tested.
		const answerFieldName = FIELDS.Form_Answer__c.Answer.fieldApiName;
		return buildKeyConditionMap(conditions, (questionId) => {
			if (this.questionAnswerMap.has(questionId)) {
				const answerAvailable = this.questionAnswerMap.get(questionId);
				if (Object.prototype.hasOwnProperty.call(answerAvailable, answerFieldName)) {
					const v = answerAvailable[answerFieldName];
					if (v) return v;
				}
			}
			const answers = this.checkInSavedAnswers(questionId, false);
			if (answers && answers.length) {
				return answers[0][answerFieldName];
			}
			return undefined;
		});
	}

	// Back-compat shim — preserved so any external caller (or future
	// inline use) continues to work; delegates to the extracted module.
	isNumericValue(str) {
		return _isNumericValueImpl(str);
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