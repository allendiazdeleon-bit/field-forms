const OPERATOR_MAP = new Map([
    ['equals', '==='],
    ['notEquals', '!=='],
    ['greaterThan', '<'],
    ['lessThan', '>'],
    ['greaterThanOrEqual', '<='],
    ['lessThanOrEqual', '>='],
    ['contains', 'includes'],
    ['inList', 'includes'],
    ['notInList', 'includes'],
    ['startsWith', 'startsWith'],
    ['endsWith', 'endsWith'],
    ['regex', 'match']
]);

const STRING_LIST_OPERATORS = [
    'contains',
    'inList',
    'notInList',
    'startsWith',
    'endsWith',
    'regex'
];

const NEGATION_STRING_LIST_OPERATORS = [
    'notInList'
];

const ELEMENT_TYPE = {
    PAGE: 'page',
    SECTION: 'section',
    QUESTION: 'question'
};

export { OPERATOR_MAP, STRING_LIST_OPERATORS, NEGATION_STRING_LIST_OPERATORS, ELEMENT_TYPE };