import { 
    createRecord, 
    updateRecord, 
    deleteRecord, 
    createContentDocumentAndVersion 
} from 'lightning/uiRecordApi';
import { IMAGE_EXT, isNullOrEmpty, dataURLtoFile } from 'c/utilsImageCapture';

import deleteFormAnswers from '@salesforce/apex/NeuraFormLogic.deleteFormAnswers';
import saveFormAnswers from '@salesforce/apex/NeuraFormLogic.saveFormAnswers';
import uploadFilesForAnswerRecords from '@salesforce/apex/NeuraFormLogic.uploadFilesForAnswerRecords';

import { FIELDS, OBJECTS } from 'c/neuraFormSchemaUtils';

async function deleteAnswers(answersToDelete, formFactorPropertyName) {
    try {
        if(formFactorPropertyName === 'Large') {
            await deleteFormAnswers({answersToDelete: answersToDelete});
        } else {
            answersToDelete.forEach(async (item) => {
                await deleteRecord(item.Id);
            });
        }
    } catch(error) {
        throw error;
    }
}

async function saveAnswers(questionAnswerMap, linkedFormId, formFactorPropertyName) {
    let formAnswers = [];

    try {
        for(let [key, value] of questionAnswerMap) {
            if(!value.uploadCompleted) {
                const fields = getFormAnswerFromQuestionAnswerMapValue(value, linkedFormId);

                if(formFactorPropertyName === 'Large') {
                    if(value.Id) {
                        fields.Id = value.Id;
                    }
                    formAnswers.push(fields);
                } else {
                    await saveAnswersForOtherDevices(fields, value, questionAnswerMap);
                }
            }   
        }

        if(formAnswers.length) {
            await saveAnswersForDesktop(formAnswers, questionAnswerMap);
        }
    } catch(error) {
        throw error;
    }
}

async function saveAnswersForDesktop(formAnswers, questionAnswerMap) {
    const result = await saveFormAnswers({answersToSave: formAnswers});

    if(result && result.length) {
        const formAnswerFields = FIELDS.Form_Answer__c;

        await uploadFilesForDesktop(result, questionAnswerMap);

        result.forEach((item) => {
            const answerAvailable = questionAnswerMap.get(item[formAnswerFields.FormQuestion.fieldApiName]);
            if(answerAvailable) {
                answerAvailable.Id = item.Id;
            }

            answerAvailable.uploadCompleted = true;
            questionAnswerMap.set(answerAvailable[formAnswerFields.FormQuestion.fieldApiName], answerAvailable);
        });
    } 
}

async function saveAnswersForOtherDevices(fields, value, questionAnswerMap) {
    const formAnswerObject = OBJECTS.Form_Answer__c;
    const formAnswerFields = FIELDS.Form_Answer__c;

    if(!value.Id) {
        const createAnswerInput = { apiName: formAnswerObject.objectApiName, fields };

        const result = await createRecord(createAnswerInput);
        
        value.Id = result.id;
    } else {
        fields.Id = value.Id;

        const updateAnswerInput = { fields };

        await updateRecord(updateAnswerInput);
    }

    if(value.filesData && value.filesData.length) {
        await uploadFilesForOtherDevices(value.Id, value.filesData);
    }

    value.uploadCompleted = true;
    questionAnswerMap.set(value[formAnswerFields.FormQuestion.fieldApiName], value);
}

function getFormAnswerFromQuestionAnswerMapValue(value, linkedFormId) {
    const formAnswerFields = FIELDS.Form_Answer__c;

    const fields = {};
    assignFieldValues(fields, formAnswerFields.Answer.fieldApiName, value[formAnswerFields.Answer.fieldApiName]);
    assignFieldValues(fields, formAnswerFields.RelatedComment.fieldApiName, value[formAnswerFields.RelatedComment.fieldApiName]);
    assignFieldValues(fields, formAnswerFields.Type.fieldApiName, value[formAnswerFields.Type.fieldApiName]);
    assignFieldValues(fields, formAnswerFields.FormQuestion.fieldApiName, value[formAnswerFields.FormQuestion.fieldApiName]);
    assignFieldValues(fields, formAnswerFields.LinkedForm.fieldApiName, linkedFormId);

    return fields;
}

function assignFieldValues(targetObj, fieldApiName, value){
    if (value !== undefined) {
        targetObj[fieldApiName] = value;
    }
}

async function uploadFilesForDesktop(savedAnswers, questionAnswerMap) {
    const formAnswerFields = FIELDS.Form_Answer__c;

    const linkedEntityToFilesDataRequests = [];
    let linkedEntityToFilesData = [];
    let totalFileSize = 0;

    savedAnswers.forEach((item) => {
        const answerAvailable = questionAnswerMap.get(item[formAnswerFields.FormQuestion.fieldApiName]);

        if(answerAvailable && answerAvailable.filesData && answerAvailable.filesData.length) {
            let filesData = [];

            answerAvailable.filesData.forEach(async (file) => {
                const fileData = {
                    data: file.data,
                    fileName: getFullFileName(file),
                    description: file.editedImageInfo.description || file.description
                };

                totalFileSize += file.expectedSize / 1000;

                if(totalFileSize < 2000) {
                    filesData.push(fileData);   
                } else {
                    if(filesData.length) {
                        linkedEntityToFilesData.push({
                            linkedEntityId: item.Id,
                            filesData: [...filesData]
                        });
                    }

                    linkedEntityToFilesDataRequests.push(linkedEntityToFilesData);
                    
                    linkedEntityToFilesData = [];
                    filesData = [];

                    totalFileSize = file.expectedSize / 1000;
                    filesData.push(fileData); 
                }
            });

            linkedEntityToFilesData.push({
                linkedEntityId: item.Id,
                filesData: [...filesData]
            });
        }
    });

    if(linkedEntityToFilesData.length) {
        linkedEntityToFilesDataRequests.push(linkedEntityToFilesData);
    }

    for(let request of linkedEntityToFilesDataRequests) {
        await uploadFilesForAnswerRecords({linkedEntityToFilesData: request})
    }
}

async function uploadFilesForOtherDevices(recordId, allImagesData) {
    // Make a copy of allImagesData to loop over it, because we modify allImagesData
    let allImagesToUpload = allImagesData.filter((item) => {
        return !item.fileUploaded;
    });

    allImagesToUpload.forEach(async (item) => {
        let fullFileName = getFullFileName(item);
        
        const description = item.editedImageInfo.description || item.description;

        await uploadData(
            fullFileName,
            description,
            item.data,
            recordId
        );

        item.fileUploaded = true;
    });
}

function getFullFileName(item) {
    const ext = item.metadata.edited ? IMAGE_EXT : item.metadata.ext;
    let fullFileName = item.editedImageInfo.fileName || item.metadata.fileName;
    
    if (!isNullOrEmpty(ext)) {
        fullFileName = `${fullFileName}.${ext}`;
    }

    // Replace whitespaces with underscores
    fullFileName = fullFileName.replaceAll(" ", "_");

    return fullFileName;
}

// Use LDS createContentDocumentAndVersion function to upload file to a ContentVersion object.
// This method creates drafts for ContentDocument and ContentVersion objects.
async function uploadData(fileName, description, fileData, recordId) {
    let fileObject = dataURLtoFile(fileData, fileName);
    const contentDocumentAndVersion =
        await createContentDocumentAndVersion({
            title: fileName,
            description: description,
            fileData: fileObject
        });

    const contentDocumentId = contentDocumentAndVersion.contentDocument.id;

    await createCdl(recordId, contentDocumentId);
}

async function createCdl(recordId, contentDocumentId) {
    await createRecord({
        apiName: "ContentDocumentLink",
        fields: {
            LinkedEntityId: recordId,
            ContentDocumentId: contentDocumentId,
            ShareType: "V"
        }
    });
}

export { deleteAnswers, saveAnswers };