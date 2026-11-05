import { LightningElement, api, track } from 'lwc';

export default class InvoicePreviewEditor extends LightningElement {
    @track invoices = [];
    @track activeSections = [];

    _rawJson = '';
    @api totalAmount = 0.00;
    @api invoiceCount = 0;

    @api
    get totalAmountString() {
        return (this.totalAmount || 0).toFixed(2);
    }

    @api
    get previewJson() {
        return this._rawJson;
    }
    set previewJson(value) {
        this._rawJson = value;
        this.initializeData(value);
    }

    @api
    get editedPreviewJson() {
        return JSON.stringify(this.getCleanPayload());
    }

    get hasInvoices() {
        return this.invoices && this.invoices.length > 0;
    }

    get formattedGrandTotal() {
        return (this.totalAmount || 0).toFixed(2);
    }

    initializeData(jsonStr) {
        if (!jsonStr) {
            this.invoices = [];
            this.totalAmount = 0.00;
            this.invoiceCount = 0;
            return;
        }

        try {
            const parsed = JSON.parse(jsonStr);
            this.invoices = (parsed || []).map(inv => {
                let invTotal = 0;
                const formattedLines = (inv.lines || []).map(l => {
                    const qty = Number(l.quantity) || 0;
                    const price = Number(l.unitPrice) || 0;
                    const lineAmt = Math.round(qty * price * 100) / 100;
                    invTotal += lineAmt;
                    return {
                        ...l,
                        quantity: qty,
                        unitPrice: price,
                        amount: lineAmt,
                        amountFormatted: lineAmt.toFixed(2)
                    };
                });

                return {
                    ...inv,
                    invoiceKey: inv.invoiceKey || inv.accountId,
                    lines: formattedLines,
                    totalAmount: Math.round(invTotal * 100) / 100,
                    totalAmountFormatted: (Math.round(invTotal * 100) / 100).toFixed(2),
                    sectionLabel: this.buildSectionLabel(inv, invTotal)
                };
            });

            this.activeSections = this.invoices.map(inv => inv.invoiceKey);
            this.recalculateGrandTotal();
        } catch (err) {
            console.error('Error parsing previewJson in invoicePreviewEditor:', err);
            this.invoices = [];
        }
    }

    buildSectionLabel(inv, total) {
        const name = inv.groupLabel ? `${inv.accountName} - ${inv.groupLabel}` : inv.accountName;
        return `${name} (Proposed Total: $${total.toFixed(2)})`;
    }

    handleHeaderChange(event) {
        const invIdx = parseInt(event.target.dataset.invIdx, 10);
        const field = event.target.dataset.field;
        const val = event.target.value;

        if (this.invoices[invIdx]) {
            this.invoices[invIdx][field] = val;
            this.notifyFlow();
        }
    }

    handleLineChange(event) {
        const invIdx = parseInt(event.target.dataset.invIdx, 10);
        const lineIdx = parseInt(event.target.dataset.lineIdx, 10);
        const field = event.target.dataset.field;
        const val = event.target.value;

        const inv = this.invoices[invIdx];
        if (!inv || !inv.lines[lineIdx]) return;

        const line = inv.lines[lineIdx];

        if (field === 'quantity') {
            line.quantity = parseFloat(val) || 0;
        } else if (field === 'unitPrice') {
            line.unitPrice = parseFloat(val) || 0;
        } else if (field === 'description') {
            line.description = val;
        }

        // Recalculate line amount
        const lineAmt = Math.round(line.quantity * line.unitPrice * 100) / 100;
        line.amount = lineAmt;
        line.amountFormatted = lineAmt.toFixed(2);

        // Recalculate invoice total
        let subtotal = 0;
        inv.lines.forEach(l => {
            subtotal += l.amount || 0;
        });
        inv.totalAmount = Math.round(subtotal * 100) / 100;
        inv.totalAmountFormatted = inv.totalAmount.toFixed(2);
        inv.sectionLabel = this.buildSectionLabel(inv, inv.totalAmount);

        // Trigger reactivity
        this.invoices = [...this.invoices];
        this.recalculateGrandTotal();
        this.notifyFlow();
    }

    recalculateGrandTotal() {
        let grand = 0;
        this.invoices.forEach(inv => {
            grand += inv.totalAmount || 0;
        });
        this.totalAmount = Math.round(grand * 100) / 100;
        this.invoiceCount = this.invoices.length;
    }

    getCleanPayload() {
        return this.invoices.map(inv => {
            return {
                accountId: inv.accountId,
                accountName: inv.accountName,
                invoiceDate: inv.invoiceDate,
                dueDate: inv.dueDate,
                periodStart: inv.periodStart,
                periodEnd: inv.periodEnd,
                status: inv.status,
                billingAddress: inv.billingAddress,
                memo: inv.memo,
                totalAmount: inv.totalAmount,
                lines: (inv.lines || []).map(l => ({
                    lineNumber: l.lineNumber,
                    projectId: l.projectId,
                    employeeId: l.employeeId,
                    activity: l.activity,
                    description: l.description,
                    quantity: l.quantity,
                    unitPrice: l.unitPrice,
                    amount: l.amount,
                    billable: l.billable,
                    serviceDate: l.serviceDate,
                    sourceIds: l.sourceIds
                }))
            };
        });
    }

    notifyFlow() {
        // Dispatch custom change event to keep Flow runtime informed
        this.dispatchEvent(new CustomEvent('invoicepreviewchange', {
            detail: {
                payload: this.editedPreviewJson,
                totalAmount: this.totalAmount,
                count: this.invoiceCount
            }
        }));
    }
}
