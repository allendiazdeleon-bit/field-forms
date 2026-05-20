import { api, LightningElement, track } from 'lwc';

export default class NeuraFormAnswerInputMultiSelect extends LightningElement {
  @api disabled = false;
  @api label = '';
  @api name;
  @api options = [];
  @api placeholder = 'Select an Option';
  @api readOnly = false;
  @api required = false;
  @api singleSelect = false;
  @api showPills = false;

  @api selectedValues = '';

  @track currentOptions = [];
  selectedItems = [];
  selectedOptions = [];
  isInitialized = false;
  isLoaded = false;
  isVisible = false;
  isDisabled = false;
  renderList = false;

  connectedCallback() {
    this.isDisabled = this.disabled || this.readOnly;
    this.hasPillsEnabled = this.showPills && !this.singleSelect;

    this.initializeSelectedValues();
  }

  initializeSelectedValues() {
    const selectedValuesArray = this.selectedValues.split(';').map(item => item.trim());
    this.currentOptions = JSON.parse(JSON.stringify(this.options));
    this.currentOptions.forEach((option) => {
      if (selectedValuesArray.includes(option.value)) {
        option.selected = true;
      } else {
        option.selected = false;
      }
    });
    this.setSelection();
    console.log('currentOptions after Init: ' + JSON.stringify(this.currentOptions));
    this.renderList = true;
  }



  renderedCallback() {
    if (!this.isInitialized) {
      this.template.querySelector('.multi-select-combobox__input').addEventListener('click', (event) => {
        this.handleClick(event.target);
        event.stopPropagation();
      });
      this.template.addEventListener('click', (event) => {
        event.stopPropagation();
      });
      document.addEventListener('click', () => {
        this.close();
      });
      this.isInitialized = true;
      this.setSelection();
    }
  }
  handleChange(event) {
    this.change(event);
  }
  handleRemove(event) {
    this.selectedOptions.splice(event.detail.index, 1);
    this.change(event);
  }
  handleClick() {
    // initialize picklist options on first click to make them editable
    /*
    if (this.isLoaded === false || (this.currentOptions?.length !== this.options?.length)) {
      this.currentOptions = JSON.parse(JSON.stringify(this.options));
      this.isLoaded = true;
    }
    */
    if (this.template.querySelector('.slds-is-open')) {
      this.close();
    } else {
      this.template.querySelectorAll('.multi-select-combobox__dropdown').forEach((node) => {
        node.classList.add('slds-is-open');
      });
    }
  }
  change(event) {
    // debug the current options
    console.log('currentOptions: ' + JSON.stringify(this.currentOptions));

    // debug the selected options
    console.log('selectedOptions: ' + JSON.stringify(this.selectedOptions));

    const selectedValue = event.detail.item.value;
    const selected = event.detail.selected;

    if (this.singleSelect) {
      this.currentOptions.forEach((item) => (item.selected = false));
    }

    // Find the selected option and update its selected status
    this.currentOptions.forEach((item) => {
      if (item.value === selectedValue) {
        item.selected = selected;
      } else if (this.singleSelect) {
        item.selected = false;
      }
    });

    this.setSelection();


    // debug the current options
    console.log('currentOptions after: ' + JSON.stringify(this.currentOptions));

    // debug the selected options
    console.log('selectedOptions after: ' + JSON.stringify(this.selectedOptions));
    //const selection = this.getSelectedItems();
    const selectedValues = this.getSelectedItems().map(item => item.value).join(';');
    this.dispatchEvent(new CustomEvent('change', { detail: { value: selectedValues } }));
    //    this.dispatchEvent(new CustomEvent('change', { detail: this.singleSelect ? selection[0] : selection }));
    // for single select picklist close dropdown after selection is made
    if (this.singleSelect) {
      this.close();
    }
  }
  close() {
    this.template.querySelectorAll('.multi-select-combobox__dropdown').forEach((node) => {
      node.classList.remove('slds-is-open');
    });
    this.dispatchEvent(new CustomEvent('close'));
  }
  setSelection() {
    const selectedItems = this.getSelectedItems();
    let selection = '';
    if (selectedItems.length < 1) {
      selection = this.placeholder;
      this.selectedOptions = [];
    } else if (selectedItems.length > 2) {
      selection = `${selectedItems.length} Options Selected`;
      this.selectedOptions = this.getSelectedItems();
    } else {
      selection = selectedItems.map((selected) => selected.label).join(', ');
      this.selectedOptions = this.getSelectedItems();
    }
    this.selectedItems = selection;
    this.isVisible = this.selectedOptions && this.selectedOptions.length > 0;
  }

  getSelectedItems() {
    return this.currentOptions.filter((item) => item.selected);
  }
}