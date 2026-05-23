import { LightningElement, api, track } from 'lwc';
import { getValue } from 'c/neuraFormUtils';
import { store } from 'c/neuraFormStore';
import AnswerField from '@salesforce/schema/Form_Answer__c.Answer__c';
import CommentField from '@salesforce/schema/Form_Answer__c.Related_Comment__c';
import TypeField from '@salesforce/schema/Form_Answer__c.Type__c';
import FormQuestionField from '@salesforce/schema/Form_Answer__c.Form_Question__c';
import IdField from '@salesforce/schema/Form_Answer__c.Id';

import { FIELDS } from 'c/neuraFormSchemaUtils';

const FORMFACTORCLASS = {
	desktop:
		'slds-large-size_1-of-3 slds-medium-size_1-of-2 slds-small-size_1-of-1 slds-m-bottom_small',
	tablet:
		'slds-large-size_1-of-2 slds-medium-size_1-of-2 slds-small-size_1-of-1 slds-m-bottom_small',
	tabletFlipped:
		'slds-large-size_1-of-2 slds-medium-size_1-of-2 slds-small-size_1-of-1 slds-m-bottom_small',
	phone:
		'slds-large-size_1-of-1 slds-medium-size_1-of-1 slds-small-size_1-of-1 slds-m-bottom_small'
};
export default class NeuraFormAnswer extends LightningElement {
	_viaBuilder = false;
	@api
	get viaBuilder() {
		return this._viaBuilder;
	}
	set viaBuilder(value) {
		this._viaBuilder = value;
	}

	_builderFormFactor = 'desktop-view';
	@api
	get builderFormFactor() {
		return this._builderFormFactor;
	}
	set builderFormFactor(value) {
		this._builderFormFactor = value;
	}

	@api question;

	@api recordId;
	@api inputType;
	@api isRequired;

	@api checkValidity() {
		let isValid = true;
		if (
			this.isDatePicker ||
			this.isEmail ||
			this.isNumberInput ||
			this.isTimePicker
		) {
			const inputField = this.template.querySelector('lightning-input');
			inputField.reportValidity();
			isValid = inputField.checkValidity();
		}

		if (
			this.notToCheckRequiredValidation &&
			isValid &&
			this.isRequired &&
			((this.hasAnswerChanged &&
				((this.isCheckbox && !this.checkboxValue) ||
					(this.isFilesRelated && !this.existingFilesData.length) ||
					(!this.isCheckbox && !this.isFilesRelated && !this.answerValue))) ||
				this.isValueBlank())
		) {
			isValid = false;
			if (
				this.isTextBox ||
				this.isCheckbox ||
				this.isDatePicker ||
				this.isTimePicker ||
				this.isNumberInput ||
				this.isEmail ||
				this.isPhone
			) {
				this.template
					.querySelector('lightning-input')
					.setCustomValidity('Complete this field.');
				this.template.querySelector('lightning-input').reportValidity();
			} else if (this.isTextArea) {
				this.template
					.querySelector('lightning-textarea')
					.setCustomValidity('Complete this field.');
				this.template.querySelector('lightning-textarea').reportValidity();
			} else if (
				this.isMultipleChoice ||
				this.isRadioButtons ||
				this.isRating ||
				this.isGeolocation ||
				this.isFileUpload ||
				this.isSignature ||
				this.isScanBarcode
			) {
				this.showInlineErrorMessage = true;
			} else if (this.isDropDown) {
				this.template
					.querySelector('lightning-combobox')
					.setCustomValidity('Complete this field.');
				this.template.querySelector('lightning-combobox').reportValidity();
			}
		}

		return isValid;
	}

	@track answerValue;
	@track relatedCommentValue;
	@track filesData = [];
	checkboxValue = false;

	@track notUploadedFilesData = [];

	hasAnswerChanged = false;
	showInlineErrorMessage = false;

	builderSizingClass(isLastLine) {
		// if desktop then return column size = to colSize
		if (this.colSize === 1) {
			return this.standardBuilderSizing(1);
		}

		if (
			this.builderFormFactor === 'desktop-view' ||
			this.builderFormFactor === 'tablet-flipped-view'
		) {
			return this.standardBuilderSizing(this.colSize);
		}
		// if tablet then return 2 and 1
		if (this.builderFormFactor === 'tablet-view') {
			let tempSize = isLastLine && this.colSize === 3 ? 1 : 2;
			return this.standardBuilderSizing(tempSize);
		}
		// if phone then each element will take up its own line.
		return this.standardBuilderSizing(1);
	}

	// Use this for the first to columns sizing
	get columnSizingClass() {
		let mediumSize = this.colSize === 3 ? 2 : this.colSize;
		return this.viaBuilder
			? this.builderSizingClass(false)
			: this.standardSizing(this.colSize, mediumSize);
	}

	// TODO: need to adjust as causing issues.
	standardSizing(largeCol, mediumCol) {
		return `slds-col slds-align-middle slds-size_1-of-1 slds-large-size_1-of-${largeCol} slds-medium-size_1-of-${mediumCol} slds-small-size_1-of-1 slds-m-bottom_small`;
		//return `slds-col slds-align-middle slds-large-size_1-of-${largeCol} slds-medium-size_1-of-${mediumCol} slds-small-size_1-of-1`;
	}

	standardBuilderSizing(colSize) {
		return `slds-col slds-align-middle slds-size_1-of-${colSize} slds-m-bottom_small`;
	}

	// use this for the last column sizing
	get lastColSizingClass() {
		let mediumSize = this.colSize === 3 ? 3 : 1;
		return this.viaBuilder
			? this.builderSizingClass(true)
			: this.standardSizing(this.colSize, mediumSize);
	}

	get colSize() {
		let colSize = 1;
		this.isIncludeComment ? colSize++ : colSize;
		this.isIncludePhoto ? colSize++ : colSize;
		return colSize;
	}

	handleChange(event) {
		const dataId = event.target.dataset.id;

		if (dataId === 'checkboxButton' || dataId === 'toggle') {
			this.checkboxValue = event.detail.checked;
			this.answerValue = String(event.detail.checked);
		} else {
			this.answerValue = event.detail.value;
		}

		this.resetInlineMessageError();

		this.dispatchChangeEvent();
	}

	/**
	 * Voice transcription handler: appends spoken text to the current answer
	 * for Text/Text Area questions. We append rather than replace so multiple
	 * sentences can be dictated in sequence.
	 */
	handleVoiceTranscript({ detail }) {
		const text = (detail?.text || '').trim();
		if (!text) return;
		const existing = this.answerValue ? String(this.answerValue) : '';
		const separator = existing && !existing.endsWith(' ') ? ' ' : '';
		this.answerValue = existing + separator + text;
		this.resetInlineMessageError();
		this.dispatchChangeEvent();
	}

	handleCommentChange({ detail }) {
		if (
			(this.inputType === 'Toggle' || this.inputType === 'Checkbox') &&
			!this.answerValue
		) {
			this.answerValue = 'false';
		}

		this.relatedCommentValue = detail.value;

		this.dispatchChangeEvent();
	}

	handleAddImages({ detail }) {
		this.resetInlineMessageError();

		this.filesData = detail.value;

		this.filesData.forEach((item) => {
			this.notUploadedFilesData.push(item);
		});

		this.dispatchChangeEvent();
	}

	resetInlineMessageError() {
		this.hasAnswerChanged = true;
		this.showInlineErrorMessage = false;
		if (
			this.isTextBox ||
			this.isCheckbox ||
			this.isDatePicker ||
			this.isTimePicker ||
			this.isNumberInput ||
			this.isEmail ||
			this.isPhone
		) {
			this.template.querySelector('lightning-input').setCustomValidity('');
			this.template.querySelector('lightning-input').reportValidity();
		} else if (this.isTextArea) {
			this.template.querySelector('lightning-textarea').setCustomValidity('');
			this.template.querySelector('lightning-textarea').reportValidity();
		} else if (this.isDropDown) {
			this.template.querySelector('lightning-combobox').setCustomValidity('');
			this.template.querySelector('lightning-combobox').reportValidity();
		}
	}

	dispatchChangeEvent() {
		const answer = {};

		this.assignFieldValues(
			answer,
			FIELDS.Form_Answer__c.Answer.fieldApiName,
			this.answerValue
		);
		this.assignFieldValues(
			answer,
			FIELDS.Form_Answer__c.FormQuestion.fieldApiName,
			this.question.Id
		);
		this.assignFieldValues(
			answer,
			FIELDS.Form_Answer__c.Type.fieldApiName,
			this.question[FIELDS.Form_Question__c.Type.fieldApiName]
		);
		this.assignFieldValues(
			answer,
			FIELDS.Form_Answer__c.RelatedComment.fieldApiName,
			this.relatedCommentValue
		);
		this.assignFieldValues(
			answer,
			FIELDS.Form_Answer__c.Id.fieldApiName,
			this.answerId
		);
		this.assignFieldValues(answer, 'filesData', this.filesData);

		this.dispatchEvent(
			new CustomEvent('answerchange', {
				detail: {
					answer
				},
				composed: true,
				bubbles: true
			})
		);

		this.filesData = [];
	}

	assignFieldValues(targetObj, fieldApiName, value) {
		if (value !== undefined) {
			targetObj[fieldApiName] = value;
		}
	}

	isValueBlank() {
		return (
			!this.hasAnswerChanged &&
			((!this.isFilesRelated && (!this.value || this.value.length === 0)) ||
				(this.isFilesRelated && this.existingFilesData.length === 0))
		);
	}

	get answerToQuestion() {
		return this.question?.answers?.length > 0 ? this.question.answers[0] : null;
	}

	get value() {
		const answer = getValue(
			this.answerToQuestion,
			AnswerField.fieldApiName,
			''
		);
		if (this.isSlider) {
			return Number(answer);
		} else if (this.isCheckbox || this.isToggle) {
			return answer === 'true' ? true : false;
		}
		return answer;
	}

	get existingFilesData() {
		let tempFilesData = JSON.parse(
			JSON.stringify(getValue(this.answerToQuestion, 'filesData', []))
		);

		this.notUploadedFilesData.forEach((item) => {
			tempFilesData.push(item);
		});

		return tempFilesData;
	}

	get answerId() {
		return this.answerToQuestion?.Id;
	}

	get isIncludeComment() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.IncludeComment.fieldApiName,
			false
		);
	}

	get commentValue() {
		return getValue(
			this.answerToQuestion,
			FIELDS.Form_Answer__c.RelatedComment.fieldApiName,
			''
		);
	}

	get isIncludePhoto() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.IncludePhoto.fieldApiName,
			false
		);
	}

	/**
     * Getters for each of the following input types
     * Text Box (Short Answer)
    Text Area (Long Answer)
    Multiple Choice
    Checkboxes
    Dropdown Menu
    Radio Buttons
    Date Picker
    Time Picker
    Number Input
    Email Address Field
    Phone Number Field
    Rating Scale (e.g., 1-5 Stars)
    Slider
    File Upload
     */
	get options() {
		let optionsJSONString = this.radioOptions;
		let options = JSON.parse(optionsJSONString);

		return options;
	}

	get radioOptions() {
		// the question will have a list of options in a comma separated string, we need to split it into a option select style list {lavel: 'label', value: 'value'}
		const raw = getValue(
			this.question,
			FIELDS.Form_Question__c.ValueSet.fieldApiName,
			''
		);
		// Rating questions without an explicit value set used to render a
		// single empty radio (1 star with no value), which the user could
		// "click" but selection silently produced an undefined value and
		// required-field validation always failed. Default to 1-5 so the
		// star input is always functional.
		if ((!raw || raw === '[{}]' || raw === '[]') && this.inputType === 'Rating') {
			return JSON.stringify([
				{ id: 'r1', label: '1', value: '1', icon: '' },
				{ id: 'r2', label: '2', value: '2', icon: '' },
				{ id: 'r3', label: '3', value: '3', icon: '' },
				{ id: 'r4', label: '4', value: '4', icon: '' },
				{ id: 'r5', label: '5', value: '5', icon: '' }
			]);
		}
		return raw || '[{}]';
	}

	get sliderSize() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.SliderSize.fieldApiName,
			''
		);
	}

	get sliderStep() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.SliderStep.fieldApiName,
			1
		);
	}

	get max() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.Max.fieldApiName,
			''
		);
	}

	get min() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.Min.fieldApiName,
			''
		);
	}

	get numberStep() {
		const decimalPlaces = getValue(
			this.question,
			FIELDS.Form_Question__c.DecimalPlaces.fieldApiName,
			0
		);
		if (decimalPlaces === 0) {
			return 1;
		}
		return Math.pow(10, -decimalPlaces);
	}

	get toggleActiveMessage() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.ActiveMessage.fieldApiName,
			'Active'
		);
	}

	get toggleInactiveMessage() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.InactiveMessage.fieldApiName,
			'Inactive'
		);
	}

	get uniqueName() {
		//return this.question.fields.Id.value;
		return this.question.Id;
	}

	get isTextBox() {
		return this.inputType === 'Text';
	}

	get isTextArea() {
		return this.inputType === 'Text Area';
	}

	get isRadioButtons() {
		return this.inputType === 'Radio Buttons';
	}

	get isScanBarcode() {
		return this.inputType === 'Scan Barcode';
	}

	get isDatePicker() {
		return this.inputType === 'Date';
	}

	get isSlider() {
		return this.inputType === 'Slider';
	}

	get isTimePicker() {
		return this.inputType === 'Time';
	}

	get isNumberInput() {
		return this.inputType === 'Number';
	}

	get isEmail() {
		return this.inputType === 'Email';
	}

	get isPhone() {
		return this.inputType === 'Phone';
	}

	get isRatingScale() {
		return this.inputType === 'Rating';
	}

	get isSlider() {
		return this.inputType === 'Slider';
	}

	get isFileUpload() {
		return this.inputType === 'File Upload';
	}

	get isCheckbox() {
		return this.inputType === 'Checkbox';
	}

	get isCheckboxes() {
		return this.inputType === 'Checkboxes';
	}

	get isRating() {
		return this.inputType === 'Rating';
	}

	get isDropDown() {
		return this.inputType === 'Dropdown';
	}
	get isGeolocation() {
		return this.inputType === 'Geolocation';
	}

	get isToggle() {
		return this.inputType === 'Toggle';
	}

	get isSignature() {
		return this.inputType === 'Signature';
	}

	get isMultipleChoice() {
		return this.inputType === 'Multiple Choice';
	}

	get isCalculation() {
		return this.inputType === 'Calculation';
	}

	get isPassFailNa() {
		return this.inputType === 'Pass Fail NA';
	}

	get isCounter() {
		return this.inputType === 'Counter';
	}

	get isDateTime() {
		return this.inputType === 'Date Time';
	}

	get isCurrency() {
		return this.inputType === 'Currency';
	}

	get isLookup() {
		return this.inputType === 'Lookup';
	}

	get isRepeatable() {
		return this.inputType === 'Repeatable';
	}

	get isChecklist() {
		return this.inputType === 'Checklist';
	}

	// --- Choice-pills routing -----------------------------------------------
	//
	// Multiple Choice / Dropdown / Radio Buttons render as pill-segmented
	// buttons when option count is small enough that they fit comfortably,
	// otherwise fall back to the legacy combobox. The threshold is the
	// point past which pills start to feel cluttered on a phone-width
	// viewport (~6 options wrap onto 2 rows; >6 should be a searchable
	// combobox).
	get _CHOICE_PILL_THRESHOLD() { return 6; }

	get useChoicePills() {
		const opts = this.options;
		if (!Array.isArray(opts)) return false;
		return opts.length > 0 && opts.length <= this._CHOICE_PILL_THRESHOLD;
	}

	get useMultipleChoicePills() {
		return this.isMultipleChoice && this.useChoicePills;
	}
	get useMultipleChoiceCombobox() {
		return this.isMultipleChoice && !this.useChoicePills;
	}

	get useDropDownPills() {
		return this.isDropDown && this.useChoicePills;
	}
	get useDropDownCombobox() {
		return this.isDropDown && !this.useChoicePills;
	}

	get useRadioButtonsPills() {
		// Radio Buttons always uses pills (the legacy segmented control
		// can't handle >6 options on a phone width cleanly anyway, and
		// admins picking "Radio Buttons" specifically expect a row-style
		// affordance). For >6 options the pills will wrap.
		return this.isRadioButtons;
	}

	// --- Lookup config (read from Form_Question__c.Lookup_*__c fields) ------
	get lookupRelatedList() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.LookupRelatedList.fieldApiName,
			''
		);
	}
	get lookupChildObject() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.LookupChildObject.fieldApiName,
			''
		);
	}
	get lookupDisplayField() {
		return getValue(
			this.question,
			FIELDS.Form_Question__c.LookupDisplayField.fieldApiName,
			''
		);
	}

	get calculationFormula() {
		return this.question?.[FIELDS.Form_Question__c.CalculationFormula.fieldApiName] || '';
	}

	get calculationResultFormat() {
		return this.question?.[FIELDS.Form_Question__c.CalculationResultFormat.fieldApiName] || 'Decimal';
	}

	get questionId() {
		return this.question?.Id;
	}

	// Map of { questionId -> answer value } passed in by the parent renderer.
	// The Calculation input subscribes to this for reactivity.
	@api answerMap;

	get notToCheckRequiredValidation() {
		return !this.isToggle && !this.isSlider;
	}

	get isFilesRelated() {
		return this.isFileUpload || this.isSignature;
	}

	connectedCallback() {
		this.unsubscribe = store.subscribe(this.handleStoreUpdate.bind(this));
		const state = store.getState();
		this._builderFormFactor = state.builderFormFactor;
		this._viaBuilder = state.viaBuilder;
	}

	handleStoreUpdate(state) {
		this._builderFormFactor = state.builderFormFactor;
		this._viaBuilder = state.viaBuilder;
	}

	disconnectedCallback() {
		if (this.unsubscribe) {
			this.unsubscribe();
		}
	}

	/**
	 * Imperatively push a dictation/prefill value into the rendered input
	 * AND propagate it through the normal answer-change pipeline. Used by
	 * the renderer after an Agentforce dictation maps a transcript to
	 * fields — see neuraFormRenderer.applyDictatedAnswer.
	 *
	 * Why imperative? On FSL Mobile (WKWebView), lightning-input doesn't
	 * always re-pick up its `value` prop after the first render, so just
	 * updating question.answers[0] doesn't visually fill the field. We
	 * find the DOM element and set .value directly, then dispatch the
	 * standard change event so the upstream questionAnswerMap also
	 * updates as if the user had typed.
	 */
	@api
	setExternalValue(val) {
		if (val === undefined || val === null) return;
		const str = String(val);
		this.answerValue = str;

		// Cover the input types that hold a freeform string value. For
		// choice types (multiple choice, dropdown, checkboxes), the value
		// gets picked up through the @api question -> value getter path
		// because their components read each render — only the freeform
		// inputs need the imperative shove.
		const candidates = [
			'lightning-input[data-id="textBox"]',
			'lightning-input[data-id="numberInput"]',
			'lightning-input[data-id="email"]',
			'lightning-input[data-id="phone"]',
			'lightning-input[data-id="datePicker"]',
			'lightning-input[data-id="timePicker"]',
			'lightning-textarea[data-id="textArea"]'
		];
		for (const sel of candidates) {
			const el = this.template.querySelector(sel);
			if (el) {
				el.value = str;
			}
		}

		this.resetInlineMessageError();
		this.dispatchChangeEvent();
	}

	// Add similar getters for other input types (Checkboxes, Dropdown Menu, etc.)

	// Additional logic and methods...
}