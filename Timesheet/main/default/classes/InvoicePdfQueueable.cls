public with sharing class InvoicePdfQueueable implements Queueable {

    private List<Id> invoiceIds;

    public InvoicePdfQueueable(List<Id> invoiceIds) {
        this.invoiceIds = invoiceIds;
    }

    public void execute(QueueableContext context) {

        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return;
        }

        IntermediateInvoicePdfService.generatePdfs(invoiceIds);
    }
}