import { LightningElement, api, track } from 'lwc';
import { processImage } from 'lightning/mediaUtils';
import { log, debug, ToastTypes } from 'c/utilsImageCapture';

export default class ImageCapture extends LightningElement {
	@api
	layoutStyle = 'large';

	@api get filesData() {
		return this.existingImagesData;
	}
	set filesData(value) {
		this.existingImagesData = [...value];
	}

	@track
	existingImagesData = [];

	@track
	allImagesData = [];

	@api showcustomtextbox = false;

	compressionOptions = {
		compressionEnabled: true,
		resizeMode: 'contain',
		resizeStrategy: 'reduce',
		targetWidth: 2048,
		targetHeight: 2048,
		compressionQuality: 0.75,
		imageSmoothingEnabled: true,
		preserveTransparency: false,
		backgroundColor: 'white'
	};

	nextId = 0;

	isReading = false;
	selectedImageInfo;
	isUploading = false;
	toastType = null;
	numPhotosToUpload = 0;
	numSuccessfullyUploadedPhotos = 0;

	get numFailedUploadPhotos() {
		return this.numPhotosToUpload - this.numSuccessfullyUploadedPhotos;
	}

	get shouldShowToast() {
		return this.toastType == null ? false : true;
	}

	get isImageSelected() {
		return this.selectedImageInfo != null;
	}

	get toastMessage() {
		switch (this.toastType) {
			case ToastTypes.Success: {
				const imageString =
					this.numPhotosToUpload > 1 ? 'images were' : 'image was';
				return `${this.numPhotosToUpload} ${imageString} added to the record.`;
			}
			case ToastTypes.Error: {
				return "We couldn't add the images to the record. Try again.";
			}
			case ToastTypes.Warning: {
				return `We couldn't add ${this.numFailedUploadPhotos}/${this.numPhotosToUpload} images to the record. Try again or contact your admin for help.`;
			}
			default: {
				return '';
			}
		}
	}

	async handleImagesSelected(event) {
		const files = event.detail;
		const numFiles = files.length;
		const compressionEnabled = this.compressionOptions.compressionEnabled;
		log(
			`Reading ${
				compressionEnabled ? 'and compressing ' : ''
			}${numFiles} images`
		);

		this.isReading = true;

		try {
			for (let i = 0; i < numFiles; i++) {
				let file = files[i];

				let blob;
				if (compressionEnabled) {
					// Compress the image when reading it, so we work with smaller files in memory
					blob = await processImage(file, this.compressionOptions);
				} else {
					blob = file;
				}

				let data = await this.readFile(blob);
				let metadata = await this.readMetadata(file);

				this.allImagesData.push({
					id: this.nextId++,
					data: data,
					description: '',
					editedImageInfo: {},
					metadata: metadata,
					expectedSize: blob.size
				});
			}
		} finally {
			this.isReading = false;
		}
	}

	// Read image data from a file selected in a browser.
	// This is standard JavaScript, not unique to LWC.
	readFile(file) {
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
				reader.readAsDataURL(file);
			} catch (err) {
				reject(new Error('Unable to read the input data.'));
			}
		});
	}

	readMetadata(file) {
		return new Promise((resolve) => {
			const fullFileName = file.name;
			const ext = fullFileName.slice(
				(Math.max(0, fullFileName.lastIndexOf('.')) || Infinity) + 1
			);
			const fileNameWithoutExt = fullFileName.substring(
				0,
				fullFileName.length - ext.length - (ext ? 1 : 0)
			);

			const metadata = {
				fileName: fileNameWithoutExt,
				ext: ext,
				edited: false
			};

			debug(`Metadata for '${fullFileName}': ${JSON.stringify(metadata)}`);
			resolve(metadata);
		});
	}

	handleAnnotateImage(event) {
		const selectedIndex = parseInt(event.detail, 10);
		debug(`Annotating image #${selectedIndex}`);

		for (const item of this.allImagesData) {
			if (item.id === selectedIndex) {
				this.selectedImageInfo = item;
				break;
			}
		}
	}

	handleSaveAnnotatedImage(event) {
		debug('Saving annotated image!');
		const savedData = event.detail;
		this.selectedImageInfo.data = savedData.imageData;
		this.selectedImageInfo.editedImageInfo = savedData.editedImageInfo;
		this.selectedImageInfo.metadata.edited = true;
		this.selectedImageInfo = null;
	}

	handleImageDiscarded() {
		debug('Discarded annotated image!');
		this.selectedImageInfo = null;
	}

	handleCancelUpload() {
		debug('Cancelling upload...');
		this.allImagesData = [];
	}

	handleDeleteImage(event) {
		const idToDelete = event.detail;
		this.deleteImageById(idToDelete);
		this.selectedImageInfo = null;
	}

	deleteImageById(id) {
		debug(`Deleteing image #${id}`);

		let index = 0;
		for (const item of this.allImagesData) {
			if (item.id === id) {
				this.allImagesData.splice(index, 1);
				break;
			}
			index++;
		}
	}

	handleFileNameUpdate({ detail }) {
		this.allImagesData = this.allImagesData.map((item) => {
			const metadata = {
				...item.metadata,
				fileName: `${detail.batchNamePrefix}${item.metadata.fileName}${detail.batchNameSuffix}`
			};
			return {
				...item,
				metadata: metadata
			};
		});
	}

	handleUploadRequested() {
		const imagesData = this.allImagesData.map((item) => {
			return {
				...item,
				fileUploaded: false
			};
		});
		this.dispatchEvent(
			new CustomEvent('addimages', {
				detail: {
					value: imagesData
				},
				bubbles: true,
				composed: true
			})
		);

		this.existingImagesData = [
			...this.existingImagesData,
			...this.allImagesData
		];
		this.allImagesData = [];
	}
}