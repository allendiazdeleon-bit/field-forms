function getFormattedGraphQLData(data) {
    let formattedData = {};
    const queryData = data.uiapi.query;
    for (let item in queryData) {
        formattedData[item] = processEdges(queryData[item].edges);
    }
    return formattedData;
}

function processEdges(edges) {
    let properties = [];
    edges.forEach(item => {
        const node = item.node;
        properties.push(processFieldValues(node));
    });
    return properties;
}

function processFieldValues(node) {
    let property = {};
    for (let field in node) {
        //field with _drafts is coming only on mobile
        //Don't know the reason of it, that's the method was not getting implemented
        if(field !== '_drafts') {
            const obj = node[field];
            let value;
            if(obj) {
                if (field === 'Id') {
                    value = obj;
                } else if (obj.hasOwnProperty('value')) {
                    value = obj.value;
                } else if (obj.hasOwnProperty('edges')) {
                    value = processEdges(obj.edges);
                } else {
                    value = processFieldValues(obj);
                }
            } else {
                value = null;
            }
            property[field] = value;
        }
    }

    return property;
}

async function uploadAllPhotos(recordId, allImagesData, formFactorPropertyName) {
    if(formFactorPropertyName === 'Large') {
        await uploadFilesForDesktop(recordId, allImagesData);
    } else {
        await uploadFilesForOtherDevices(recordId, allImagesData);
    }
}

async function uploadFilesForDesktop(recordId, allImagesData) {
    const filesData = allImagesData.map((item) => {
        return {
            data: item.data,
            fileName: getFullFileName(item),
            description: item.editedImageInfo.description || item.description
        };
    });

    const request = {
        linkedEntityId: recordId,
        filesData: filesData
    };
    await uploadFilesForAnswerRecord(request);
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
        await unstable_createContentDocumentAndVersion({
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

function reduceError(error) {
    let errorMessage = '';

    if(error.body.message) {
        errorMessage += error.body.message + '. ';
    } 
    if(error.body.output) {
        const fieldErrors = error.body.output.fieldErrors;
        for (const property in fieldErrors) {
            if(fieldErrors[property][0]) {
                const propertyObj = fieldErrors[property][0];
                if(propertyObj.hasOwnProperty('message')) {
                    errorMessage += propertyObj.message + '. ';
                }
            }
        }
        const errors = error.body.output.errors;
        errors.forEach((item) => {
            errorMessage += item.message + ' ';
        });
    }

    return errorMessage;
}

function isChangeInDataForGraphQLResult(graphQlResultResult, holdingGraphQlResult) {
    if(graphQlResultResult && graphQlResultResult.data && holdingGraphQlResult && holdingGraphQlResult.data) {
        const currentFormattedGraphQlData = getFormattedGraphQLData(graphQlResultResult.data);
        const holdingFormattedGraphQlData = getFormattedGraphQLData(holdingGraphQlResult.data);

        return haveObjectsChanged(currentFormattedGraphQlData, holdingFormattedGraphQlData);
    }

    return false;
}

function areEqual(value1, value2) {
    if (value1 === value2) {
        return true;
    }

    if (typeof value1 !== typeof value2) {
        return false;
    }

    if (Array.isArray(value1) && Array.isArray(value2)) {
        if (value1.length !== value2.length) {
            return false;
        }
        for (let i = 0; i < value1.length; i++) {
            if (!areEqual(value1[i], value2[i])) {
                return false;
            }
        }
        return true;
    }

    if (typeof value1 === 'object' && value1 !== null && typeof value2 === 'object' && value2 !== null) {
        return haveObjectsChanged(value1, value2) === false;
    }

    return false;
}

function haveObjectsChanged(obj1, obj2) {
    for (const key in obj1) {
        if (obj1.hasOwnProperty(key)) {
            if (!obj2.hasOwnProperty(key) || !areEqual(obj1[key], obj2[key])) {
                return true;
            }
        }
    }

    for (const key in obj2) {
        if (obj2.hasOwnProperty(key) && !obj1.hasOwnProperty(key)) {
            return true;
        }
    }

    return false;
}

export { getFormattedGraphQLData, isChangeInDataForGraphQLResult }