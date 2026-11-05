public with sharing class TimesheetInvoiceEngine {

    public class EngineException extends Exception {}

    // Paths are relative to dbt__Timesheet_Line_Item__c.
    public static final String DEFAULT_CUSTOMER_FIELD = 'dbt__Project__r.Account__c';
    private static final String KEY_SEPARATOR = '\u001F';
    private static final Integer MAX_PATH_HOPS = 5;
    private static final Integer MAX_GROUP_LABEL_LENGTH = 200;

    public class FetchRequest {
        @InvocableVariable(required=true label='Start Date')
        public Date startDate;

        @InvocableVariable(required=true label='End Date')
        public Date endDate;

        @InvocableVariable(label='Only Billable Items')
        public Boolean onlyBillable;

        @InvocableVariable(label='Allowed Timesheet Statuses (comma-separated)')
        public String allowedStatuses; // default: 'Submitted,Approved'

        @InvocableVariable(label='Customer Account Filter')
        public Id accountIdFilter;

        @InvocableVariable(label='Customer Account Field' description='Path from Timesheet Line Item to the Account lookup that receives the invoice. Default: dbt__Project__r.Account__c. Employee customer: dbt__Timesheet__r.dbt__Employee__r.Account__c')
        public String customerAccountField;
    }

    public class FetchResponse {
        @InvocableVariable(label='Eligible Timesheets')
        public List<dbt__Timesheet__c> eligibleTimesheets;

        @InvocableVariable(label='Eligible Line Item IDs')
        public List<String> eligibleLineItemIds;

        @InvocableVariable(label='Total Eligible Hours')
        public Decimal totalEligibleHours;

        @InvocableVariable(label='Total Line Item Count')
        public Integer totalLineItemCount;

        @InvocableVariable(label='Lines Skipped - No Customer')
        public Integer skippedNoCustomerCount;
    }

    public class PreviewRequest {
        @InvocableVariable(label='Selected Timesheet Records (from Data Table)')
        public List<dbt__Timesheet__c> selectedTimesheets;

        @InvocableVariable(label='Selected Timesheet IDs')
        public List<Id> selectedTimesheetIds;

        @InvocableVariable(required=true label='Eligible Line Item IDs')
        public List<String> eligibleLineItemIds;

        @InvocableVariable(required=true label='Start Date')
        public Date startDate;

        @InvocableVariable(required=true label='End Date')
        public Date endDate;

        @InvocableVariable(label='Only Billable Items')
        public Boolean onlyBillable;

        @InvocableVariable(label='Customer Account Field' description='Path from Timesheet Line Item to the Account lookup that receives the invoice. Default: dbt__Project__r.Account__c. Employee customer: dbt__Timesheet__r.dbt__Employee__r.Account__c')
        public String customerAccountField;

        @InvocableVariable(label='Invoice Grouping Key Fields' description='Optional comma-separated paths from Timesheet Line Item. One invoice per customer and distinct key value, e.g. dbt__Timesheet__r.dbt__Employee__c,dbt__Project__c')
        public String invoiceGroupingKeyFields;

        @InvocableVariable(label='Default Payment Terms (Days)')
        public Integer dueDaysOffset; // Default: 30

        @InvocableVariable(label='Default Intermediate Invoice Status')
        public String defaultInvoiceStatus; // Default: 'Confirmed'

        @InvocableVariable(label='Line Description Template')
        public String descriptionTemplate; // Default: '{Project} - {Employee} ({Activity})'
    }

    public class PreviewResponse {
        public List<Intermediate_Invoice__c> previewInvoices;

        public List<Intermediate_Invoice_Line_Item__c> previewLineItems;

        @InvocableVariable(label='Preview JSON (for LWC Editor)')
        public String previewJson;

        @InvocableVariable(label='Total Proposed Amount')
        public Decimal totalProposedAmount;

        @InvocableVariable(label='Intermediate Invoice Count')
        public Integer invoiceCount;
    }

    public class CommitRequest {
        @InvocableVariable(label='Edited Preview JSON (from LWC)')
        public String previewJson;

        public List<Intermediate_Invoice__c> invoices;

        public List<Intermediate_Invoice_Line_Item__c> lineItems;
    }

    public class CommitResponse {
        @InvocableVariable(label='Created Intermediate Invoice IDs')
        public List<Id> createdInvoiceIds;

        @InvocableVariable(label='Success')
        public Boolean isSuccess;

        @InvocableVariable(label='Message')
        public String message;
    }

    // Helper method to collect all already-invoiced Timesheet Line Item IDs
    public static Set<Id> getAlreadyInvoicedLineItemIds() {
        Set<Id> invoicedIds = new Set<Id>();
        for (Intermediate_Invoice_Line_Item__c ili : [
            SELECT Source_Timesheet_Line_Items__c
            FROM Intermediate_Invoice_Line_Item__c
            WHERE Intermediate_Invoice__r.Status__c != 'Void'
        ]) {
            if (String.isNotBlank(ili.Source_Timesheet_Line_Items__c)) {
                for (String rawId : ili.Source_Timesheet_Line_Items__c.split(',')) {
                    String cleanId = rawId.trim();
                    if (String.isNotBlank(cleanId) && (cleanId.length() == 15 || cleanId.length() == 18)) {
                        try {
                            invoicedIds.add((Id)cleanId);
                        } catch (Exception e) {
                            // Ignore malformed IDs
                        }
                    }
                }
            }
        }
        return invoicedIds;
    }

    // Step 1: Fetch Eligible Timesheets and Line Items
    public static FetchResponse fetchEligibleTimesheets(FetchRequest req) {
        FetchResponse res = new FetchResponse();
        res.eligibleTimesheets = new List<dbt__Timesheet__c>();
        res.eligibleLineItemIds = new List<String>();
        res.totalEligibleHours = 0;
        res.totalLineItemCount = 0;
        res.skippedNoCustomerCount = 0;

        if (req == null || req.startDate == null || req.endDate == null) {
            return res;
        }

        // Parse allowed statuses
        List<String> statusList = new List<String>();
        if (String.isNotBlank(req.allowedStatuses)) {
            for (String s : req.allowedStatuses.split(',')) {
                if (String.isNotBlank(s)) statusList.add(s.trim());
            }
        }
        if (statusList.isEmpty()) {
            statusList.add('Submitted');
            statusList.add('Approved');
        }

        Set<Id> alreadyInvoicedIds = getAlreadyInvoicedLineItemIds();
        Boolean onlyBillable = req.onlyBillable != null ? req.onlyBillable : true;
        Id accountFilter = req.accountIdFilter;
        Date sDate = req.startDate;
        Date eDate = req.endDate;
        FieldPath customerPath = resolveCustomerPath(req.customerAccountField);

        // Base query for candidate line items
        String queryStr = 'SELECT Id, dbt__Date__c, dbt__Duration__c, dbt__Timesheet__c, ' +
                          'dbt__Project__c, dbt__Billable__c, ' + customerPath.path + ' ' +
                          'FROM dbt__Timesheet_Line_Item__c ' +
                          'WHERE dbt__Date__c >= :sDate AND dbt__Date__c <= :eDate ' +
                          'AND dbt__Timesheet__r.dbt__Status__c IN :statusList ' +
                          'AND dbt__Type__c != \'Absence\' ' +
                          'AND dbt__Absence_Category__c = null ' +
                          'AND dbt__Project__c != null ';

        if (onlyBillable) {
            queryStr += 'AND dbt__Billable__c = \'Yes\' ';
        }


        List<dbt__Timesheet_Line_Item__c> candidateItems = Database.query(queryStr);
        Set<Id> eligibleTimesheetIds = new Set<Id>();

        for (dbt__Timesheet_Line_Item__c tli : candidateItems) {
            if (!alreadyInvoicedIds.contains(tli.Id)) {
                Object customerId = customerPath.getValue(tli);
                if (customerId == null) {
                    res.skippedNoCustomerCount++;
                    continue;
                }
                if (accountFilter != null && (Id)customerId != accountFilter) {
                    continue;
                }
                res.eligibleLineItemIds.add(String.valueOf(tli.Id));
                eligibleTimesheetIds.add(tli.dbt__Timesheet__c);
                Decimal duration = tli.dbt__Duration__c != null ? tli.dbt__Duration__c : 0;
                res.totalEligibleHours += duration;
                res.totalLineItemCount++;
            }
        }

        if (!eligibleTimesheetIds.isEmpty()) {
            res.eligibleTimesheets = [
                SELECT Id, Name, dbt__Employee__c,
                       dbt__Start_Date__c, dbt__End_Date__c, dbt__Status__c, dbt__Total_Hours__c
                FROM dbt__Timesheet__c
                WHERE Id IN :eligibleTimesheetIds
                ORDER BY dbt__Start_Date__c DESC, Name ASC
            ];
        }

        return res;
    }

    // Validates a line-item field path against the schema. Nothing reaches dynamic SOQL
    // unless every segment exists, so a bad path fails loudly instead of grouping as null.
    private static FieldPath resolvePath(String rawPath) {
        String path = rawPath == null ? '' : rawPath.trim();
        List<String> parts = path.split('\\.');
        if (String.isBlank(path) || parts.size() > MAX_PATH_HOPS + 1) {
            throw new EngineException('Invalid invoice field path: "' + path + '"');
        }

        Schema.DescribeSObjectResult current = dbt__Timesheet_Line_Item__c.SObjectType.getDescribe();
        for (Integer i = 0; i < parts.size() - 1; i++) {
            Schema.DescribeFieldResult relField = null;
            for (Schema.SObjectField f : current.fields.getMap().values()) {
                Schema.DescribeFieldResult d = f.getDescribe();
                if (parts[i].equalsIgnoreCase(d.getRelationshipName())) {
                    relField = d;
                    break;
                }
            }
            if (relField == null || relField.getReferenceTo().size() != 1) {
                throw new EngineException('Invalid invoice field path: "' + path + '" - unknown relationship "' + parts[i] + '" on ' + current.getName());
            }
            current = relField.getReferenceTo()[0].getDescribe();
        }

        Schema.SObjectField leaf = current.fields.getMap().get(parts[parts.size() - 1].toLowerCase());
        if (leaf == null) {
            throw new EngineException('Invalid invoice field path: "' + path + '" - unknown field "' + parts[parts.size() - 1] + '" on ' + current.getName());
        }

        Schema.DescribeFieldResult leafDescribe = leaf.getDescribe();
        FieldPath result = new FieldPath(path, leafDescribe);
        List<Schema.SObjectType> targets = leafDescribe.getReferenceTo();
        if (targets.size() == 1 && leafDescribe.getRelationshipName() != null
                && targets[0].getDescribe().fields.getMap().containsKey('name')) {
            List<String> nameParts = parts.clone();
            nameParts[nameParts.size() - 1] = leafDescribe.getRelationshipName();
            nameParts.add('Name');
            result.namePath = String.join(nameParts, '.');
        }
        return result;
    }

    private static FieldPath resolveCustomerPath(String rawPath) {
        FieldPath customerPath = resolvePath(String.isNotBlank(rawPath) ? rawPath : DEFAULT_CUSTOMER_FIELD);
        List<Schema.SObjectType> targets = customerPath.describe.getReferenceTo();
        if (targets.size() != 1 || targets[0] != Account.SObjectType) {
            throw new EngineException('Customer Account Field must be a lookup to Account: "' + customerPath.path + '"');
        }
        return customerPath;
    }

    private static List<FieldPath> resolveGroupingPaths(String rawFields) {
        List<FieldPath> paths = new List<FieldPath>();
        if (String.isBlank(rawFields)) {
            return paths;
        }
        for (String rawField : rawFields.split(',')) {
            paths.add(resolvePath(rawField));
        }
        return paths;
    }

    // The customer always leads the key: one invoice can only ever bill one customer.
    public static String buildInvoiceKey(dbt__Timesheet_Line_Item__c tli, Id customerId, List<FieldPath> groupingPaths) {
        List<String> keyParts = new List<String>{ String.valueOf(customerId) };
        for (FieldPath groupingPath : groupingPaths) {
            Object val = groupingPath.getValue(tli);
            keyParts.add(val != null ? String.valueOf(val) : 'NULL');
        }
        return String.join(keyParts, KEY_SEPARATOR);
    }

    private static String buildGroupLabel(dbt__Timesheet_Line_Item__c tli, List<FieldPath> groupingPaths) {
        List<String> labels = new List<String>();
        for (FieldPath groupingPath : groupingPaths) {
            labels.add(groupingPath.getDisplayValue(tli));
        }
        return String.join(labels, ' / ').abbreviate(MAX_GROUP_LABEL_LENGTH);
    }

    // Step 2: In-Memory Preview Generation
    public static PreviewResponse generateInvoicePreview(PreviewRequest req) {
        PreviewResponse res = new PreviewResponse();
        res.previewInvoices = new List<Intermediate_Invoice__c>();
        res.previewLineItems = new List<Intermediate_Invoice_Line_Item__c>();
        res.totalProposedAmount = 0.00;
        res.invoiceCount = 0;

        if (req == null || req.eligibleLineItemIds == null || req.eligibleLineItemIds.isEmpty()) {
            res.previewJson = '[]';
            return res;
        }

        Set<Id> eligibleIds = new Set<Id>();
        for (String sId : req.eligibleLineItemIds) {
            eligibleIds.add((Id)sId);
        }

        Set<Id> selectedTsIds = new Set<Id>();
        if (req.selectedTimesheets != null) {
            for (dbt__Timesheet__c ts : req.selectedTimesheets) {
                if (ts.Id != null) selectedTsIds.add(ts.Id);
            }
        }
        if (req.selectedTimesheetIds != null) {
            selectedTsIds.addAll(req.selectedTimesheetIds);
        }

        // If no timesheets were explicitly selected (user clicked Next without selecting rows),
        // use ALL eligible timesheets (include all eligible line items without filtering by timesheet)
        Boolean useAllTimesheets = selectedTsIds.isEmpty();

        FieldPath customerPath = resolveCustomerPath(req.customerAccountField);
        List<FieldPath> groupingPaths = resolveGroupingPaths(req.invoiceGroupingKeyFields);

        // Query full details of eligible line items. Paths were validated by resolvePath.
        Map<String, String> selectFields = new Map<String, String>();
        for (String baseField : new List<String>{
            'Id', 'dbt__Date__c', 'dbt__Duration__c', 'dbt__Activity__c', 'dbt__Billable__c',
            'dbt__Project__c', 'dbt__Project__r.Name',
            'dbt__Timesheet__c', 'dbt__Timesheet__r.dbt__Employee__c', 'dbt__Timesheet__r.dbt__Employee__r.Name'
        }) {
            selectFields.put(baseField.toLowerCase(), baseField);
        }
        selectFields.put(customerPath.path.toLowerCase(), customerPath.path);
        for (FieldPath groupingPath : groupingPaths) {
            selectFields.put(groupingPath.path.toLowerCase(), groupingPath.path);
            if (groupingPath.namePath != null) {
                selectFields.put(groupingPath.namePath.toLowerCase(), groupingPath.namePath);
            }
        }

        String lineQuery = 'SELECT ' + String.join(selectFields.values(), ', ') +
                           ' FROM dbt__Timesheet_Line_Item__c WHERE Id IN :eligibleIds' +
                           (useAllTimesheets ? '' : ' AND dbt__Timesheet__c IN :selectedTsIds') +
                           ' ORDER BY dbt__Date__c ASC';
        List<dbt__Timesheet_Line_Item__c> lineItems = Database.query(lineQuery);

        if (lineItems.isEmpty()) {
            res.previewJson = '[]';
            return res;
        }

        // Rate Resolution: Query dbt__Project_Employee__c
        Set<Id> projectIds = new Set<Id>();
        Set<Id> employeeIds = new Set<Id>();
        for (dbt__Timesheet_Line_Item__c tli : lineItems) {
            if (tli.dbt__Project__c != null) projectIds.add(tli.dbt__Project__c);
            if (tli.dbt__Timesheet__r.dbt__Employee__c != null) employeeIds.add(tli.dbt__Timesheet__r.dbt__Employee__c);
        }

        Map<String, Decimal> rateMap = new Map<String, Decimal>();
        for (dbt__Project_Employee__c pe : [
            SELECT dbt__Project__c, dbt__Employee__c, dbt__Hourly_Rate__c
            FROM dbt__Project_Employee__c
            WHERE dbt__Project__c IN :projectIds AND dbt__Employee__c IN :employeeIds
        ]) {
            String rateKey = pe.dbt__Project__c + '_' + pe.dbt__Employee__c;
            rateMap.put(rateKey, pe.dbt__Hourly_Rate__c != null ? pe.dbt__Hourly_Rate__c : 0.00);
        }

        // Configuration defaults
        Integer dueOffset = req.dueDaysOffset != null ? req.dueDaysOffset : 30;
        String defaultStatus = String.isNotBlank(req.defaultInvoiceStatus) ? req.defaultInvoiceStatus : 'Confirmed';
        String descTemplate = String.isNotBlank(req.descriptionTemplate) ? req.descriptionTemplate : '{Project} - {Employee} ({Activity})';


        // Group Line Items by invoice key (customer + optional grouping fields)
        Map<String, InvoiceGroup> invoiceGroups = new Map<String, InvoiceGroup>();
        Set<Id> customerIds = new Set<Id>();

        for (dbt__Timesheet_Line_Item__c tli : lineItems) {
            Id accId = (Id)customerPath.getValue(tli);
            if (accId == null) continue;

            String invoiceKey = buildInvoiceKey(tli, accId, groupingPaths);
            if (!invoiceGroups.containsKey(invoiceKey)) {
                invoiceGroups.put(invoiceKey, new InvoiceGroup(invoiceKey, accId, buildGroupLabel(tli, groupingPaths)));
                customerIds.add(accId);
            }
            invoiceGroups.get(invoiceKey).lines.add(tli);
        }

        Map<Id, Account> accountInfoMap = new Map<Id, Account>([
            SELECT Id, Name, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry
            FROM Account
            WHERE Id IN :customerIds
        ]);

        // Build In-Memory Preview Intermediate Invoices and Lines
        List<Map<String, Object>> previewDtoList = new List<Map<String, Object>>();

        for (InvoiceGroup invoiceGroup : invoiceGroups.values()) {
            Id accId = invoiceGroup.accountId;
            Account acc = accountInfoMap.get(accId);
            if (acc == null) {
                throw new EngineException('You do not have access to customer Account ' + accId);
            }
            List<dbt__Timesheet_Line_Item__c> accLines = invoiceGroup.lines;

            // Intermediate Invoice Header
            Intermediate_Invoice__c inv = new Intermediate_Invoice__c();
            inv.Account__c = accId;
            inv.Invoice_Date__c = Date.today();
            inv.Due_Date__c = Date.today().addDays(dueOffset);
            inv.Billing_Period_Start__c = req.startDate;
            inv.Billing_Period_End__c = req.endDate;
            inv.Status__c = defaultStatus;

            List<String> addrParts = new List<String>();
            if (String.isNotBlank(acc.BillingStreet)) addrParts.add(acc.BillingStreet);
            if (String.isNotBlank(acc.BillingCity)) addrParts.add(acc.BillingCity);
            if (String.isNotBlank(acc.BillingState)) addrParts.add(acc.BillingState);
            if (String.isNotBlank(acc.BillingPostalCode)) addrParts.add(acc.BillingPostalCode);
            if (String.isNotBlank(acc.BillingCountry)) addrParts.add(acc.BillingCountry);
            inv.Billing_Address__c = String.join(addrParts, ', ');
            inv.Memo__c = 'Timesheet billing for ' + req.startDate.format() + ' - ' + req.endDate.format();
            if (String.isNotBlank(invoiceGroup.label)) {
                inv.Memo__c += ' (' + invoiceGroup.label + ')';
            }

            // Merge Lines for this Account
            // Composite Key -> Merged Wrapper
            Map<String, MergedLineWrapper> mergedMap = new Map<String, MergedLineWrapper>();

            for (dbt__Timesheet_Line_Item__c tli : accLines) {
                Id empId = tli.dbt__Timesheet__r.dbt__Employee__c;
                String empName = tli.dbt__Timesheet__r.dbt__Employee__r.Name;
                String projName = tli.dbt__Project__r.Name;
                String activity = String.isNotBlank(tli.dbt__Activity__c) ? tli.dbt__Activity__c : 'Standard Work';
                Boolean isBillable = tli.dbt__Billable__c == 'Yes';

                // Merge key: Project + Employee + Activity + Billable
                String mKey = tli.dbt__Project__c + '|' + empId + '|' + activity + '|' + (isBillable ? 'BILLABLE' : 'NON_BILLABLE');

                if (!mergedMap.containsKey(mKey)) {
                    MergedLineWrapper mlw = new MergedLineWrapper();
                    mlw.projectId = tli.dbt__Project__c;
                    mlw.projectName = projName;
                    mlw.employeeId = empId;
                    mlw.employeeName = empName;
                    mlw.activity = activity;
                    mlw.isBillable = isBillable;
                    mlw.totalHours = 0;
                    mlw.latestDate = tli.dbt__Date__c;
                    mlw.sourceIds = new List<String>();

                    String rateKey = tli.dbt__Project__c + '_' + empId;
                    mlw.unitPrice = isBillable && rateMap.containsKey(rateKey) ? rateMap.get(rateKey) : 0.00;

                    // Formatted description
                    String descStr = descTemplate;
                    descStr = descStr.replace('{Project}', projName != null ? projName : '');
                    descStr = descStr.replace('{Employee}', empName != null ? empName : '');
                    descStr = descStr.replace('{Activity}', activity);
                    mlw.description = descStr;

                    mergedMap.put(mKey, mlw);
                }

                MergedLineWrapper curr = mergedMap.get(mKey);
                Decimal dur = tli.dbt__Duration__c != null ? tli.dbt__Duration__c : 0;
                curr.totalHours += dur;
                curr.sourceIds.add(String.valueOf(tli.Id));
                if (tli.dbt__Date__c != null && (curr.latestDate == null || tli.dbt__Date__c > curr.latestDate)) {
                    curr.latestDate = tli.dbt__Date__c;
                }
            }

            // Create SObject Lines and DTO for JSON
            Decimal invoiceTotal = 0;
            Integer lineNum = 1;
            List<Map<String, Object>> lineDtoList = new List<Map<String, Object>>();

            for (MergedLineWrapper mlw : mergedMap.values()) {
                Intermediate_Invoice_Line_Item__c ili = new Intermediate_Invoice_Line_Item__c();
                ili.Line_Number__c = lineNum;
                ili.Project__c = mlw.projectId;
                ili.Employee__c = mlw.employeeId;
                ili.Activity__c = mlw.activity;
                ili.Description__c = mlw.description;
                ili.Quantity__c = mlw.totalHours;
                ili.Unit_Price__c = mlw.unitPrice;
                ili.Billable__c = mlw.isBillable;
                ili.Service_Date__c = mlw.latestDate != null ? mlw.latestDate : req.endDate;
                ili.Source_Timesheet_Line_Items__c = String.join(mlw.sourceIds, ',');

                Decimal lineAmt = (mlw.totalHours * mlw.unitPrice).setScale(2, RoundingMode.HALF_UP);
                invoiceTotal += lineAmt;

                res.previewLineItems.add(ili);

                // DTO for LWC
                Map<String, Object> lDto = new Map<String, Object>();
                lDto.put('lineNumber', lineNum);
                lDto.put('projectId', mlw.projectId);
                lDto.put('projectName', mlw.projectName);
                lDto.put('employeeId', mlw.employeeId);
                lDto.put('employeeName', mlw.employeeName);
                lDto.put('activity', mlw.activity);
                lDto.put('description', mlw.description);
                lDto.put('quantity', mlw.totalHours);
                lDto.put('unitPrice', mlw.unitPrice);
                lDto.put('amount', lineAmt);
                lDto.put('billable', mlw.isBillable);
                lDto.put('serviceDate', String.valueOf(ili.Service_Date__c));
                lDto.put('sourceIds', ili.Source_Timesheet_Line_Items__c);
                lDto.put('sourceCount', mlw.sourceIds.size());
                lineDtoList.add(lDto);

                lineNum++;
            }

            res.previewInvoices.add(inv);
            res.totalProposedAmount += invoiceTotal;
            res.invoiceCount++;

            // DTO Header for LWC
            Map<String, Object> invDto = new Map<String, Object>();
            invDto.put('invoiceKey', invoiceGroup.key);
            invDto.put('groupLabel', invoiceGroup.label);
            invDto.put('accountId', accId);
            invDto.put('accountName', acc.Name);
            invDto.put('invoiceDate', String.valueOf(inv.Invoice_Date__c));
            invDto.put('dueDate', String.valueOf(inv.Due_Date__c));
            invDto.put('periodStart', String.valueOf(inv.Billing_Period_Start__c));
            invDto.put('periodEnd', String.valueOf(inv.Billing_Period_End__c));
            invDto.put('status', inv.Status__c);
            invDto.put('billingAddress', inv.Billing_Address__c);
            invDto.put('memo', inv.Memo__c);
            invDto.put('totalAmount', invoiceTotal);
            invDto.put('lines', lineDtoList);
            previewDtoList.add(invDto);
        }

        res.previewJson = JSON.serialize(previewDtoList);
        return res;
    }

    // Step 3: Commit Intermediate Invoices & Line Items (Atomic Transaction)
    public static CommitResponse commitInvoices(CommitRequest req) {
        CommitResponse res = new CommitResponse();
        res.createdInvoiceIds = new List<Id>();
        res.isSuccess = false;

        Savepoint sp = Database.setSavepoint();
        try {
            List<Intermediate_Invoice__c> invoicesToInsert = new List<Intermediate_Invoice__c>();
            List<List<Intermediate_Invoice_Line_Item__c>> linesPerInvoice = new List<List<Intermediate_Invoice_Line_Item__c>>();

            // If previewJson is provided from LWC editor, parse edited data
            if (String.isNotBlank(req.previewJson) && req.previewJson != '[]') {
                List<Object> rawList = (List<Object>)JSON.deserializeUntyped(req.previewJson);
                for (Object rawInvObj : rawList) {
                    Map<String, Object> invMap = (Map<String, Object>)rawInvObj;
                    Intermediate_Invoice__c inv = new Intermediate_Invoice__c();
                    inv.Account__c = (Id)invMap.get('accountId');
                    if (invMap.get('invoiceDate') != null) inv.Invoice_Date__c = Date.valueOf((String)invMap.get('invoiceDate'));
                    if (invMap.get('dueDate') != null) inv.Due_Date__c = Date.valueOf((String)invMap.get('dueDate'));
                    if (invMap.get('periodStart') != null) inv.Billing_Period_Start__c = Date.valueOf((String)invMap.get('periodStart'));
                    if (invMap.get('periodEnd') != null) inv.Billing_Period_End__c = Date.valueOf((String)invMap.get('periodEnd'));
                    inv.Status__c = invMap.get('status') != null ? (String)invMap.get('status') : 'Confirmed';
                    inv.Billing_Address__c = (String)invMap.get('billingAddress');
                    inv.Memo__c = (String)invMap.get('memo');
                    if (invMap.get('totalAmount') != null) {
                        inv.Total_Amount__c = Decimal.valueOf(String.valueOf(invMap.get('totalAmount')));
                    }
                    invoicesToInsert.add(inv);

                    List<Intermediate_Invoice_Line_Item__c> currLines = new List<Intermediate_Invoice_Line_Item__c>();
                    List<Object> rawLines = (List<Object>)invMap.get('lines');
                    Integer lIndex = 1;
                    if (rawLines != null) {
                        for (Object rawLObj : rawLines) {
                            Map<String, Object> lMap = (Map<String, Object>)rawLObj;
                            Intermediate_Invoice_Line_Item__c ili = new Intermediate_Invoice_Line_Item__c();
                            ili.Line_Number__c = lIndex;
                            if (lMap.get('projectId') != null) ili.Project__c = (Id)lMap.get('projectId');
                            if (lMap.get('employeeId') != null) ili.Employee__c = (Id)lMap.get('employeeId');
                            ili.Activity__c = (String)lMap.get('activity');
                            ili.Description__c = (String)lMap.get('description');
                            ili.Quantity__c = lMap.get('quantity') != null ? Decimal.valueOf(String.valueOf(lMap.get('quantity'))) : 0;
                            ili.Unit_Price__c = lMap.get('unitPrice') != null ? Decimal.valueOf(String.valueOf(lMap.get('unitPrice'))) : 0;
                            ili.Billable__c = lMap.get('billable') != null ? Boolean.valueOf(lMap.get('billable')) : true;
                            if (lMap.get('serviceDate') != null) ili.Service_Date__c = Date.valueOf((String)lMap.get('serviceDate'));
                            ili.Source_Timesheet_Line_Items__c = (String)lMap.get('sourceIds');
                            currLines.add(ili);
                            lIndex++;
                        }
                    }
                    linesPerInvoice.add(currLines);
                }
            } else if (req.invoices != null && !req.invoices.isEmpty()) {
                // Fallback to SObject lists
                invoicesToInsert = req.invoices;
                // Group line items by Project -> Account
                Map<Id, Id> projectToAccount = new Map<Id, Id>();
                Set<Id> pIds = new Set<Id>();
                for (Intermediate_Invoice_Line_Item__c ili : req.lineItems) {
                    if (ili.Project__c != null) pIds.add(ili.Project__c);
                }
                for (dbt__Project__c p : [SELECT Id, Account__c FROM dbt__Project__c WHERE Id IN :pIds]) {
                    projectToAccount.put(p.Id, p.Account__c);
                }

                Map<Id, List<Intermediate_Invoice_Line_Item__c>> accToLines = new Map<Id, List<Intermediate_Invoice_Line_Item__c>>();
                for (Intermediate_Invoice_Line_Item__c ili : req.lineItems) {
                    Id accId = projectToAccount.get(ili.Project__c);
                    if (accId != null) {
                        if (!accToLines.containsKey(accId)) accToLines.put(accId, new List<Intermediate_Invoice_Line_Item__c>());
                        accToLines.get(accId).add(ili);
                    }
                }
                for (Intermediate_Invoice__c inv : invoicesToInsert) {
                    linesPerInvoice.add(accToLines.containsKey(inv.Account__c) ? accToLines.get(inv.Account__c) : new List<Intermediate_Invoice_Line_Item__c>());
                }
            }

            if (invoicesToInsert.isEmpty()) {
                res.message = 'No intermediate invoices to insert.';
                res.isSuccess = true;
                return res;
            }

            insert invoicesToInsert;

            List<Intermediate_Invoice_Line_Item__c> allLinesToInsert = new List<Intermediate_Invoice_Line_Item__c>();
            for (Integer i = 0; i < invoicesToInsert.size(); i++) {
                Intermediate_Invoice__c inv = invoicesToInsert[i];
                res.createdInvoiceIds.add(inv.Id);
                List<Intermediate_Invoice_Line_Item__c> lines = linesPerInvoice[i];
                for (Intermediate_Invoice_Line_Item__c line : lines) {
                    line.Intermediate_Invoice__c = inv.Id;
                    allLinesToInsert.add(line);
                }
            }

            if (!allLinesToInsert.isEmpty()) {
                insert allLinesToInsert;
            }

            res.isSuccess = true;
            res.message = 'Successfully generated ' + invoicesToInsert.size() + ' intermediate invoice(s) with ' + allLinesToInsert.size() + ' line item(s).';

        } catch (Exception e) {
            Database.rollback(sp);
            res.isSuccess = false;
            res.message = 'Commit failed: ' + e.getMessage() + ' | Line: ' + e.getLineNumber();
            // Do NOT re-throw - return the error response so the flow can handle it gracefully
        }

        return res;
    }

    private class InvoiceGroup {
        public String key;
        public Id accountId;
        public String label;
        public List<dbt__Timesheet_Line_Item__c> lines = new List<dbt__Timesheet_Line_Item__c>();

        public InvoiceGroup(String key, Id accountId, String label) {
            this.key = key;
            this.accountId = accountId;
            this.label = label;
        }
    }

    public class FieldPath {
        public String path;
        public String namePath;
        public Schema.DescribeFieldResult describe;

        public FieldPath(String path, Schema.DescribeFieldResult describe) {
            this.path = path;
            this.describe = describe;
        }

        public Object getValue(SObject record) {
            return read(record, path);
        }

        public String getDisplayValue(SObject record) {
            Object val = namePath != null ? read(record, namePath) : null;
            if (val == null) val = getValue(record);
            return val != null ? String.valueOf(val) : 'None';
        }

        private Object read(SObject record, String fieldPath) {
            List<String> parts = fieldPath.split('\\.');
            SObject current = record;
            for (Integer i = 0; i < parts.size() - 1; i++) {
                current = current.getSObject(parts[i]);
                if (current == null) return null;
            }
            return current.get(parts[parts.size() - 1]);
        }
    }

    private class MergedLineWrapper {
        public Id projectId;
        public String projectName;
        public Id employeeId;
        public String employeeName;
        public String activity;
        public String description;
        public Decimal totalHours;
        public Decimal unitPrice;
        public Boolean isBillable;
        public Date latestDate;
        public List<String> sourceIds;
    }
}
