public with sharing class TimesheetInvoicePreviewAction {

    @InvocableMethod(
        label='Generate Intermediate Invoice Preview'
        description='Aggregates timesheet line items by Customer Account, merges by project/employee/activity, resolves rates, and produces proposed in-memory intermediate invoices.'
        category='Timesheet Invoicing'
    )
    public static List<TimesheetInvoiceEngine.PreviewResponse> execute(List<TimesheetInvoiceEngine.PreviewRequest> requests) {
        List<TimesheetInvoiceEngine.PreviewResponse> responses = new List<TimesheetInvoiceEngine.PreviewResponse>();
        for (TimesheetInvoiceEngine.PreviewRequest req : requests) {
            responses.add(TimesheetInvoiceEngine.generateInvoicePreview(req));
        }
        return responses;
    }
}
