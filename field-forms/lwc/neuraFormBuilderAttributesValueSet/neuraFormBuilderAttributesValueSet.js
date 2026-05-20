import { LightningElement, api } from 'lwc';
import { generateUUID } from 'c/utilityService';
export default class NeuraFormBuilderAttributesValueSet extends LightningElement {
    @api fieldName; // the name of the field to be updated

    _valueSet;
    @api
    get valueSet() {
        return this._valueSet;
    }

    set valueSet(value) {
        // Build a fresh default each time so two components editing different
        // questions don't share the same option object.
        if (!value) {
            this._valueSet = [{
                id: generateUUID(),
                label: 'Option 1',
                value: 'Option 1',
                icon: ''
            }];
            return;
        }
        try {
            this._valueSet = JSON.parse(value);
        } catch (e) {
            // Corrupt value field - fall back to a single default rather than
            // crashing the builder; the user will see Option 1 and can rebuild.
            console.error('Invalid value-set JSON; resetting to default.', e);
            this._valueSet = [{
                id: generateUUID(),
                label: 'Option 1',
                value: 'Option 1',
                icon: ''
            }];
        }
    }

    handleInputChange(event) {
        console.log('Input Change: ' + JSON.stringify(event.currentTarget.value));
        try {
            const index = event.currentTarget.dataset.index;
            const value = event.currentTarget.value;
            let updatedValueSet = JSON.parse(JSON.stringify(this._valueSet));
            updatedValueSet[index].label = value;
            updatedValueSet[index].value = value;
            this.sendUpdateEvent(updatedValueSet);
        } catch (error) {
                console.error(error);
        }
        
    }

    handleIconChange(event) {
        console.log('Icon Event: ' + JSON.stringify(event.detail.value));
        const index = event.currentTarget.dataset.index;
        const value = event.detail.value;
        let updatedValueSet = JSON.parse(JSON.stringify(this._valueSet));
        updatedValueSet[index].icon = value;

        // send an event with the full new value set
       this.sendUpdateEvent(updatedValueSet);
    }

    addItem() {
        let updatedValueSet = JSON.parse(JSON.stringify(this._valueSet));
        let incrementNumber = updatedValueSet.length + 1;
        let optionLabel = 'Option ' + incrementNumber;
        
        updatedValueSet.push({ id: generateUUID(), label: optionLabel , value: optionLabel, icon: '' });
        this.sendUpdateEvent(updatedValueSet);
    }

    sendUpdateEvent(updatedValueSet) {
        // send an event with the full new value set
        this.dispatchEvent(new CustomEvent('update', { detail: { fieldName: this.fieldName, value : JSON.stringify(updatedValueSet) } }));
    }

    deleteItem(event) {
        const index = event.target.dataset.index;
        let updatedValueSet = JSON.parse(JSON.stringify(this._valueSet));
        updatedValueSet.splice(index, 1);
        this.sendUpdateEvent(updatedValueSet);
    }

}