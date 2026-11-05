@isTest
private class TimesheetInvoiceEngineTest {

    @testSetup
    static void setupData() {
        // 1. Account
        Account acc = new Account(
            Name = 'Acme Corporation',
            BillingStreet = '123 Market St',
            BillingCity = 'San Francisco',
            BillingState = 'CA',
            BillingPostalCode = '94105',
            BillingCountry = 'USA'
        );
        insert acc;

        // 2. Employee
        dbt__Employee__c emp = new dbt__Employee__c(
            dbt__First_Name__c = 'Jane',
            dbt__Last_Name__c = 'Doe',
            dbt__Email__c = 'jane.doe@example.com'
        );
        insert emp;

        // 3. Project
        dbt__Project__c proj = new dbt__Project__c(
            Name = 'Alpha Project',
            Account__c = acc.Id,
            dbt__Billable__c = 'Yes',
            dbt__Active__c = true
        );
        insert proj;

        // 4. Project Employee (Hourly Rate = 100)
        dbt__Project_Employee__c pe = new dbt__Project_Employee__c(
            dbt__Project__c = proj.Id,
            dbt__Employee__c = emp.Id,
            dbt__Hourly_Rate__c = 100.00
        );
        insert pe;

        // 5. Timesheet (Approved)
        Date refDate = Date.today().toStartOfWeek();
        dbt__Timesheet__c ts = new dbt__Timesheet__c(
            dbt__Employee__c = emp.Id,
            dbt__Status__c = 'Approved',
            dbt__Start_Date__c = refDate,
            dbt__End_Date__c = refDate.addDays(6)
        );
        insert ts;

        // 6. Timesheet Line Items
        List<dbt__Timesheet_Line_Item__c> lines = new List<dbt__Timesheet_Line_Item__c>{
            // Line 1: Development, Billable, 5 hours
            new dbt__Timesheet_Line_Item__c(
                dbt__Timesheet__c = ts.Id,
                dbt__Project__c = proj.Id,
                dbt__Activity__c = 'Development',
                dbt__Date__c = refDate,
                dbt__Duration__c = 5,
                dbt__Billable__c = 'Yes',
                dbt__Type__c = 'Attendance'
            ),
            // Line 2: Development, Billable, 3 hours (will merge with Line 1)
            new dbt__Timesheet_Line_Item__c(
                dbt__Timesheet__c = ts.Id,
                dbt__Project__c = proj.Id,
                dbt__Activity__c = 'Development',
                dbt__Date__c = refDate.addDays(1),
                dbt__Duration__c = 3,
                dbt__Billable__c = 'Yes',
                dbt__Type__c = 'Attendance'
            ),
            // Line 3: Consulting, Billable, 2 hours
            new dbt__Timesheet_Line_Item__c(
                dbt__Timesheet__c = ts.Id,
                dbt__Project__c = proj.Id,
                dbt__Activity__c = 'Consulting',
                dbt__Date__c = refDate.addDays(2),
                dbt__Duration__c = 2,
                dbt__Billable__c = 'Yes',
                dbt__Type__c = 'Attendance'
            ),
            // Line 4: Absence (Must be excluded)
            new dbt__Timesheet_Line_Item__c(
                dbt__Timesheet__c = ts.Id,
                dbt__Project__c = proj.Id,
                dbt__Activity__c = 'Vacation',
                dbt__Date__c = refDate.addDays(3),
                dbt__Duration__c = 8,
                dbt__Billable__c = 'No',
                dbt__Type__c = 'Absence',
                dbt__Absence_Category__c = 'PTO-Planned'
            )
        };
        insert lines;
    }

    @isTest
    static void testEndToEndInvoicing() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        dbt__Timesheet__c ts = [SELECT Id, dbt__Start_Date__c, dbt__End_Date__c FROM dbt__Timesheet__c LIMIT 1];

        Test.startTest();

        // 1. Test Fetch Action
        TimesheetInvoiceEngine.FetchRequest fetchReq = new TimesheetInvoiceEngine.FetchRequest();
        fetchReq.startDate = ts.dbt__Start_Date__c;
        fetchReq.endDate = ts.dbt__End_Date__c;
        fetchReq.onlyBillable = true;
        fetchReq.allowedStatuses = 'Approved';
        fetchReq.accountIdFilter = acc.Id;

        List<TimesheetInvoiceEngine.FetchResponse> fetchResponses =
            TimesheetInvoiceFetchAction.execute(new List<TimesheetInvoiceEngine.FetchRequest>{fetchReq});

        System.assertEquals(1, fetchResponses.size());
        TimesheetInvoiceEngine.FetchResponse fetchRes = fetchResponses[0];
        System.assertEquals(1, fetchRes.eligibleTimesheets.size(), 'Should find 1 eligible timesheet');
        System.assertEquals(3, fetchRes.eligibleLineItemIds.size(), 'Should find 3 billable items (excluding absence)');
        System.assertEquals(10, fetchRes.totalEligibleHours, 'Total hours should be 5 + 3 + 2 = 10');

        // 2. Test Preview Action
        TimesheetInvoiceEngine.PreviewRequest prevReq = new TimesheetInvoiceEngine.PreviewRequest();
        prevReq.selectedTimesheetIds = new List<Id>{ts.Id};
        prevReq.eligibleLineItemIds = fetchRes.eligibleLineItemIds;
        prevReq.startDate = fetchReq.startDate;
        prevReq.endDate = fetchReq.endDate;
        prevReq.onlyBillable = true;
        prevReq.dueDaysOffset = 30;
        prevReq.defaultInvoiceStatus = 'Confirmed';
        prevReq.descriptionTemplate = '{Project} - {Employee} ({Activity})';

        List<TimesheetInvoiceEngine.PreviewResponse> prevResponses =
            TimesheetInvoicePreviewAction.execute(new List<TimesheetInvoiceEngine.PreviewRequest>{prevReq});

        System.assertEquals(1, prevResponses.size());
        TimesheetInvoiceEngine.PreviewResponse prevRes = prevResponses[0];
        System.assertEquals(1, prevRes.previewInvoices.size(), 'Should propose 1 intermediate invoice for the account');
        System.assertEquals(2, prevRes.previewLineItems.size(), 'Should merge into 2 lines: Development and Consulting');
        System.assertEquals(1000.00, prevRes.totalProposedAmount, 'Total proposed amount should be 10 hrs * 100 = 1000');
        System.assert(String.isNotBlank(prevRes.previewJson), 'Preview JSON should be generated');

        // 3. Test Commit Action (using Preview JSON)
        TimesheetInvoiceEngine.CommitRequest commitReq = new TimesheetInvoiceEngine.CommitRequest();
        commitReq.previewJson = prevRes.previewJson;

        List<TimesheetInvoiceEngine.CommitResponse> commitResponses =
            TimesheetInvoiceCommitAction.execute(new List<TimesheetInvoiceEngine.CommitRequest>{commitReq});

        System.assertEquals(1, commitResponses.size());
        TimesheetInvoiceEngine.CommitResponse commitRes = commitResponses[0];
        System.assert(commitRes.isSuccess, 'Commit should succeed');
        System.assertEquals(1, commitRes.createdInvoiceIds.size());

        Id invoiceId = commitRes.createdInvoiceIds[0];
        Intermediate_Invoice__c inv = [SELECT Id, Account__c, Status__c, Billing_Address__c FROM Intermediate_Invoice__c WHERE Id = :invoiceId];
        System.assertEquals(acc.Id, inv.Account__c);
        System.assertEquals('Confirmed', inv.Status__c);

        List<Intermediate_Invoice_Line_Item__c> lines = [
            SELECT Id, Activity__c, Quantity__c, Unit_Price__c, Source_Timesheet_Line_Items__c
            FROM Intermediate_Invoice_Line_Item__c
            WHERE Intermediate_Invoice__c = :invoiceId
            ORDER BY Activity__c ASC
        ];
        System.assertEquals(2, lines.size());
        // Consulting
        System.assertEquals('Consulting', lines[0].Activity__c);
        System.assertEquals(2, lines[0].Quantity__c);
        System.assertEquals(100.00, lines[0].Unit_Price__c);
        // Development (merged 5 + 3 = 8)
        System.assertEquals('Development', lines[1].Activity__c);
        System.assertEquals(8, lines[1].Quantity__c);
        System.assertEquals(100.00, lines[1].Unit_Price__c);
        System.assert(lines[1].Source_Timesheet_Line_Items__c.contains(','), 'Merged line should contain comma-separated IDs');

        // 4. Test Deduplication: Running fetch again should return 0 eligible lines
        List<TimesheetInvoiceEngine.FetchResponse> secondFetchResponses =
            TimesheetInvoiceFetchAction.execute(new List<TimesheetInvoiceEngine.FetchRequest>{fetchReq});
        System.assertEquals(0, secondFetchResponses[0].eligibleLineItemIds.size(), 'Previously committed lines must be excluded');

        Test.stopTest();
    }

    @isTest
    static void testCommitViaSObjectListsFallback() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        dbt__Project__c proj = [SELECT Id FROM dbt__Project__c LIMIT 1];

        Intermediate_Invoice__c inv = new Intermediate_Invoice__c(
            Account__c = acc.Id,
            Invoice_Date__c = Date.today(),
            Status__c = 'Confirmed'
        );

        Intermediate_Invoice_Line_Item__c ili = new Intermediate_Invoice_Line_Item__c(
            Project__c = proj.Id,
            Activity__c = 'Testing',
            Quantity__c = 4,
            Unit_Price__c = 50.00,
            Billable__c = true
        );

        TimesheetInvoiceEngine.CommitRequest req = new TimesheetInvoiceEngine.CommitRequest();
        req.invoices = new List<Intermediate_Invoice__c>{inv};
        req.lineItems = new List<Intermediate_Invoice_Line_Item__c>{ili};

        Test.startTest();
        TimesheetInvoiceEngine.CommitResponse res = TimesheetInvoiceEngine.commitInvoices(req);
        Test.stopTest();

        System.assert(res.isSuccess);
        System.assertEquals(1, res.createdInvoiceIds.size());
    }

    @isTest
    static void testMissingRateDefaultsToZero() {
        // Create project without Project_Employee junction
        Account acc = [SELECT Id FROM Account LIMIT 1];
        dbt__Employee__c emp = [SELECT Id FROM dbt__Employee__c LIMIT 1];

        dbt__Project__c proj2 = new dbt__Project__c(
            Name = 'Beta Project',
            Account__c = acc.Id,
            dbt__Billable__c = 'Yes',
            dbt__Active__c = true
        );
        insert proj2;

        dbt__Timesheet__c ts2 = new dbt__Timesheet__c(
            dbt__Employee__c = emp.Id,
            dbt__Status__c = 'Approved',
            dbt__Start_Date__c = Date.today(),
            dbt__End_Date__c = Date.today().addDays(6)
        );
        insert ts2;

        dbt__Timesheet_Line_Item__c tli = new dbt__Timesheet_Line_Item__c(
            dbt__Timesheet__c = ts2.Id,
            dbt__Project__c = proj2.Id,
            dbt__Activity__c = 'Design',
            dbt__Date__c = Date.today(),
            dbt__Duration__c = 6,
            dbt__Billable__c = 'Yes',
            dbt__Type__c = 'Attendance'
        );
        insert tli;

        TimesheetInvoiceEngine.PreviewRequest prevReq = new TimesheetInvoiceEngine.PreviewRequest();
        prevReq.selectedTimesheetIds = new List<Id>{ts2.Id};
        prevReq.eligibleLineItemIds = new List<String>{String.valueOf(tli.Id)};
        prevReq.startDate = Date.today();
        prevReq.endDate = Date.today().addDays(6);
        prevReq.onlyBillable = true;

        Test.startTest();
        TimesheetInvoiceEngine.PreviewResponse prevRes = TimesheetInvoiceEngine.generateInvoicePreview(prevReq);
        Test.stopTest();

        System.assertEquals(1, prevRes.previewLineItems.size());
        System.assertEquals(0.00, prevRes.previewLineItems[0].Unit_Price__c, 'Rate should default to 0 when no junction record exists');
    }

    @isTest
    static void testPreviewWithNoSelectedTimesheets_UsesAll() {
        // When selectedTimesheets is null/empty, the engine should process ALL eligible timesheets
        Account acc = [SELECT Id FROM Account LIMIT 1];
        dbt__Employee__c emp = [SELECT Id FROM dbt__Employee__c LIMIT 1];
        dbt__Project__c proj = [SELECT Id FROM dbt__Project__c WHERE Account__c = :acc.Id LIMIT 1];
        dbt__Timesheet__c ts = [SELECT Id FROM dbt__Timesheet__c LIMIT 1];
        dbt__Timesheet_Line_Item__c tli = [SELECT Id FROM dbt__Timesheet_Line_Item__c WHERE dbt__Timesheet__c = :ts.Id LIMIT 1];

        // Pass empty selectedTimesheets (simulates user clicking Next without selecting any rows)
        TimesheetInvoiceEngine.PreviewRequest prevReq = new TimesheetInvoiceEngine.PreviewRequest();
        prevReq.selectedTimesheets = new List<dbt__Timesheet__c>(); // empty - no selection
        prevReq.eligibleLineItemIds = new List<String>{String.valueOf(tli.Id)};
        prevReq.startDate = Date.today().toStartOfWeek();
        prevReq.endDate = Date.today().toStartOfWeek().addDays(6);
        prevReq.onlyBillable = true;

        Test.startTest();
        TimesheetInvoiceEngine.PreviewResponse prevRes = TimesheetInvoiceEngine.generateInvoicePreview(prevReq);
        Test.stopTest();

        System.assert(prevRes.previewLineItems != null, 'Should return line items even with no explicit timesheet selection');
        System.assert(prevRes.invoiceCount >= 1, 'Should produce at least one invoice');
    }

    private static final String EMPLOYEE_CUSTOMER = 'dbt__Timesheet__r.dbt__Employee__r.Account__c';
    private static final String EMPLOYEE_KEY = 'dbt__Timesheet__r.dbt__Employee__c';

    // Second employee with an approved timesheet and 4 billable hours on the existing project.
    private static dbt__Employee__c addSecondEmployeeLine() {
        dbt__Project__c proj = [SELECT Id FROM dbt__Project__c LIMIT 1];
        // Each employee needs a distinct user (package validation rule).
        String uniqueName = 'invoice.key.' + System.currentTimeMillis() + '@example.com.test';
        User secondUser = new User(
            Alias = 'invkey', Email = 'invoice.key@example.com', LastName = 'Roe', Username = uniqueName,
            ProfileId = UserInfo.getProfileId(), EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles'
        );
        insert secondUser;
        dbt__Employee__c emp2 = new dbt__Employee__c(
            dbt__First_Name__c = 'John',
            dbt__Last_Name__c = 'Roe',
            dbt__Email__c = 'john.roe@example.com',
            dbt__User__c = secondUser.Id
        );
        insert emp2;
        insert new dbt__Project_Employee__c(dbt__Project__c = proj.Id, dbt__Employee__c = emp2.Id, dbt__Hourly_Rate__c = 50.00);

        Date refDate = Date.today().toStartOfWeek();
        dbt__Timesheet__c ts2 = new dbt__Timesheet__c(
            dbt__Employee__c = emp2.Id,
            dbt__Status__c = 'Approved',
            dbt__Start_Date__c = refDate,
            dbt__End_Date__c = refDate.addDays(6)
        );
        insert ts2;
        insert new dbt__Timesheet_Line_Item__c(
            dbt__Timesheet__c = ts2.Id,
            dbt__Project__c = proj.Id,
            dbt__Activity__c = 'Development',
            dbt__Date__c = refDate,
            dbt__Duration__c = 4,
            dbt__Billable__c = 'Yes',
            dbt__Type__c = 'Attendance'
        );
        return emp2;
    }

    private static TimesheetInvoiceEngine.FetchResponse fetchFor(String customerField) {
        TimesheetInvoiceEngine.FetchRequest req = new TimesheetInvoiceEngine.FetchRequest();
        req.startDate = Date.today().toStartOfWeek();
        req.endDate = req.startDate.addDays(6);
        req.onlyBillable = true;
        req.allowedStatuses = 'Approved';
        req.customerAccountField = customerField;
        return TimesheetInvoiceEngine.fetchEligibleTimesheets(req);
    }

    private static TimesheetInvoiceEngine.PreviewResponse previewFor(List<String> lineIds, String customerField, String keyFields) {
        TimesheetInvoiceEngine.PreviewRequest req = new TimesheetInvoiceEngine.PreviewRequest();
        req.eligibleLineItemIds = lineIds;
        req.startDate = Date.today().toStartOfWeek();
        req.endDate = req.startDate.addDays(6);
        req.customerAccountField = customerField;
        req.invoiceGroupingKeyFields = keyFields;
        return TimesheetInvoiceEngine.generateInvoicePreview(req);
    }

    @isTest
    static void testGroupingKeySplitsOneCustomerIntoSeparateInvoices() {
        addSecondEmployeeLine();
        List<String> lineIds = fetchFor(null).eligibleLineItemIds;

        System.assertEquals(1, previewFor(lineIds, null, null).invoiceCount, 'No key: one invoice per customer');

        TimesheetInvoiceEngine.PreviewResponse keyed = previewFor(lineIds, null, EMPLOYEE_KEY);
        System.assertEquals(2, keyed.invoiceCount, 'Employee key: one invoice per employee');
        System.assertEquals(1200.00, keyed.totalProposedAmount, 'Splitting must not change the total: 10h*100 + 4h*50');

        // Keys must be unique per invoice: the LWC uses them as its iteration key.
        List<Object> dtos = (List<Object>)JSON.deserializeUntyped(keyed.previewJson);
        Set<String> keys = new Set<String>();
        Set<String> labels = new Set<String>();
        for (Object dto : dtos) {
            keys.add((String)((Map<String, Object>)dto).get('invoiceKey'));
            labels.add((String)((Map<String, Object>)dto).get('groupLabel'));
        }
        System.assertEquals(2, keys.size());
        System.assertEquals(2, labels.size(), 'Labels identify each employee');
        System.assert(!labels.contains(null), 'Keyed invoices have a label');

        TimesheetInvoiceEngine.CommitRequest commitReq = new TimesheetInvoiceEngine.CommitRequest();
        commitReq.previewJson = keyed.previewJson;
        TimesheetInvoiceEngine.CommitResponse commitRes = TimesheetInvoiceEngine.commitInvoices(commitReq);
        System.assert(commitRes.isSuccess, commitRes.message);
        System.assertEquals(2, [SELECT COUNT() FROM Intermediate_Invoice__c WHERE Account__c = :[SELECT Id FROM Account LIMIT 1].Id]);
        System.assertEquals(0, fetchFor(null).eligibleLineItemIds.size(), 'Double-billing guard still works after a split');
    }

    @isTest
    static void testCustomerFromEmployeeBillsEmployeeAccount() {
        dbt__Employee__c emp2 = addSecondEmployeeLine();
        Account employeeCustomer = new Account(Name = 'Employee Customer', BillingCity = 'Austin');
        insert employeeCustomer;
        emp2.Account__c = employeeCustomer.Id;
        update emp2;

        // Project has a different customer: the employee's must win. First employee has none.
        TimesheetInvoiceEngine.FetchResponse fetched = fetchFor(EMPLOYEE_CUSTOMER);
        System.assertEquals(1, fetched.eligibleLineItemIds.size());
        System.assertEquals(3, fetched.skippedNoCustomerCount, 'Lines without a customer are reported, not silently lost');
        System.assertEquals(4, fetched.totalEligibleHours);

        TimesheetInvoiceEngine.PreviewResponse preview = previewFor(fetched.eligibleLineItemIds, EMPLOYEE_CUSTOMER, null);
        System.assertEquals(1, preview.invoiceCount);
        System.assertEquals(employeeCustomer.Id, preview.previewInvoices[0].Account__c);
        System.assert(preview.previewInvoices[0].Billing_Address__c.contains('Austin'), 'Address comes from the billed customer');
        System.assertEquals(200.00, preview.totalProposedAmount, 'Rate still comes from project + employee');
    }

    @isTest
    static void testEmployeeCustomerWorksWhenProjectHasNoAccount() {
        Account acc = [SELECT Id FROM Account LIMIT 1];
        update new dbt__Project__c(Id = [SELECT Id FROM dbt__Project__c LIMIT 1].Id, Account__c = null);
        update new dbt__Employee__c(Id = [SELECT Id FROM dbt__Employee__c LIMIT 1].Id, Account__c = acc.Id);

        System.assertEquals(0, fetchFor(null).eligibleLineItemIds.size(), 'Default project customer finds nothing');
        System.assertEquals(3, fetchFor(null).skippedNoCustomerCount);
        System.assertEquals(3, fetchFor(EMPLOYEE_CUSTOMER).eligibleLineItemIds.size());
    }

    @isTest
    static void testInvalidPathsFailInsteadOfMergingEverything() {
        List<String> lineIds = fetchFor(null).eligibleLineItemIds;
        for (String badKey : new List<String>{
            'Not_A_Field__c',
            'dbt__Project__r.Not_A_Field__c',
            'Bad__r.Name',
            'Id FROM Account --',
            'dbt__Project__c, '
        }) {
            try {
                previewFor(lineIds, null, badKey);
                System.assert(false, 'Should reject grouping key: ' + badKey);
            } catch (TimesheetInvoiceEngine.EngineException e) {
                System.assert(e.getMessage().contains('Invalid invoice field path'), e.getMessage());
            }
        }

        try {
            fetchFor('dbt__Project__c'); // valid lookup, wrong target object
            System.assert(false, 'Customer field must point to Account');
        } catch (TimesheetInvoiceEngine.EngineException e) {
            System.assert(e.getMessage().contains('lookup to Account'), e.getMessage());
        }
    }

    @isTest
    static void testCommitActionAttachesOnePdfPerSplitInvoice() {
        addSecondEmployeeLine();
        TimesheetInvoiceEngine.PreviewResponse keyed = previewFor(fetchFor(null).eligibleLineItemIds, null, EMPLOYEE_KEY);
        TimesheetInvoiceEngine.CommitRequest commitReq = new TimesheetInvoiceEngine.CommitRequest();
        commitReq.previewJson = keyed.previewJson;

        Test.startTest();
        TimesheetInvoiceEngine.CommitResponse res =
            TimesheetInvoiceCommitAction.execute(new List<TimesheetInvoiceEngine.CommitRequest>{commitReq})[0];
        Test.stopTest();

        System.assert(res.isSuccess, res.message);
        System.assertEquals(2, res.createdInvoiceIds.size());
        for (Id invoiceId : res.createdInvoiceIds) {
            String invoiceName = [SELECT Name FROM Intermediate_Invoice__c WHERE Id = :invoiceId].Name;
            List<ContentDocumentLink> links = [
                SELECT ContentDocument.Title, ContentDocument.FileExtension
                FROM ContentDocumentLink
                WHERE LinkedEntityId = :invoiceId
            ];
            System.assertEquals(1, links.size(), 'Each invoice gets its own PDF');
            System.assertEquals('Invoice-' + invoiceName, links[0].ContentDocument.Title);
            System.assertEquals('pdf', links[0].ContentDocument.FileExtension);
        }
    }

    @isTest
    static void testFailedCommitQueuesNoPdf() {
        TimesheetInvoiceEngine.CommitRequest commitReq = new TimesheetInvoiceEngine.CommitRequest();
        commitReq.previewJson = 'not json';

        Test.startTest();
        TimesheetInvoiceEngine.CommitResponse res =
            TimesheetInvoiceCommitAction.execute(new List<TimesheetInvoiceEngine.CommitRequest>{commitReq})[0];
        System.assertEquals(0, Limits.getQueueableJobs(), 'No PDF job after a failed commit');
        Test.stopTest();

        System.assert(!res.isSuccess);
    }

    @isTest
    static void testPdfServiceIgnoresEmptyInput() {
        Test.startTest();
        IntermediateInvoicePdfService.generatePdfs(null);
        System.enqueueJob(new InvoicePdfQueueable(new List<Id>()));
        Test.stopTest();
        System.assertEquals(0, [SELECT COUNT() FROM ContentVersion WHERE Title LIKE 'Invoice-%']);
    }
}
