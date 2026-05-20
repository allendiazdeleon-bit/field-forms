export const LOADING_TOKENS = {
    DATA_LOAD: 'dataload',
    FOOTER_CLICK_LOAD: 'footerClickLoad',
    GEOLOCATION_LOAD: 'geolocationLoad',
    REFRESH_LOAD: 'refreshLoad'
};

export const MESSAGE_VARIANT = {
    ERROR: 'error',
    INFO: 'info',
    WARN: 'warning'
}

// GraphQL pagination cap for Form_Answers__r per Linked_Form.
// If a completed form has more answers than this, the user is warned
// that older answers were truncated rather than failing silently.
export const FORM_ANSWER_FETCH_LIMIT = 500;