public with sharing class TimesheetInvoiceCommitAction {

    @InvocableMethod(
        label='Commit Intermediate Invoices and Line Items'
        description='Atomically creates Intermediate_Invoice__c and Intermediate_Invoice_Line_Item__c records in the database with audit line item IDs.'
        category='Timesheet Invoicing'
    )
    public static List<TimesheetInvoiceEngine.CommitResponse> execute(List<TimesheetInvoiceEngine.CommitRequest> requests) {
        List<TimesheetInvoiceEngine.CommitResponse> responses = new List<TimesheetInvoiceEngine.CommitResponse>();
        for (TimesheetInvoiceEngine.CommitRequest req : requests) {
            responses.add(TimesheetInvoiceEngine.commitInvoices(req));
        }
        return responses;
    }
}
