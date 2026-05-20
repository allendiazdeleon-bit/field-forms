import { LightningElement, api } from 'lwc';
import { generateUUID } from 'c/utilityService';
import { store } from 'c/neuraFormStore';
import { FIELDS } from 'c/neuraFormSchemaUtils';

export default class NeuraFormCriteriaBuilder extends LightningElement {
    allQuestions = [];
    allConfig = [];

    _conditionFieldValue;
    
    @api
    get conditionFieldValue() {
        return this._conditionFieldValue;
    }
    set conditionFieldValue(value) {
        this._conditionFieldValue = { ...value, typeOfLogic: value?.typeOfLogic ?? 'AND', customLogic: value?.customLogic ?? ''};
    }

    @api selection;

    variant = 'narrow';

    logicOptions = [
        { label: 'All Conditions Are Met', value: 'AND' },
        { label: 'Any Condition Is Met', value: 'OR' },
        { label: 'Custom Logic Is Met', value: 'Custom' }
    ];

    operatorOptions = [
        { label: 'Equals', value: 'equals' },
        { label: 'Does Not Equal', value: 'notEquals' },
        { label: 'Greater Than', value: 'greaterThan' },
        { label: 'Less Than', value: 'lessThan' },
        { label: 'Greater Than or Equal To', value: 'greaterThanOrEqual' },
        { label: 'Less Than or Equal To', value: 'lessThanOrEqual' },
        { label: 'Contains', value: 'contains' },
        { label: 'Starts With', value: 'startsWith' },
        { label: 'Ends With', value: 'endsWith' },
        { label: 'In List', value: 'inList' },
        { label: 'Not In List', value: 'notInList' },
        { label: 'Regex Match', value: 'regex' },
        { label: 'Is True', value: 'isTrue' },
        { label: 'Is False', value: 'isFalse' }
        // Additional operators can be added here
    ];

    get isNarrowVariant() {
        return this.variant === 'narrow';
    }

    get conditions() {
        return this._conditionFieldValue?.conditions ?? [];
    }

    get selectedLogic() {
        return this._conditionFieldValue?.typeOfLogic ?? 'AND';
    }

    get customLogic() {
        return this._conditionFieldValue?.customLogic ?? '';
    }

    get isCustomLogic() {
        return this.selectedLogic === 'Custom';
    }

    get questionOptions() {
        return this.allQuestions.map(q => ({
            label: q.attributes[FIELDS.Form_Question__c.Question.fieldApiName],
            value: q.id
        }));
    }

     /**
     * Handle changes in the custom logic input
     * @param {Event} event - The input event
     */
     handleCustomLogicChange(event) {
        this.updateConditionField('customLogic', event.target.value);
    }

    /**
     * Handle changes in the logical operator
     * @param {Event} event - The input event
     */
    handleLogicChange(event) {
        const newLogicType = event.target.value;
        let currentLogic = this.selectedLogic;
        if(newLogicType != 'Custom'){
            currentLogic = this.conditions.map(c => c.key).join(` ${newLogicType} `);
        }

        this.updateConditionFields({
            typeOfLogic: newLogicType,
            customLogic: currentLogic
        });
    }

    /**
     * Add a new condition to the conditions array
     */
    addCondition() {
        const lastCondition = this.conditions[this.conditions.length - 1];
        if (lastCondition && !lastCondition.resource) {
            return;
        }

        const newCondition = {
            id: generateUUID(), // UUID for the condition
            key: this.conditions.length + 1, // Position in the array + 1
            operator: 'equals',
            resource: '',
            value: ''
        };

        const newConditions = [...this.conditions, newCondition];
        const recalculatedConditions = this.recalculateConditionKeys(newConditions);
        const updatedLogic = this.recalculateCustomLogic(recalculatedConditions);

        this.updateConditionFields({
            conditions: recalculatedConditions,
            customLogic: updatedLogic
        });
    }

    /**
     * Handle removing a condition
     * @param {Event} event - The remove event
     */
    handleRemoveCondition(event) {
        try {
            const index = parseInt(event.detail.index, 10);
            if (this.isValidIndex(index, this.conditions.length)) {

                const updatedConditions = this.conditions.filter((_, i) => i !== index);
                const recalculatedConditions = this.recalculateConditionKeys(updatedConditions);
                const updatedLogic = this.recalculateCustomLogic(recalculatedConditions);

                this.updateConditionFields({
                    conditions: recalculatedConditions,
                    customLogic: updatedLogic
                });
            } else {
                console.error('Invalid index:', index);
            }
        } catch (error) {
            this.handleError(error, 'handleRemoveCondition');
        }
    }

    /**
     * Recalculate the 'key' field for each condition based on its position in the array
     * @param {Array} conditions - The array of conditions
     * @returns {Array} - The updated conditions with recalculated keys
     */
    recalculateConditionKeys(conditions) {
        try {
            return conditions.map((condition, index) => ({
                ...condition,
                key: index + 1
            }));
        } catch (error) {
            this.handleError(error, 'recalculateConditionKeys');
        }
    }
    
    /**
     * recalculates the custom logic string
     * @param {Array} conditions - The array of conditions
     * @returns {string} - The new logical string if typeOfLogic is AND or OR, or the current customLogic if Custom
     */
    recalculateCustomLogic(conditions) {
        // Recalculate customLogic if typeOfLogic is AND or OR by going Key by Key and building out the logical string.
        if (this.selectedLogic !== 'Custom') {
            return conditions.map(c => c.key).join(` ${this.selectedLogic} `);
        } else {
            return this.customLogic;
        }
    }

    /**
     * Handle page change
     * @param {Event} event - The input event
     */
    handlePageChange(event) {
        this.updateConditionProperty(event.detail.index, 'page', event.detail.value);
    }

    /**
     * Handle section change
     * @param {Event} event - The input event
     */
    handleSectionChange(event) {
        this.updateConditionProperty(event.detail.index, 'section', event.detail.value);
    }

    /**
     * Handle resource change
     * @param {Event} event - The input event
     */
    handleResourceChange(event) {
        this.updateConditionProperty(event.detail.index, 'resource', event.detail.value);
    }

    /**
     * Handle operator change
     * @param {Event} event - The input event
     */
    handleOperatorChange(event) {
        this.updateConditionProperty(event.detail.index, 'operator', event.detail.value);
    }

    /**
     * Handle value change
     * @param {Event} event - The input event
     */
    handleValueChange(event) {
        this.updateConditionProperty(event.detail.index, 'value', event.detail.value);
    }

    /**
     * Handle errors from events
     * @param {*} error - The event that caused the error
     */

    handleError(error, methodName){
        console.error('Error: ', error, ' methodName: ', methodName);
    }


    /**
     * Handle updates from the store
     * @param {object} state - The current state from the store
     */
    handleStoreUpdate(state) {
        this.allQuestions = state.allQuestions;
        this.allConfig = state.allConfig;
    }

    /**
     * Handle changes to individual conditions
     * @param {Event} event - The condition change event
     */
    handleConditionChange(event) {
        try{
            const index = event.detail.index;
            const condition = event.detail.condition;
            if (this.isValidIndex(index, this.conditions.length)) {
                const updatedConditions = this.conditions.map((c, i) => (i === index ? condition : c));
                const recalculatedConditions = this.recalculateConditionKeys(updatedConditions);
                const updatedLogic = this.recalculateCustomLogic(recalculatedConditions);
                this.updateConditionFields({
                    conditions: recalculatedConditions,
                    customLogic: updatedLogic
                });
            } else {
                console.error('Invalid index:', index);
            }
        } catch (error) {
            this.handleError(error, 'handleConditionChange');
        }
    }

    /**
     * Update a specific field in the conditionFieldValue object
     * @param {string} field - The field to update
     * @param {any} value - The new value
     */
    updateConditionField(field, value) {
        this._conditionFieldValue = { ...this._conditionFieldValue, [field]: value };
        this.dispatchUpdateEvent();
    }

    /**
     * Update a specific fields in the conditionFieldValue object
     * @param {string} field - The field to update
     * @param {any} value - The new value
     */
    updateConditionFields(updates) {
        this._conditionFieldValue = { ...this._conditionFieldValue, ...updates };
        this.dispatchUpdateEvent();
    }

    /**
     * Update a property of a specific condition
     * @param {number} index - The index of the condition to update
     * @param {string} property - The property to update
     * @param {any} value - The new value
     */
    updateConditionProperty(index, property, value) {
        try {
            if (this.isValidIndex(index, this.conditions.length)) {
                const updatedConditions = [...this.conditions];
                updatedConditions[index] = { ...updatedConditions[index], [property]: value };
                // Re-key the conditions, then rebuild the customLogic STRING from
                // those keys. The previous version assigned the array of conditions
                // to customLogic, silently corrupting the expression.
                const recalculatedConditions = this.recalculateConditionKeys(updatedConditions);
                const updatedLogic = this.recalculateCustomLogic(recalculatedConditions);
                this.updateConditionFields({
                    conditions: recalculatedConditions,
                    customLogic: updatedLogic
                });
            } else {
                console.error('Invalid index:', index);
            }
        } catch (error) {
            this.handleError(error, 'updateConditionProperty');
        }
    }

    /**
     * Check if an index is valid for a given array length
     * @param {number} index - The index to check
     * @param {number} length - The length of the array
     * @returns {boolean} - Whether the index is valid
     */
    isValidIndex(index, length) {
        return !isNaN(index) && index >= 0 && index < length;
    }

    /**
     * Dispatch an update event to notify parent components
     */
    dispatchUpdateEvent() {
        console.log('Dispatching update event');
        console.log(this._conditionFieldValue);
        this.dispatchEvent(new CustomEvent('update', { detail: { value: JSON.stringify(this._conditionFieldValue) } }));
    }

    /**
     * Lifecycle hook to handle component initialization
     */
    connectedCallback() {
        this.unsubscribe = store.subscribe(this.handleStoreUpdate.bind(this));
        const state = store.getState();
        this.allQuestions = state.allQuestions;
        this.allConfig = state.allConfig;
    }

    /**
     * Lifecycle hook to handle component cleanup
     */
    disconnectedCallback() {
        if (this.unsubscribe) {
            this.unsubscribe();
        }
    }
}