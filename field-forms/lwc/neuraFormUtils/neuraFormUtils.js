const getFieldValue = (field, defaultValue = '') => {
    return field && field.value ? field.value : defaultValue;
};

const getValue = (object, fieldName, defaultValue) => {
    return object && object[fieldName] ? object[fieldName] : defaultValue;
}

export { getFieldValue, getValue };