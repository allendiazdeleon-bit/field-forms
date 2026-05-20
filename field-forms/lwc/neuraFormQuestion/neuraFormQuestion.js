import { LightningElement, api } from 'lwc';
import { getValue } from 'c/neuraFormUtils';
import { FIELDS } from 'c/neuraFormSchemaUtils';

// target="_blank" anchors and record-id links don't navigate inside FSL Mobile's
// WebView (lightning-formatted-rich-text limitation). Strip the target so the
// link is at least readable in the field; rel="noopener" is added defensively.
function sanitizeRichTextForOffline(html) {
    if (!html || typeof html !== 'string') return html;
    return html
        .replace(/\starget=("|')_blank\1/gi, ' rel="noopener"')
        .replace(/\stargetname=("|')_blank\1/gi, '');
}

export default class NeuraFormQuestion extends LightningElement {
	@api recordId;
	@api formQuestion;

	@api checkValidity() {
		return !this.isLayoutItem ? this.refs.formAnswer.checkValidity() : true;
	}

	showFileUpload = false;

	get isLabelVisible() {
		return getValue(
			this.formQuestion,
			FIELDS.Form_Question__c.LabelVisible.fieldApiName,
			true
		);
	}

	// TODO - FIX THIS TO USE A Display Type - requires fixing the builder to include a 'display' vs 'input' style type when creating new questions.
	get isLayoutItem() {
		return this.questionType === 'Display Text';
	}

	get layoutItemRichText() {
		const raw = getValue(
			this.formQuestion,
			FIELDS.Form_Question__c.DisplayRichText.fieldApiName,
			''
		);
		return sanitizeRichTextForOffline(raw);
	}

	get labelStyle() {
		const alignment = getValue(
			this.formQuestion,
			FIELDS.Form_Question__c.TextAlignment.fieldApiName,
			'left'
		);
		const fontSize = getValue(
			this.formQuestion,
			FIELDS.Form_Question__c.FontSize.fieldApiName,
			'14px'
		);
		const color = getValue(
			this.formQuestion,
			FIELDS.Form_Question__c.FontColor.fieldApiName,
			'#000000'
		);

		return `${alignment ? `text-align: ${alignment};` : ''}${fontSize ? ` font-size: ${fontSize};` : ''}${color ? ` color: ${color};` : ''}`;
	}

	get question() {
		return getValue(
			this.formQuestion,
			FIELDS.Form_Question__c.Question.fieldApiName,
			''
		);
	}

	get isIncludeComment() {
		return getValue(
			this.formQuestion,
			FIELDS.Form_Question__c.IncludeComment.fieldApiName,
			false
		);
	}
	get isIncludePhoto() {
		return getValue(
			this.formQuestion,
			FIELDS.Form_Question__c.IncludePhoto.fieldApiName,
			false
		);
	}

	get questionType() {
		return getValue(
			this.formQuestion,
			FIELDS.Form_Question__c.Type.fieldApiName,
			'Text'
		);
	}

	get isRequired() {
		return getValue(
			this.formQuestion,
			FIELDS.Form_Question__c.Required.fieldApiName,
			false
		);
	}

	handleFileUpload() {
		this.showFileUpload = true;
	}
}