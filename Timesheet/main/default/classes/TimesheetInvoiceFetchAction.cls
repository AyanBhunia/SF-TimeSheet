public with sharing class TimesheetInvoiceFetchAction {

    @InvocableMethod(
        label='Fetch Eligible Timesheets for Intermediate Invoicing'
        description='Finds candidate timesheets and line items for the selected date range, excluding already invoiced lines and absences.'
        category='Timesheet Invoicing'
    )
    public static List<TimesheetInvoiceEngine.FetchResponse> execute(List<TimesheetInvoiceEngine.FetchRequest> requests) {
        List<TimesheetInvoiceEngine.FetchResponse> responses = new List<TimesheetInvoiceEngine.FetchResponse>();
        for (TimesheetInvoiceEngine.FetchRequest req : requests) {
            responses.add(TimesheetInvoiceEngine.fetchEligibleTimesheets(req));
        }
        return responses;
    }
}
