public with sharing class TimesheetInvoiceCommitAction {

    @InvocableMethod(
        label='Commit Intermediate Invoices and Line Items'
        description='Atomically creates invoices and line items, then queues PDF generation.'
        category='Timesheet Invoicing'
    )
    public static List<TimesheetInvoiceEngine.CommitResponse> execute(
        List<TimesheetInvoiceEngine.CommitRequest> requests
    ) {

        List<TimesheetInvoiceEngine.CommitResponse> responses =
            new List<TimesheetInvoiceEngine.CommitResponse>();

        List<Id> invoiceIdsForPdf = new List<Id>();

        for (TimesheetInvoiceEngine.CommitRequest req : requests) {

            TimesheetInvoiceEngine.CommitResponse res =
                TimesheetInvoiceEngine.commitInvoices(req);

            responses.add(res);

            // Collect IDs only from successful commits
            if (
                res.isSuccess == true &&
                res.createdInvoiceIds != null &&
                !res.createdInvoiceIds.isEmpty()
            ) {

                invoiceIdsForPdf.addAll(res.createdInvoiceIds);
            }
        }

        // One asynchronous job for all generated invoices
        if (!invoiceIdsForPdf.isEmpty()) {

            System.enqueueJob(
                new InvoicePdfQueueable(invoiceIdsForPdf)
            );
        }

        return responses;
    }
}