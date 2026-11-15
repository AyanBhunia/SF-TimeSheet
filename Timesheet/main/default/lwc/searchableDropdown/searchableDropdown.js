import { LightningElement, api } from 'lwc';

const LIST_MAX_HEIGHT = 216;
const LIST_GAP = 4;
const VIEWPORT_MARGIN = 8;

/**
 * Searchable picklist (adapted from the QBO searchable dropdown).
 * Single select: bind `value`, the list closes on pick.
 * Multi select (`multi-select`): bind `values`, picks show as pills and the list stays open
 * until focus leaves the field (click outside, Tab or Escape).
 * Fires "change" with detail { name, value, values }.
 */
export default class SearchableDropdown extends LightningElement {
    @api label;
    @api name;
    @api placeholder = 'Search...';
    @api required = false;

    isOpen = false;
    searchTerm = '';
    highlightedIndex = -1;
    hasError = false;
    errorMessage = '';

    _options = [];
    _value = '';
    _values = [];
    _disabled = false;
    _multiSelect = false;

    @api
    get options() {
        return this._options;
    }
    set options(val) {
        this._options = val || [];
    }

    @api
    get value() {
        return this._value;
    }
    set value(val) {
        this._value = val === null || val === undefined ? '' : String(val);
        this.hasError = false;
    }

    @api
    get values() {
        return this._values;
    }
    set values(val) {
        this._values = Array.isArray(val) ? [...val] : [];
        this.hasError = false;
    }

    @api
    get disabled() {
        return this._disabled;
    }
    set disabled(val) {
        this._disabled = val === true || val === 'true';
        if (this._disabled) {
            this.closeList();
        }
    }

    @api
    get multiSelect() {
        return this._multiSelect;
    }
    set multiSelect(val) {
        this._multiSelect = val === true || val === 'true';
    }

    @api
    validate() {
        return this.runValidation();
    }

    @api
    focus() {
        const input = this.template.querySelector('.sd-input');
        if (input) {
            input.focus();
        }
    }

    connectedCallback() {
        this._repositionHandler = () => this.positionList();
    }

    renderedCallback() {
        if (this.isOpen) {
            this.positionList();
        }
    }

    disconnectedCallback() {
        this.removeWindowListeners();
    }

    // --- Computed ---

    get isMulti() {
        return this._multiSelect;
    }

    get iconName() {
        return this.isOpen ? 'utility:search' : 'utility:down';
    }

    get ariaExpanded() {
        return this.isOpen ? 'true' : 'false';
    }

    get ariaInvalid() {
        return this.hasError ? 'true' : 'false';
    }

    get ariaLabel() {
        return this.label || this.placeholder;
    }

    // While open the input holds the search text; closed it shows the selection
    get displayValue() {
        if (this.isOpen) {
            return this.searchTerm;
        }
        if (this.isMulti) {
            return this._values.length > 0 ? `${this._values.length} selected` : '';
        }
        const match = this._options.find(o => o.value === this._value);
        return match ? match.label : '';
    }

    get selectedOptions() {
        return this._values
            .map(v => this._options.find(o => o.value === v))
            .filter(o => o)
            .map(o => ({ ...o, key: 'pill-' + o.value }));
    }

    get showPills() {
        return this.isMulti && this.selectedOptions.length > 0;
    }

    get filteredOptions() {
        const search = this.searchTerm.trim().toLowerCase();
        return this._options
            .filter(o => !search || (o.label || '').toLowerCase().includes(search))
            .map((o, idx) => {
                const isSelected = this.isSelected(o.value);
                return {
                    ...o,
                    key: 'opt-' + o.value,
                    isSelected,
                    ariaSelected: isSelected ? 'true' : 'false',
                    itemClass:
                        'sd-option' +
                        (isSelected ? ' sd-option--selected' : '') +
                        (idx === this.highlightedIndex ? ' sd-option--highlighted' : '')
                };
            });
    }

    get hasFilteredOptions() {
        return this.filteredOptions.length > 0;
    }

    isSelected(val) {
        return this.isMulti ? this._values.includes(val) : val === this._value;
    }

    // --- Event handlers ---

    handleFocus() {
        this.openList();
    }

    // Focus stays in the input after a single pick, so a click has to reopen the list
    handleInputClick() {
        if (!this.isOpen) {
            this.openList();
        }
    }

    // Clicks on the icon area focus the input (which opens the list)
    handleWrapperClick() {
        if (this.disabled) {
            return;
        }
        this.focus();
    }

    // Option clicks keep focus in the input (see handleDropdownMouseDown), so a blur means focus left the field
    handleBlur() {
        this.closeList();
        this.runValidation();
    }

    handleInput(event) {
        this.searchTerm = event.target.value;
        this.highlightedIndex = this.filteredOptions.length > 0 ? 0 : -1;
        if (!this.isOpen) {
            this.openList();
        }
    }

    handleKeyDown(event) {
        const opts = this.filteredOptions;
        if (event.key === 'ArrowDown') {
            event.preventDefault();
            if (!this.isOpen) {
                this.openList();
                return;
            }
            this.highlightedIndex = Math.min(this.highlightedIndex + 1, opts.length - 1);
            this.scrollHighlightedIntoView();
        } else if (event.key === 'ArrowUp') {
            event.preventDefault();
            this.highlightedIndex = Math.max(this.highlightedIndex - 1, 0);
            this.scrollHighlightedIntoView();
        } else if (event.key === 'Enter') {
            event.preventDefault();
            if (this.isOpen && this.highlightedIndex >= 0 && this.highlightedIndex < opts.length) {
                this.selectOption(opts[this.highlightedIndex].value);
            }
        } else if (event.key === 'Escape' && this.isOpen) {
            // Close only the list, not the surrounding modal
            event.preventDefault();
            event.stopPropagation();
            this.closeList();
        }
    }

    handleSelect(event) {
        this.selectOption(event.currentTarget.dataset.value);
    }

    handleOptionHover(event) {
        const val = event.currentTarget.dataset.value;
        this.highlightedIndex = this.filteredOptions.findIndex(o => o.value === val);
    }

    // Keeps focus in the input while clicking options or the list's scrollbar
    handleDropdownMouseDown(event) {
        event.preventDefault();
    }

    handleRemovePill(event) {
        if (this.disabled) {
            return;
        }
        const val = event.target.name;
        this._values = this._values.filter(v => v !== val);
        this.fireChange();
        this.runValidation();
    }

    // --- Internal ---

    openList() {
        if (this.disabled || this.isOpen) {
            return;
        }
        this.searchTerm = '';
        this.highlightedIndex = this.isMulti ? -1 : this._options.findIndex(o => o.value === this._value);
        this.isOpen = true;
        // Follow the field when the page, modal or table scrolls
        window.addEventListener('scroll', this._repositionHandler, true);
        window.addEventListener('resize', this._repositionHandler);
    }

    closeList() {
        if (!this.isOpen) {
            return;
        }
        this.isOpen = false;
        this.searchTerm = '';
        this.highlightedIndex = -1;
        this.removeWindowListeners();
    }

    removeWindowListeners() {
        if (this._repositionHandler) {
            window.removeEventListener('scroll', this._repositionHandler, true);
            window.removeEventListener('resize', this._repositionHandler);
        }
    }

    selectOption(val) {
        if (this.isMulti) {
            this._values = this._values.includes(val)
                ? this._values.filter(v => v !== val)
                : [...this._values, val];
            this.hasError = false;
            this.fireChange();
            return;
        }
        this._value = val;
        this.hasError = false;
        this.closeList();
        this.fireChange();
    }

    runValidation() {
        const empty = this.isMulti ? this._values.length === 0 : !this._value;
        this.hasError = this.required && !this.disabled && empty;
        this.errorMessage = this.hasError ? 'Complete this field.' : '';
        return !this.hasError;
    }

    fireChange() {
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: { name: this.name, value: this._value, values: [...this._values] }
            })
        );
    }

    scrollHighlightedIntoView() {
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        requestAnimationFrame(() => {
            const el = this.template.querySelector('.sd-option--highlighted');
            if (el) {
                el.scrollIntoView({ block: 'nearest' });
            }
        });
    }

    // Places the list under the input, or above it when there is more room there,
    // and shrinks it to the room available so only the list scrolls
    positionList() {
        const anchor = this.template.querySelector('.sd-input');
        const list = this.template.querySelector('.sd-dropdown');
        const options = this.template.querySelector('.sd-options');
        if (!anchor || !list || !options) {
            return;
        }
        const rect = anchor.getBoundingClientRect();
        const viewportHeight = window.innerHeight;
        const spaceBelow = viewportHeight - rect.bottom - LIST_GAP - VIEWPORT_MARGIN;
        const spaceAbove = rect.top - LIST_GAP - VIEWPORT_MARGIN;
        const openUp = spaceBelow < LIST_MAX_HEIGHT && spaceAbove > spaceBelow;
        const room = Math.max(openUp ? spaceAbove : spaceBelow, 80);

        options.style.maxHeight = Math.min(LIST_MAX_HEIGHT, room) + 'px';
        list.style.width = rect.width + 'px';
        const left = rect.left;
        const top = openUp ? rect.top - LIST_GAP - list.offsetHeight : rect.bottom + LIST_GAP;
        list.style.left = left + 'px';
        list.style.top = top + 'px';

        // A transformed ancestor (the Lightning modal is one) makes "fixed" relative to it
        // instead of the viewport, so shift by however far the list landed from the target
        const placed = list.getBoundingClientRect();
        const dx = placed.left - left;
        const dy = placed.top - top;
        if (Math.abs(dx) > 0.5 || Math.abs(dy) > 0.5) {
            list.style.left = left - dx + 'px';
            list.style.top = top - dy + 'px';
        }
    }
}
