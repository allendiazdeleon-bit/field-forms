import { LightningElement, api } from 'lwc';
import LightningConfirm from 'lightning/confirm';
import { debug, getComputedHeight } from 'c/utilsImageCapture';
import FORM_FACTOR from '@salesforce/client/formFactor';
import neuraFormFileBulkNameUpdateModal from 'c/neuraFormFileBulkNameUpdateModal';

export default class ImageSelector extends LightningElement {
	@api
	existingImagesData = [];

	@api
	allImagesData;

	@api
	layoutStyle = 'large';

	isViewMode = false;

	get numberOfPhotos() {
		return this.existingImagesData.length;
	}

	get showExistingPhotos() {
		return this.existingImagesData.length > 0;
	}

	get isLayoutSmall() {
		return this.layoutStyle === 'small';
	}

	get isLayoutLarge() {
		return this.layoutStyle === 'large';
	}
	// Testing
	@api
	triggerFileSelect() {
		let upload = this.template.querySelector('[data-id="file-upload-input"]');
		console.log('upload', upload);
		if (upload) {
			upload.click();
		}
	}

	handleCancel() {
		this.isViewMode = false;

		this.dispatchEvent(new CustomEvent('cancelupload'));
		this.previewImage = null;
		this.dispatchEvent(
			new CustomEvent('overlaystate', {
				detail: false,
				bubbles: true,
				composed: true
			})
		);
	}

	handlePhotoOpen(event) {
		this.triggerFileSelect();
	}

	handleViewAll() {
		this.isViewMode = true;
		this.allImagesData = [...this.existingImagesData];
	}

	previewImage = null;
	maxHeightForPreview;
	pageWidth;

	get totalSelectedImages() {
		return this.allImagesData.length;
	}

	get noImagesSelected() {
		return this.totalSelectedImages === 0 && !this.isPreviewingImage;
	}

	get someImagesSelected() {
		return this.totalSelectedImages > 0 && !this.isPreviewingImage;
	}

	get isPreviewingImage() {
		return this.previewImage !== null;
	}

	get imageText() {
		return this.totalSelectedImages > 1 ? 'images' : 'image';
	}

	get previewContainer() {
		return this.template.querySelector('[data-id="preview-container"]');
	}

	get imagesListContainer() {
		return this.template.querySelector('[data-id="images-list-container"]');
	}

	get imageInfoViewer() {
		return this.template.querySelector('[data-id="image-info-viewer"]');
	}

	handleImageSelectedForEditDirectly(event) {
		if (!this.isViewMode) {
			const selectedId = parseInt(event.currentTarget.dataset.id, 10);
			for (const item of this.allImagesData) {
				if (item.id === selectedId) {
					this.previewImage = item;
					break;
				}
			}

			// Use the height of the images list container as the max height for the preview
			this.maxHeightForPreview = getComputedHeight(this.imagesListContainer);

			this.pageWidth = window.innerWidth;

			this.dispatchEvent(
				new CustomEvent('annotateimage', {
					detail: selectedId
				})
			);
		}
	}

	handleImageSelectedForPreview(event) {
		const selectedId = parseInt(event.currentTarget.dataset.id, 10);
		for (const item of this.allImagesData) {
			console.log('item: ' + JSON.stringify(item));
			if (item.id === selectedId) {
				this.previewImage = item;
				break;
			}
		}

		// Use the height of the images list container as the max height for the preview
		this.maxHeightForPreview = getComputedHeight(this.imagesListContainer);

		this.pageWidth = window.innerWidth;
	}

	handlePreviewScreenRendered() {
		debug('Preview container max height = ' + this.maxHeightForPreview);
		this.previewContainer.style.maxHeight = this.maxHeightForPreview + 'px';
		this.imageInfoViewer.style.maxWidth =
			this.previewContainer.offsetWidth + 'px';
	}

	backToPreviewAllImages() {
		this.previewImage = null;
	}

	async handleRemoveClicked(event) {
		const selectedId = parseInt(event.currentTarget.dataset.id, 10);
		const result = await LightningConfirm.open({
			message: 'Removing the image deletes it from your uploaded images.',
			variant: 'header',
			label: 'Remove image?',
			theme: 'error'
		});

		if (result === true) {
			for (const item of this.allImagesData) {
				if (item.id === selectedId) {
					this.previewImage = item;
					break;
				}
			}
			if (this.previewImage) {
				this.dispatchEvent(
					new CustomEvent('delete', {
						detail: this.previewImage.id
					})
				);

				this.previewImage = null;
			}
		}
	}

	handleImageSelectedForAnnotation() {
		const selectedId = this.previewImage.id;
		this.dispatchEvent(
			new CustomEvent('annotateimage', {
				detail: selectedId
			})
		);
	}

	async handleFilesSelected(event) {
		const files = event.target.files;

		this.dispatchEvent(
			new CustomEvent('selectimages', {
				detail: files
			})
		);

		// send an event to trigger overlay sizing
		this.dispatchEvent(
			new CustomEvent('overlaystate', {
				detail: true,
				bubbles: true,
				composed: true
			})
		);
	}

	readAsArrayBuffer(file) {
		return new Promise((resolve, reject) => {
			const reader = new FileReader();
			reader.onloadend = (ev) => {
				resolve(ev.target.result);
			};
			reader.onerror = () => {
				reject(
					`There was an error reading file: '${file.name}', error: ${reader.error}`
				);
			};

			try {
				reader.readAsArrayBuffer(file);
			} catch (err) {
				reject(new Error('Unable to read the input data.'));
			}
		});
	}

	async handleUploadClicked() {
		const result = await LightningConfirm.open({
			message: "After uploading the images you can't edit them.",
			variant: 'header',
			label: 'Add images to record?',
			theme: 'success'
		});

		if (result) {
			this.dispatchEvent(new CustomEvent('uploadrequest'));
			this.dispatchEvent(
				new CustomEvent('overlaystate', {
					detail: false,
					bubbles: true,
					composed: true
				})
			);
		}
	}

	renderedCallback() {
		//this.triggerFileSelect();
	}

	handleBatchRename() {
		neuraFormFileBulkNameUpdateModal.open({
			// `label` is not included here in this example.
			// it is set on lightning-modal-header instead
			size: 'large',
			description: 'Handle Bulk Update File Name',
			onupdatebulkfilename: (event) => {
				event.stopPropagation();
				this.handleSave(event);
			}
		});
	}

	handleSave(event) {
		this.dispatchEvent(
			new CustomEvent('updatefilename', {
				detail: {
					batchNamePrefix: event.detail.batchNamePrefix,
					batchNameSuffix: event.detail.batchNameSuffix
				}
			})
		);
	}

	get viewMode() {
		switch (FORM_FACTOR) {
			case 'Small':
				return 'Phone';
				break;
			case 'Medium':
				return 'Tablet';
				break;
			case 'Large':
			default:
				return 'Desktop';
				break;
		}
	}

	get pageClass() {
		switch (this.viewMode) {
			case 'Phone':
			case 'Tablet':
				return 'phone-container page-container';
			case 'Desktop':
			default:
				return 'desktop-container page-container';
		}
	}

	get bodyClass() {
		switch (this.viewMode) {
			case 'Phone':
			case 'Tablet':
				return 'phone-body page-body';
			case 'Desktop':
			default:
				return 'desktop-body page-body';
		}
	}

	get footerClass() {
		switch (this.viewMode) {
			case 'Phone':
			case 'Tablet':
				return 'phone-footer page-footer';
			case 'Desktop':
			default:
				return 'desktop-footer page-footer';
		}
	}
}