import { LightningElement, api, track } from 'lwc';
import { generateUUID } from 'c/utilityService';

export default class NeuraFormBuilderAttributesValueSet extends LightningElement {
    @api fieldName; // the name of the field to be updated

    // Advanced mode exposes the stored value separately from the label.
    // Important because answers and visibility conditions reference the
    // VALUE: in simple mode a label edit only re-keys the value while the
    // two are still in sync (a fresh option); once a value has been
    // deliberately set apart, label edits leave it alone.
    @track showValues = false;
    @track showBulkAdd = false;
    @track bulkText = '';

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

    // Per-row view model: disable the up arrow on the first row, down on
    // the last (LWC templates can't compute that inline).
    get rows() {
        const last = (this._valueSet || []).length - 1;
        return (this._valueSet || []).map((item, index) => ({
            ...item,
            index,
            isFirst: index === 0,
            isLast: index === last
        }));
    }

    get valuesToggleLabel() {
        return this.showValues ? 'Hide stored values' : 'Edit stored values';
    }

    handleInputChange(event) {
        try {
            const index = event.currentTarget.dataset.index;
            const value = event.currentTarget.value;
            let updatedValueSet = JSON.parse(JSON.stringify(this._valueSet));
            const wasInSync = updatedValueSet[index].value === updatedValueSet[index].label;
            updatedValueSet[index].label = value;
            // Only re-key the stored value while label and value are still
            // twins. Once they diverge (admin set an explicit value), a label
            // edit must NOT silently re-key it — saved answers and visibility
            // conditions reference the value.
            if (wasInSync) {
                updatedValueSet[index].value = value;
            }
            this.sendUpdateEvent(updatedValueSet);
        } catch (error) {
            console.error(error);
        }
    }

    handleValueChange(event) {
        try {
            const index = event.currentTarget.dataset.index;
            const value = event.currentTarget.value;
            let updatedValueSet = JSON.parse(JSON.stringify(this._valueSet));
            updatedValueSet[index].value = value;
            this.sendUpdateEvent(updatedValueSet);
        } catch (error) {
            console.error(error);
        }
    }

    handleIconChange(event) {
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

        updatedValueSet.push({ id: generateUUID(), label: optionLabel, value: optionLabel, icon: '' });
        this.sendUpdateEvent(updatedValueSet);
    }

    moveItem(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        const delta = parseInt(event.currentTarget.dataset.delta, 10);
        const target = index + delta;
        let updatedValueSet = JSON.parse(JSON.stringify(this._valueSet));
        if (target < 0 || target >= updatedValueSet.length) return;
        const [moved] = updatedValueSet.splice(index, 1);
        updatedValueSet.splice(target, 0, moved);
        this.sendUpdateEvent(updatedValueSet);
    }

    toggleValues() {
        this.showValues = !this.showValues;
    }

    toggleBulkAdd() {
        this.showBulkAdd = !this.showBulkAdd;
        this.bulkText = '';
    }

    handleBulkTextChange(event) {
        this.bulkText = event.target.value;
    }

    /**
     * Bulk add: one option per line. "Label | value" sets an explicit
     * stored value; a bare line uses the text for both. Blank lines and
     * duplicate values (already present) are skipped. Turns the
     * ten-click chore of building a long dropdown into one paste.
     */
    applyBulkAdd() {
        const lines = (this.bulkText || '').split('\n');
        let updatedValueSet = JSON.parse(JSON.stringify(this._valueSet));
        const existingValues = new Set(updatedValueSet.map((o) => o.value));
        let added = 0;
        for (const line of lines) {
            const trimmed = line.trim();
            if (!trimmed) continue;
            const parts = trimmed.split('|').map((p) => p.trim());
            const label = parts[0];
            const value = parts.length > 1 && parts[1] ? parts[1] : label;
            if (existingValues.has(value)) continue;
            existingValues.add(value);
            updatedValueSet.push({ id: generateUUID(), label, value, icon: '' });
            added++;
        }
        if (added > 0) {
            this.sendUpdateEvent(updatedValueSet);
        }
        this.showBulkAdd = false;
        this.bulkText = '';
    }

    sendUpdateEvent(updatedValueSet) {
        // send an event with the full new value set
        this.dispatchEvent(new CustomEvent('update', { detail: { fieldName: this.fieldName, value: JSON.stringify(updatedValueSet) } }));
    }

    deleteItem(event) {
        const index = event.target.dataset.index;
        let updatedValueSet = JSON.parse(JSON.stringify(this._valueSet));
        updatedValueSet.splice(index, 1);
        this.sendUpdateEvent(updatedValueSet);
    }
}
