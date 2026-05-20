function reduceError(error) {
    let errorMessage = '';

    if(Array.isArray(error)) {
        //error will be in Array from error on graphQL wire adapter
        error.forEach(item => {
            if(item.error && item.error.length) {
                item.error.forEach((err) => {
                    errorMessage += `${err.message}. `;
                });
            }

            if (item.body && item.body.message && item.body.message.length) {
				item.body.message.forEach(err => {
					errorMessage += `${err.message}. `;
				});
			}
        });
    } 

    if(error.message) {
        errorMessage += `${error.message}. `;
    }
    
    if(error.body) {
        //body.message will come from client side issues
        if(error.body.message) {
            errorMessage += `${error.body.message}. `;
        } 

        //body.fieldErrors will come from all types for field errors when call Apex
        if(error.body.fieldErrors) {
            const fieldErrors = error.body.fieldErrors;
            for (const property in fieldErrors) {
                if(Array.isArray(fieldErrors[property])) {
                    fieldErrors[property].forEach((item) => {
                        errorMessage +=  `[${property}] ${item.message}. `;
                    });
                }
            }
        }

        //body.pageErrors will come from all types for page errors when call Apex
        if(error.body.pageErrors) {
            const pageErrors = error.body.pageErrors;
            if(Array.isArray(pageErrors)) {
                pageErrors.forEach((item) => {
                    errorMessage += `${item.message}. `;
                });
            }
        }

        //body.output will come from all types for page errors when call ui record api
        if(error.body.output) {
            errorMessage += getOutputErrors(error.body.output);
        }
    }

    //error.output will come from all types for page errors when using hanele error from lightning record form
    if(error.output) {
        errorMessage += getOutputErrors(error.output);
    }

    errorMessage = errorMessage.replaceAll('..', '.');

    return errorMessage.trim();
}

function getOutputErrors(outputErrors) {
    let errorMessage = '';

    if(outputErrors.fieldErrors) {
        const fieldErrors = outputErrors.fieldErrors;
        for (const property in fieldErrors) {
            if(fieldErrors[property][0]) {
                const propertyObj = fieldErrors[property][0];
                if(propertyObj.hasOwnProperty('message')) {
                    errorMessage += `[${propertyObj.field}] ${propertyObj.message}. `;
                }
            }
        }
    }

    if(outputErrors.pageErrors) {
        const pageErrors = outputErrors.pageErrors;
        if(Array.isArray(pageErrors)) {
            pageErrors.forEach((item) => {
                errorMessage += `${item.message}. `;
            });
        }
    }

    if(outputErrors.errors) {
        const errors = outputErrors.errors;
        errors.forEach((item) => {
            errorMessage += item.message + '. ';
            if(item.duplicateRecordError && item.duplicateRecordError.matchResults && Array.isArray(item.duplicateRecordError.matchResults)) {
                errorMessage += 'Matching Record Ids : ';
                item.duplicateRecordError.matchResults.forEach((result) => {
                    result.matchRecordIds.forEach((id) => {
                        errorMessage += `${id} `;
                    });
                });
            }
        });
    }

    return errorMessage;
}

export { reduceError }