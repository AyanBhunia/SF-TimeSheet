import { LightningElement, api } from 'lwc';

export default class PtoTable extends LightningElement {
    @api columns = [];
    @api rows = [];
    @api rowActions = [];
    @api sortedBy;
    @api sortedDirection = 'asc';
    @api emptyMessage;

    get hasRowActions() {
        return Array.isArray(this.rowActions) && this.rowActions.length > 0;
    }

    get columnCount() {
        let count = Array.isArray(this.columns) ? this.columns.length : 0;
        if (this.hasRowActions) {
            count += 1;
        }
        return count;
    }

    get isEmpty() {
        return !Array.isArray(this.rows) || this.rows.length === 0;
    }

    get displayEmptyMessage() {
        return this.emptyMessage || 'No records to display.';
    }

    get actionsStyle() {
        const count = Array.isArray(this.rowActions) ? this.rowActions.length : 0;
        return `width: ${Math.max(6, count * 6.5)}rem;`;
    }

    get sortIconName() {
        return this.sortedDirection === 'desc' ? 'utility:arrowdown' : 'utility:arrowup';
    }

    get viewColumns() {
        if (!Array.isArray(this.columns)) {
            return [];
        }
        return this.columns.map(col => {
            const isSorted = this.sortedBy === col.fieldName;
            const isRight = col.align === 'right';
            let headerClass = isRight ? 'slds-text-align_right' : 'slds-text-align_left';
            if (col.sortable) {
                headerClass += ' slds-is-sortable';
                if (isSorted) {
                    headerClass += ' slds-is-sorted slds-is-sorted_' + (this.sortedDirection || 'asc');
                }
            }
            let style = '';
            if (col.width) {
                style = `width: ${col.width};`;
            }
            return {
                fieldName: col.fieldName,
                actionClass: 'slds-th__action slds-text-link_reset' + (isRight ? ' slds-grid_align-end' : ''),
                label: col.label || col.fieldName,
                sortable: Boolean(col.sortable),
                isSorted,
                headerClass,
                style
            };
        });
    }

    get viewRows() {
        if (!Array.isArray(this.rows)) {
            return [];
        }
        const cols = Array.isArray(this.columns) ? this.columns : [];
        const hasActions = this.hasRowActions;
        const actions = Array.isArray(this.rowActions) ? this.rowActions : [];

        return this.rows.map(row => {
            const isLocked = Boolean(row.locked);
            const hasError = Boolean(row.error);
            const hasInfo = Boolean(row.info);
            const hasMessage = hasError || hasInfo;

            let rowClass = 'table-row';
            if (isLocked) {
                rowClass += ' row-locked';
            } else if (hasError) {
                rowClass += ' row-error';
            }

            let messageRowClass = 'message-row';
            if (!hasMessage) {
                messageRowClass += ' slds-hide';
            } else if (isLocked) {
                messageRowClass += ' row-locked';
            } else if (hasError) {
                messageRowClass += ' row-error';
            }

            const cells = cols.map(col => {
                const type = col.type || 'text';
                const isEditable = Boolean(col.editable && !isLocked);
                const rawValue = row[col.fieldName];
                const value = rawValue !== undefined && rawValue !== null ? rawValue : '';
                const isRight = col.align === 'right';
                const cellClass = isRight ? 'slds-text-align_right' : 'slds-text-align_left';

                let badgeClass = 'slds-badge';
                if (type === 'status') {
                    const statusVal = String(value);
                    if (statusVal === 'Submitted') {
                        badgeClass = 'slds-badge badge-submitted';
                    } else if (statusVal === 'Approved') {
                        badgeClass = 'slds-badge badge-approved';
                    } else if (statusVal === 'Rejected' || statusVal === 'Conversion error') {
                        badgeClass = 'slds-badge badge-rejected';
                    } else if (statusVal === 'Holiday') {
                        badgeClass = 'slds-badge badge-holiday';
                    } else {
                        badgeClass = 'slds-badge';
                    }
                }

                return {
                    key: `${row.key}-${col.fieldName}`,
                    rowKey: row.key,
                    fieldName: col.fieldName,
                    label: col.label || col.fieldName,
                    value,
                    type,
                    isEditable,
                    isText: type === 'text',
                    isDate: type === 'date',
                    isNumber: type === 'number',
                    isPicklist: type === 'picklist',
                    isStatus: type === 'status',
                    options: col.options || [],
                    selectOptions: [{ label: '--Pick--', value: '', selected: value === '' }].concat(
                        (col.options || []).map(o => ({ label: o.label, value: o.value, selected: o.value === value }))
                    ),
                    disabled: isLocked,
                    badgeClass,
                    cellClass
                };
            });

            return {
                key: row.key,
                messageKey: `${row.key}-msg`,
                actionsKey: `${row.key}-actions`,
                rowClass,
                messageRowClass,
                hasMessage,
                error: row.error,
                info: row.info,
                cells,
                showActions: hasActions && !isLocked,
                actions
            };
        });
    }

    renderedCallback() {
        // A native select keeps the user's last pick after re-render; push the current value back in.
        this.template.querySelectorAll('select[data-value]').forEach((select) => {
            if (select.value !== select.dataset.value) {
                select.value = select.dataset.value;
            }
        });
    }

    handleSortClick(event) {
        event.preventDefault();
        const fieldName = event.currentTarget.dataset.field;
        let direction = 'asc';
        if (this.sortedBy === fieldName) {
            direction = this.sortedDirection === 'asc' ? 'desc' : 'asc';
        }
        this.dispatchEvent(new CustomEvent('sort', {
            detail: { fieldName, direction }
        }));
    }

    handleCellChange(event) {
        const rowKey = event.currentTarget.dataset.rowKey;
        const fieldName = event.currentTarget.dataset.field;
        const value = event.detail && event.detail.value !== undefined ? event.detail.value : event.target.value;
        this.dispatchEvent(new CustomEvent('cellchange', {
            detail: { rowKey, fieldName, value }
        }));
    }

    handleRowAction(event) {
        const rowKey = event.currentTarget.dataset.rowKey;
        const action = event.currentTarget.dataset.action;
        this.dispatchEvent(new CustomEvent('rowaction', {
            detail: { rowKey, action }
        }));
    }
}
