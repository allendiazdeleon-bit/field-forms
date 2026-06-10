const getFieldValue = (field, defaultValue = '') => {
    return field && field.value ? field.value : defaultValue;
};

const getValue = (object, fieldName, defaultValue) => {
    return object && object[fieldName] ? object[fieldName] : defaultValue;
}

/**
 * Count the authored rules in a Conditions__c JSON blob (the
 * conditional-visibility config on questions / sections / pages).
 * Returns 0 for blank/malformed JSON and for placeholder rows that
 * never picked a referenced question. Used by the builder canvas to
 * badge conditional elements — before this, authored visibility rules
 * were completely invisible until you clicked into the element.
 */
const countConditionRules = (rawJson) => {
    if (!rawJson) return 0;
    try {
        const parsed = typeof rawJson === 'string' ? JSON.parse(rawJson) : rawJson;
        if (!Array.isArray(parsed?.conditions)) return 0;
        return parsed.conditions.filter((c) => c && c.resource).length;
    } catch (e) {
        return 0;
    }
};

export { getFieldValue, getValue, countConditionRules };