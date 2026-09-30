import { LightningElement, api, track } from 'lwc';

export default class MultiSelectCombobox extends LightningElement {
    @api label;
    @api placeholder = 'Select Options';
    @api disabled = false;
    @api showPills = false; // If true, shows pills. If false, shows 'X options selected'

    @track _options = [];
    @track _selectedValues = [];
    @track isOpen = false;

    @api
    get options() {
        return this._options;
    }
    set options(val) {
        this._options = val || [];
    }

    @api
    get values() {
        return this._selectedValues;
    }
    set values(val) {
        this._selectedValues = val || [];
    }

    get optionsToDisplay() {
        return this._options.map(opt => {
            return {
                label: opt.label,
                value: opt.value,
                selected: this._selectedValues.includes(opt.value)
            };
        });
    }

    get hasSelection() {
        return this._selectedValues.length > 0;
    }

    get selectedOptions() {
        return this._options.filter(opt => this._selectedValues.includes(opt.value));
    }

    get displayText() {
        if (!this.hasSelection) {
            return '';
        }
        if (this._selectedValues.length === 1) {
            return this.selectedOptions[0].label;
        }
        return `${this._selectedValues.length} options selected`;
    }

    get dropdownClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click ${this.isOpen ? 'slds-is-open' : ''}`;
    }

    get inputContainerClass() {
        return `slds-combobox__input-container ${this.disabled ? 'slds-is-disabled' : ''}`;
    }

    toggleDropdown() {
        if (this.disabled) return;
        // Let the click reach the document so other open comboboxes close themselves
        this.isOpen = !this.isOpen;
    }

    closeDropdown() {
        this.isOpen = false;
    }

    handleSelect(event) {
        if (event) {
            event.stopPropagation();
        }
        const value = event.currentTarget.dataset.value;
        let selected = [...this._selectedValues];
        if (selected.includes(value)) {
            selected = selected.filter(v => v !== value);
        } else {
            selected.push(value);
        }
        this._selectedValues = selected;
        this.dispatchChangeEvent();
    }

    handleRemovePill(event) {
        if (event) {
            event.stopPropagation();
        }
        const value = event.target.name;
        this._selectedValues = this._selectedValues.filter(v => v !== value);
        this.dispatchChangeEvent();
    }

    dispatchChangeEvent() {
        const event = new CustomEvent('change', {
            detail: { values: this._selectedValues }
        });
        this.dispatchEvent(event);
    }

    // Close dropdown when clicking outside
    connectedCallback() {
        this._handler = (event) => {
            const path = event.path || (event.composedPath && event.composedPath());
            if (path && !path.includes(this.template.host)) {
                this.closeDropdown();
            }
        };
        document.addEventListener('click', this._handler);
    }

    disconnectedCallback() {
        document.removeEventListener('click', this._handler);
    }
}