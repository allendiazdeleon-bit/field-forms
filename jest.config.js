const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    moduleNameMapper: {
        ...jestConfig.moduleNameMapper,
        '^c/(.+)$': '<rootDir>/field-forms/lwc/$1/$1'
    },
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver'],
    collectCoverageFrom: [
        'field-forms/lwc/**/*.js',
        '!field-forms/lwc/**/__tests__/**',
        '!field-forms/lwc/luxon/**',
        '!field-forms/lwc/avonni*/**',
        '!field-forms/lwc/configProvider/**',
        '!field-forms/lwc/positionLibrary/**',
        '!field-forms/lwc/tooltipLibrary/**',
        '!field-forms/lwc/utilsPrivate/**'
    ]
};
