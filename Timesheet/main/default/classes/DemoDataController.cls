/**
 * @description Controller for the demo data setup popup (demoDataSetup LWC). Creates, lists and deletes
 *              sample records for the Timesheet application. Every demo record is flagged with Is_Demo__c;
 *              only records flagged and created by the running user, and the timesheets, line items and
 *              project assignments that belong to them, are ever read or deleted.
 *              Only HR admins may use it; all queries and DML run in user mode.
 */
public with sharing class DemoDataController {

    @TestVisible private static final String DEMO_FIRST_NAME = 'Demo';
    @TestVisible private static final String PARENT_LAST_NAME = 'Employee';
    @TestVisible private static final String CHILD_LAST_NAME_PREFIX = 'Child Employee ';
    @TestVisible private static final String PROJECT_BILLABLE = 'Demo Project - Billable';
    @TestVisible private static final String PROJECT_NON_BILLABLE = 'Demo Project - Non Billable';
    @TestVisible private static final String PROJECT_LEGACY = 'Demo Project - Legacy';
    private static final List<String> PROJECT_NAMES = new List<String>{ PROJECT_BILLABLE, PROJECT_NON_BILLABLE, PROJECT_LEGACY };
    private static final Decimal HOURLY_RATE = 150;

    /**
     * Fields the demo data tables may edit, by table and column key (the LWC's fieldName).
     * Anything else sent to saveDemoRecords() is rejected. Fields that feed the accrual and absence
     * totals (accrual settings, extra hours, line item dates and hours) are left out: the totals are
     * only recalculated when a timesheet is approved, so editing them here would leave them stale.
     */
    private static final Map<String, Map<String, SObjectField>> EDITABLE_FIELDS = new Map<String, Map<String, SObjectField>>{
        'employees' => new Map<String, SObjectField>{
            'email' => Employee__c.Email__c,
            'active' => Employee__c.Active__c
        },
        'projects' => new Map<String, SObjectField>{
            'active' => Project__c.Active__c,
            'startDate' => Project__c.Start_Date__c,
            'endDate' => Project__c.End_Date__c
        },
        'projectEmployees' => new Map<String, SObjectField>{
            'hourlyRate' => Project_Employee__c.Hourly_Rate__c
        }
    };

    /** One row in the employee, project or project assignment table; only the fields for that table are set. */
    public class DemoRecordDetail {
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String manager { get; set; }
        @AuraEnabled public Date accrualStartDate { get; set; }
        @AuraEnabled public Decimal accrualDivisor { get; set; }
        @AuraEnabled public Boolean canCreateChildren { get; set; }
        @AuraEnabled public String billable { get; set; }
        @AuraEnabled public String employeeName { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public Decimal hourlyRate { get; set; }
        @AuraEnabled public String email { get; set; }
        @AuraEnabled public String employmentType { get; set; }
        @AuraEnabled public Boolean active { get; set; }
        @AuraEnabled public Decimal extraAccruedHours { get; set; }
        @AuraEnabled public Decimal extraAbsenceHours { get; set; }
        @AuraEnabled public Decimal totalAccruedHours { get; set; }
        @AuraEnabled public Decimal totalAbsenceHours { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        /** An employee's project assignments and timesheets, so the LWC can tell which steps still have gaps. */
        @AuraEnabled public Integer assignmentCount { get; set; }
        @AuraEnabled public Integer timesheetCount { get; set; }
    }

    public class TimesheetLineItemDetail {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String timesheetId { get; set; }
        @AuraEnabled public Date lineDate { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public String activity { get; set; }
        @AuraEnabled public String absenceCategory { get; set; }
        @AuraEnabled public Decimal duration { get; set; }
    }

    public class TimesheetDetail {
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String employeeName { get; set; }
        @AuraEnabled public String periodName { get; set; }
        @AuraEnabled public String dateRange { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Decimal totalHours { get; set; }
        @AuraEnabled public Decimal billableHours { get; set; }
        @AuraEnabled public List<TimesheetLineItemDetail> lineItems { get; set; }
    }

    public class DemoDataWrapper {
        @AuraEnabled public List<DemoRecordDetail> employees { get; set; }
        @AuraEnabled public List<DemoRecordDetail> projects { get; set; }
        @AuraEnabled public List<DemoRecordDetail> projectEmployees { get; set; }
        @AuraEnabled public List<TimesheetDetail> timesheets { get; set; }
        /** True when a timesheet of the demo employee linked to the running user has no manager. */
        @AuraEnabled public Boolean userTimesheetsWithoutManager { get; set; }
    }

    public class DeleteSummary {
        @AuraEnabled public Integer lineItems { get; set; }
        @AuraEnabled public Integer timesheets { get; set; }
        @AuraEnabled public Integer projectEmployees { get; set; }
        @AuraEnabled public Integer projects { get; set; }
        @AuraEnabled public Integer employees { get; set; }
    }

    /** Demo records owned by the running user, in the order they must be deleted. */
    private class DemoScope {
        public List<Timesheet_Line_Item__c> lineItems;
        public List<Timesheet__c> timesheets;
        public List<Project_Employee__c> projectEmployees;
        public List<Project__c> projects;
        public List<Employee__c> employees;
    }

    /** Who may use demo data setup; see getAccessState(). */
    private class AccessState {
        public Boolean canCreate = false;
        public Boolean hasAccess = false;
    }

    @AuraEnabled
    public static Map<String, Object> getDemoStatus() {
        AccessState state = getAccessState();
        Map<String, Object> result = new Map<String, Object>{
            'hasAccess' => state.hasAccess,
            'canCreate' => state.canCreate
        };
        if (!state.hasAccess) {
            return result;
        }
        Organization org = [SELECT IsSandbox, TrialExpirationDate FROM Organization LIMIT 1];
        result.put('isProductionOrg', !org.IsSandbox && org.TrialExpirationDate == null);
        return result;
    }

    @AuraEnabled
    public static void createDemoEmployee() {
        assertCanCreate();
        try {
            if (!getDemoEmployees().isEmpty()) {
                throw newAuraException('A demo employee already exists.');
            }
            Id currentUserId = UserInfo.getUserId();
            if (![SELECT Id FROM Employee__c WHERE User__c = :currentUserId WITH USER_MODE LIMIT 1].isEmpty()) {
                throw newAuraException('An employee record is already linked to your user, so the demo employee cannot be linked to you.');
            }
            // Linked to the running user so the Employee Overview shows the demo data as their own. No manager.
            Employee__c emp = newDemoEmployee(PARENT_LAST_NAME, null);
            emp.User__c = currentUserId;
            Database.insert(emp, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void createChildEmployees() {
        assertCanCreate();
        try {
            Boolean hasParent = false;
            for (Employee__c emp : getDemoEmployees()) {
                if (isParent(emp)) {
                    hasParent = true;
                } else if (isChild(emp)) {
                    throw newAuraException('Child employees already exist.');
                }
            }
            if (!hasParent) {
                throw newAuraException('Create the demo employee first.');
            }
            // Children report to the running user so they can approve the demo timesheets themselves.
            Database.insert(new List<Employee__c>{
                newDemoEmployee(CHILD_LAST_NAME_PREFIX + 'A', UserInfo.getUserId()),
                newDemoEmployee(CHILD_LAST_NAME_PREFIX + 'B', UserInfo.getUserId())
            }, AccessLevel.USER_MODE);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void createDemoProjects() {
        assertCanCreate();
        try {
            Map<String, Project__c> existing = getDemoProjectsByName();
            Map<String, String> billableByName = new Map<String, String>{
                PROJECT_BILLABLE => 'Yes',
                PROJECT_NON_BILLABLE => 'No',
                PROJECT_LEGACY => 'No'
            };
            List<Project__c> toInsert = new List<Project__c>();
            for (String name : billableByName.keySet()) {
                if (!existing.containsKey(name)) {
                    toInsert.add(new Project__c(Name = name, Active__c = true, Billable__c = billableByName.get(name), Is_Demo__c = true));
                }
            }
            if (!toInsert.isEmpty()) {
                Database.insert(toInsert, AccessLevel.USER_MODE);
            }
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static void createDemoProjectAssignments() {
        assertCanCreate();
        try {
            List<Employee__c> emps = getDemoEmployees();
            List<Project__c> projs = getDemoProjectsByName().values();
            Set<String> existingKeys = new Set<String>();
            for (Project_Employee__c pe : [
                SELECT Employee__c, Project__c
                FROM Project_Employee__c
                WHERE Employee__c IN :emps
                WITH USER_MODE
            ]) {
                existingKeys.add(String.valueOf(pe.Employee__c) + pe.Project__c);
            }

            List<Project_Employee__c> toInsert = new List<Project_Employee__c>();
            for (Employee__c emp : emps) {
                for (Project__c proj : projs) {
                    if (!existingKeys.contains(String.valueOf(emp.Id) + proj.Id)) {
                        toInsert.add(new Project_Employee__c(Employee__c = emp.Id, Project__c = proj.Id, Hourly_Rate__c = HOURLY_RATE));
                    }
                }
            }
            if (!toInsert.isEmpty()) {
                // Child employees added after the timesheet step still get the (now inactive) legacy project.
                List<Project__c> reactivated = activateProjectsFor(toInsert);
                Database.insert(toInsert, AccessLevel.USER_MODE);
                deactivateProjects(reactivated);
            }
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    /**
     * Creates four weekly timesheets per demo employee:
     *  - two weeks ago: legacy project work, Approved
     *  - last week: billable + non-billable work with one sick day, Approved
     *  - this week: billable + non-billable work with two sick days, New
     *  - next week: empty, New
     * The legacy project is deactivated afterwards to show hours logged against an inactive project.
     */
    @AuraEnabled
    public static void createDemoTimesheets() {
        assertCanCreate();
        try {
            Map<String, Project__c> projects = getDemoProjectsByName();
            if (projects.size() < PROJECT_NAMES.size()) {
                throw newAuraException('Create the demo projects first.');
            }
            Id billableId = projects.get(PROJECT_BILLABLE).Id;
            Id nonBillableId = projects.get(PROJECT_NON_BILLABLE).Id;
            Id legacyId = projects.get(PROJECT_LEGACY).Id;

            Date thisWeek = getWeekStart(Date.today());
            Date twoWeeksAgo = thisWeek.addDays(-14);
            Date lastWeek = thisWeek.addDays(-7);
            Date nextWeek = thisWeek.addDays(7);

            List<Employee__c> emps = getDemoEmployees();
            Set<String> existingKeys = new Set<String>();
            for (Timesheet__c ts : [SELECT Employee__c, Start_Date__c FROM Timesheet__c WHERE Employee__c IN :emps WITH USER_MODE]) {
                existingKeys.add(String.valueOf(ts.Employee__c) + ts.Start_Date__c);
            }

            List<Timesheet__c> timesheets = new List<Timesheet__c>();
            for (Employee__c emp : emps) {
                for (Date weekStart : new List<Date>{ twoWeeksAgo, lastWeek, thisWeek, nextWeek }) {
                    if (!existingKeys.contains(String.valueOf(emp.Id) + weekStart)) {
                        timesheets.add(new Timesheet__c(
                            Name = 'Timesheet for ' + String.valueOf(weekStart) + ' to ' + String.valueOf(weekStart.addDays(6)),
                            Employee__c = emp.Id,
                            Manager__c = emp.Manager__c,
                            Start_Date__c = weekStart,
                            End_Date__c = weekStart.addDays(6),
                            Status__c = 'New',
                            Is_Demo__c = true
                        ));
                    }
                }
            }
            if (timesheets.isEmpty()) {
                return;
            }
            Database.insert(timesheets, AccessLevel.USER_MODE);

            List<Timesheet_Line_Item__c> items = new List<Timesheet_Line_Item__c>();
            List<Timesheet__c> approveFirst = new List<Timesheet__c>();
            List<Timesheet__c> approveSecond = new List<Timesheet__c>();
            for (Timesheet__c ts : timesheets) {
                if (ts.Start_Date__c == twoWeeksAgo) {
                    addWorkWeek(items, ts, legacyId, null, new Set<Integer>());
                    approveFirst.add(new Timesheet__c(Id = ts.Id, Status__c = 'Approved'));
                } else if (ts.Start_Date__c == lastWeek) {
                    addWorkWeek(items, ts, billableId, nonBillableId, new Set<Integer>{ 1 });
                    approveSecond.add(new Timesheet__c(Id = ts.Id, Status__c = 'Approved'));
                } else if (ts.Start_Date__c == thisWeek) {
                    addWorkWeek(items, ts, billableId, nonBillableId, new Set<Integer>{ 1, 2 });
                }
            }
            List<Project__c> reactivated = new List<Project__c>();
            if (!items.isEmpty()) {
                reactivated = activateProjectsFor(items);
                Database.insert(items, AccessLevel.USER_MODE);
            }

            // Approve in two steps: the first approval sets the employee's absence balance,
            // which Prevent_Insufficient_Absence_Hours checks when the week with sick leave is approved.
            if (!approveFirst.isEmpty()) {
                Database.update(approveFirst, AccessLevel.USER_MODE);
            }
            if (!approveSecond.isEmpty()) {
                Database.update(approveSecond, AccessLevel.USER_MODE);
            }

            // Restore projects that were inactive before, and deactivate the legacy project.
            Map<Id, Project__c> toDeactivate = new Map<Id, Project__c>(reactivated);
            toDeactivate.put(legacyId, new Project__c(Id = legacyId));
            deactivateProjects(toDeactivate.values());
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    @AuraEnabled
    public static DemoDataWrapper getDemoRecords() {
        assertAccess();
        DemoDataWrapper wrapper = new DemoDataWrapper();
        wrapper.employees = new List<DemoRecordDetail>();
        wrapper.projects = new List<DemoRecordDetail>();
        wrapper.projectEmployees = new List<DemoRecordDetail>();
        wrapper.timesheets = new List<TimesheetDetail>();
        wrapper.userTimesheetsWithoutManager = false;

        List<Employee__c> emps = getDemoEmployees();
        Boolean childExists = false;
        for (Employee__c emp : emps) {
            if (isChild(emp)) {
                childExists = true;
            }
        }
        Map<Id, DemoRecordDetail> employeeDetails = new Map<Id, DemoRecordDetail>();
        for (Employee__c emp : emps) {
            DemoRecordDetail detail = new DemoRecordDetail();
            detail.recordId = emp.Id;
            detail.name = emp.Name;
            detail.manager = emp.Manager__r != null ? emp.Manager__r.Name : null;
            detail.email = emp.Email__c;
            detail.employmentType = emp.Employment_Type__c;
            detail.active = emp.Active__c;
            detail.accrualStartDate = emp.Accrual_Start_Date__c;
            detail.accrualDivisor = emp.Accrual_Divisor__c;
            detail.extraAccruedHours = emp.Extra_Accrued_Hours__c;
            detail.extraAbsenceHours = emp.Extra_Absence_Hours__c;
            detail.totalAccruedHours = emp.Total_Accrued_Hours__c;
            detail.totalAbsenceHours = emp.Total_Absence_Hours__c;
            detail.canCreateChildren = isParent(emp) && !childExists;
            detail.assignmentCount = 0;
            detail.timesheetCount = 0;
            wrapper.employees.add(detail);
            employeeDetails.put(emp.Id, detail);
        }

        for (Project__c proj : [
            SELECT Id, Name, Active__c, Billable__c, Start_Date__c, End_Date__c
            FROM Project__c
            WHERE Is_Demo__c = true AND CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Name
        ]) {
            DemoRecordDetail detail = new DemoRecordDetail();
            detail.recordId = proj.Id;
            detail.name = proj.Name;
            detail.active = proj.Active__c;
            detail.billable = proj.Billable__c;
            detail.startDate = proj.Start_Date__c;
            detail.endDate = proj.End_Date__c;
            wrapper.projects.add(detail);
        }

        for (Project_Employee__c pe : [
            SELECT Id, Employee__c, Project__r.Name, Employee__r.Name, Hourly_Rate__c
            FROM Project_Employee__c
            WHERE Employee__c IN :emps AND Project__r.Is_Demo__c = true
            WITH USER_MODE
            ORDER BY Employee__r.Name, Project__r.Name
        ]) {
            DemoRecordDetail detail = new DemoRecordDetail();
            detail.recordId = pe.Id;
            detail.employeeName = pe.Employee__r.Name;
            detail.projectName = pe.Project__r.Name;
            detail.hourlyRate = pe.Hourly_Rate__c;
            wrapper.projectEmployees.add(detail);
            employeeDetails.get(pe.Employee__c).assignmentCount++;
        }

        Date thisWeek = getWeekStart(Date.today());
        Map<Date, String> periodNames = new Map<Date, String>{
            thisWeek.addDays(-14) => 'Two Weeks Ago',
            thisWeek.addDays(-7) => 'Last Week',
            thisWeek => 'Current Week',
            thisWeek.addDays(7) => 'Next Week'
        };
        for (Timesheet__c ts : [
            SELECT Id, Start_Date__c, End_Date__c, Status__c, Total_Hours__c, Billable_Hours__c, Manager__c,
                Employee__c, Employee__r.Name, Employee__r.User__c,
                (SELECT Id, Date__c, Activity__c, Absence_Category__c, Project__r.Name, Duration__c
                 FROM Timesheets__r ORDER BY Date__c, Type__c)
            FROM Timesheet__c
            WHERE Employee__c IN :emps AND Is_Demo__c = true AND CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Employee__r.Name, Start_Date__c
        ]) {
            if (ts.Employee__r.User__c == UserInfo.getUserId() && ts.Manager__c == null) {
                wrapper.userTimesheetsWithoutManager = true;
            }
            TimesheetDetail detail = new TimesheetDetail();
            detail.recordId = ts.Id;
            detail.employeeName = ts.Employee__r.Name;
            detail.periodName = periodNames.containsKey(ts.Start_Date__c) ? periodNames.get(ts.Start_Date__c) : 'Weekly Timesheet';
            detail.dateRange = ts.Start_Date__c.format() + ' - ' + ts.End_Date__c.format();
            detail.status = ts.Status__c;
            detail.totalHours = ts.Total_Hours__c != null ? ts.Total_Hours__c : 0;
            detail.billableHours = ts.Billable_Hours__c != null ? ts.Billable_Hours__c : 0;
            detail.lineItems = new List<TimesheetLineItemDetail>();
            for (Timesheet_Line_Item__c tli : ts.Timesheets__r) {
                TimesheetLineItemDetail item = new TimesheetLineItemDetail();
                item.id = tli.Id;
                item.timesheetId = ts.Id;
                item.lineDate = tli.Date__c;
                item.projectName = tli.Project__r != null ? tli.Project__r.Name : null;
                item.activity = tli.Activity__c;
                item.absenceCategory = tli.Absence_Category__c;
                item.duration = tli.Duration__c;
                detail.lineItems.add(item);
            }
            wrapper.timesheets.add(detail);
            if (employeeDetails.containsKey(ts.Employee__c)) {
                employeeDetails.get(ts.Employee__c).timesheetCount++;
            }
        }

        return wrapper;
    }

    /**
     * Saves inline edits from one demo data table. Each draft holds the row's recordId and the edited
     * column keys; only the running user's demo records and the fields in EDITABLE_FIELDS can be changed.
     * Rows are saved independently, so one failing row does not block the others.
     * @return error message by record Id for every row that was not saved
     */
    @AuraEnabled
    public static Map<String, String> saveDemoRecords(String tableKey, List<Map<String, Object>> drafts) {
        assertAccess();
        Map<String, SObjectField> fields = EDITABLE_FIELDS.get(tableKey);
        if (fields == null) {
            throw newAuraException('Unknown demo data table: ' + tableKey);
        }
        Map<String, String> errors = new Map<String, String>();
        try {
            Set<Id> allowedIds = getScopeIds(tableKey);
            List<SObject> records = new List<SObject>();
            for (Map<String, Object> draft : drafts) {
                String recordId = String.valueOf(draft.get('recordId'));
                SObject record = toRecord(draft, fields, allowedIds, errors);
                if (record != null) {
                    records.add(record);
                } else if (!errors.containsKey(recordId)) {
                    errors.put(recordId, 'This record cannot be edited here.');
                }
            }
            if (records.isEmpty()) {
                return errors;
            }
            // The Project lookup filter is checked on every update, so assignments to the
            // deactivated legacy project need it active while they are saved.
            List<Project__c> reactivated = activateProjectsFor(getLinkedProjects(tableKey, records));
            List<Database.SaveResult> results = Database.update(records, false, AccessLevel.USER_MODE);
            deactivateProjects(reactivated);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    errors.put(records[i].Id, results[i].getErrors()[0].getMessage());
                }
            }
        } catch (Exception e) {
            throw toAuraException(e);
        }
        return errors;
    }

    /** The record to update for one draft, or null when the record or one of its fields may not be edited. */
    private static SObject toRecord(Map<String, Object> draft, Map<String, SObjectField> fields, Set<Id> allowedIds, Map<String, String> errors) {
        Id recordId;
        try {
            recordId = Id.valueOf(String.valueOf(draft.get('recordId')));
        } catch (Exception e) {
            return null;
        }
        if (!allowedIds.contains(recordId)) {
            return null;
        }
        SObject record = recordId.getSObjectType().newSObject(recordId);
        for (String key : draft.keySet()) {
            if (key == 'recordId') {
                continue;
            }
            SObjectField field = fields.get(key);
            if (field == null) {
                errors.put(recordId, 'The field ' + key + ' cannot be edited here.');
                return null;
            }
            try {
                record.put(field, toFieldValue(field, draft.get(key)));
            } catch (Exception e) {
                errors.put(recordId, 'Invalid value for ' + field.getDescribe().getLabel() + '.');
                return null;
            }
        }
        return record;
    }

    /** Converts a datatable draft value (dates and numbers arrive as strings) to the field's type. */
    private static Object toFieldValue(SObjectField field, Object value) {
        Schema.DisplayType fieldType = field.getDescribe().getType();
        if (fieldType == Schema.DisplayType.BOOLEAN) {
            return value != null && Boolean.valueOf(value);
        }
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        String text = String.valueOf(value);
        switch on fieldType {
            when DATE {
                return Date.valueOf(text);
            }
            when DOUBLE, CURRENCY, PERCENT {
                return Decimal.valueOf(text);
            }
            when else {
                return text;
            }
        }
    }

    /** The records' Project__c values, for tables whose object has a filtered Project lookup. */
    private static List<SObject> getLinkedProjects(String tableKey, List<SObject> records) {
        if (tableKey == 'projectEmployees') {
            return [SELECT Project__c FROM Project_Employee__c WHERE Id IN :records WITH USER_MODE];
        }
        return new List<SObject>();
    }

    /**
     * Ids of the records the given table shows, with the same filters as getDemoRecords(). Narrower than
     * getDemoScope(), which also covers non-demo records linked to demo ones so they can be deleted.
     */
    private static Set<Id> getScopeIds(String tableKey) {
        Id currentUserId = UserInfo.getUserId();
        List<SObject> records;
        switch on tableKey {
            when 'employees' {
                records = [SELECT Id FROM Employee__c WHERE Is_Demo__c = true AND CreatedById = :currentUserId WITH USER_MODE];
            }
            when 'projects' {
                records = [SELECT Id FROM Project__c WHERE Is_Demo__c = true AND CreatedById = :currentUserId WITH USER_MODE];
            }
            when else {
                records = [
                    SELECT Id FROM Project_Employee__c
                    WHERE Employee__r.Is_Demo__c = true AND Employee__r.CreatedById = :currentUserId
                        AND Project__r.Is_Demo__c = true
                    WITH USER_MODE
                ];
            }
        }
        return new Map<Id, SObject>(records).keySet();
    }

    @AuraEnabled
    public static DeleteSummary getDeleteSummary() {
        assertAccess();
        DemoScope scope = getDemoScope();
        DeleteSummary summary = new DeleteSummary();
        summary.lineItems = scope.lineItems.size();
        summary.timesheets = scope.timesheets.size();
        summary.projectEmployees = scope.projectEmployees.size();
        summary.projects = scope.projects.size();
        summary.employees = scope.employees.size();
        return summary;
    }

    @AuraEnabled
    public static void deleteDemoRecords() {
        assertAccess();
        try {
            DemoScope scope = getDemoScope();
            deleteRecords(scope.lineItems);
            deleteRecords(scope.timesheets);
            deleteRecords(scope.projectEmployees);
            deleteRecords(scope.projects);
            deleteRecords(scope.employees);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    /**
     * Demo employees and projects flagged Is_Demo__c and created by the running user, plus every
     * timesheet, line item and project assignment that belongs to them.
     */
    private static DemoScope getDemoScope() {
        Id currentUserId = UserInfo.getUserId();
        DemoScope scope = new DemoScope();
        scope.employees = getDemoEmployees();
        scope.projects = [
            SELECT Id FROM Project__c
            WHERE Is_Demo__c = true AND CreatedById = :currentUserId
            WITH USER_MODE
        ];
        scope.timesheets = [
            SELECT Id FROM Timesheet__c
            WHERE (Is_Demo__c = true AND CreatedById = :currentUserId) OR Employee__c IN :scope.employees
            WITH USER_MODE
        ];
        scope.lineItems = [
            SELECT Id FROM Timesheet_Line_Item__c
            WHERE Timesheet__c IN :scope.timesheets
            WITH USER_MODE
        ];
        scope.projectEmployees = [
            SELECT Id FROM Project_Employee__c
            WHERE Employee__c IN :scope.employees OR Project__c IN :scope.projects
            WITH USER_MODE
        ];
        return scope;
    }

    private static void deleteRecords(List<SObject> records) {
        if (!records.isEmpty()) {
            Database.delete(records, AccessLevel.USER_MODE);
        }
    }

    private static List<Employee__c> getDemoEmployees() {
        return [
            SELECT Id, Name, Last_Name__c, User__c, Manager__c, Manager__r.Name, Email__c, Employment_Type__c, Active__c,
                Accrual_Start_Date__c, Accrual_Divisor__c, Extra_Accrued_Hours__c, Extra_Absence_Hours__c,
                Total_Accrued_Hours__c, Total_Absence_Hours__c
            FROM Employee__c
            WHERE Is_Demo__c = true AND CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY CreatedDate, Last_Name__c
        ];
    }

    /** The demo employee linked to the running user. Found by the link, so it survives name edits. */
    private static Boolean isParent(Employee__c emp) {
        return emp.User__c == UserInfo.getUserId();
    }

    /** A child employee: not linked to a user and reporting to the running user. */
    private static Boolean isChild(Employee__c emp) {
        return emp.User__c == null && emp.Manager__c == UserInfo.getUserId();
    }

    /**
     * The Project lookups on assignments and line items only accept active projects when they are set,
     * so the inactive projects the new records point to are activated for the insert. That only happens
     * when records are added after a project was deactivated (e.g. child employees added after the
     * timesheet step). Returns the activated projects for deactivateProjects().
     */
    private static List<Project__c> activateProjectsFor(List<SObject> records) {
        Set<Id> projectIds = new Set<Id>();
        for (SObject record : records) {
            projectIds.add((Id) record.get('Project__c'));
        }
        projectIds.remove(null);
        List<Project__c> inactive = [
            SELECT Id FROM Project__c
            WHERE Id IN :projectIds AND Active__c = false
            WITH USER_MODE
        ];
        for (Project__c proj : inactive) {
            proj.Active__c = true;
        }
        if (!inactive.isEmpty()) {
            Database.update(inactive, AccessLevel.USER_MODE);
        }
        return inactive;
    }

    private static void deactivateProjects(List<Project__c> projects) {
        for (Project__c proj : projects) {
            proj.Active__c = false;
        }
        if (!projects.isEmpty()) {
            Database.update(projects, AccessLevel.USER_MODE);
        }
    }

    private static Map<String, Project__c> getDemoProjectsByName() {
        Map<String, Project__c> projects = new Map<String, Project__c>();
        for (Project__c proj : [
            SELECT Id, Name
            FROM Project__c
            WHERE Is_Demo__c = true AND CreatedById = :UserInfo.getUserId()
                AND Name IN :PROJECT_NAMES
            WITH USER_MODE
        ]) {
            projects.put(proj.Name, proj);
        }
        return projects;
    }

    private static Employee__c newDemoEmployee(String lastName, Id managerId) {
        return new Employee__c(
            First_Name__c = DEMO_FIRST_NAME,
            Last_Name__c = lastName,
            Email__c = UserInfo.getUserEmail(),
            Manager__c = managerId,
            Employment_Type__c = 'Full Time',
            Active__c = true,
            Accrual_Start_Date__c = Date.today().addMonths(-1),
            Accrual_Divisor__c = 8,
            Extra_Accrued_Hours__c = 30,
            Is_Demo__c = true
        );
    }

    /**
     * Adds Monday-Friday line items. With a single project each day is 8h on it; with two projects
     * each day is split 4h/4h. Days in sickDays (0 = Monday) get an 8h Sick Leave absence instead.
     */
    private static void addWorkWeek(List<Timesheet_Line_Item__c> items, Timesheet__c ts, Id primaryProjectId, Id secondaryProjectId, Set<Integer> sickDays) {
        for (Integer day = 0; day < 5; day++) {
            Date workDate = ts.Start_Date__c.addDays(day);
            if (sickDays.contains(day)) {
                items.add(newLineItem(ts, workDate, 8, 'Demo - Sick leave', null, null, 'Absence', 'Sick Leave'));
            } else if (secondaryProjectId == null) {
                items.add(newLineItem(ts, workDate, 8, 'Demo - Project work', primaryProjectId, 'Development-Coding', 'Attendance', null));
            } else {
                items.add(newLineItem(ts, workDate, 4, 'Demo - Billable work', primaryProjectId, 'Development-Coding', 'Attendance', null));
                items.add(newLineItem(ts, workDate, 4, 'Demo - Non-billable work', secondaryProjectId, 'Meeting', 'Attendance', null));
            }
        }
    }

    private static Timesheet_Line_Item__c newLineItem(Timesheet__c ts, Date workDate, Decimal hours, String description,
            Id projectId, String activity, String type, String absenceCategory) {
        return new Timesheet_Line_Item__c(
            Timesheet__c = ts.Id,
            Employee__c = ts.Employee__c,
            Date__c = workDate,
            Duration__c = hours,
            Description__c = description,
            Project__c = projectId,
            Activity__c = activity,
            Type__c = type,
            Absence_Category__c = absenceCategory
        );
    }

    /** Monday of the week containing the given date (1900-01-01 was a Monday). */
    private static Date getWeekStart(Date value) {
        return value.addDays(-Math.mod(Date.newInstance(1900, 1, 1).daysBetween(value), 7));
    }

    /**
     * HR admins (Timesheet_HR_Admin permission set) without an active employee record can create demo data.
     * HR admins who still own demo records can always review and delete them.
     */
    private static AccessState getAccessState() {
        AccessState state = new AccessState();
        if (!GetDashboardProfileDetails.hasHrAdminPermission()) {
            return state;
        }
        Id currentUserId = UserInfo.getUserId();
        Boolean hasActiveEmployee = ![
            SELECT Id FROM Employee__c
            WHERE User__c = :currentUserId AND Active__c = true AND Is_Demo__c = false
            WITH USER_MODE
            LIMIT 1
        ].isEmpty();
        Boolean hasDemoRecords = !getDemoEmployees().isEmpty() || ![
            SELECT Id FROM Project__c
            WHERE Is_Demo__c = true AND CreatedById = :currentUserId
            WITH USER_MODE
            LIMIT 1
        ].isEmpty();
        state.canCreate = !hasActiveEmployee;
        state.hasAccess = state.canCreate || hasDemoRecords;
        return state;
    }

    private static void assertAccess() {
        if (!getAccessState().hasAccess) {
            throw newAuraException('Demo data setup is available to HR admins without an active employee record.');
        }
    }

    private static void assertCanCreate() {
        if (!getAccessState().canCreate) {
            throw newAuraException('Demo data can only be created by HR admins without an active employee record.');
        }
    }

    private static AuraHandledException toAuraException(Exception e) {
        if (e instanceof AuraHandledException) {
            return (AuraHandledException) e;
        }
        return newAuraException(e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage());
    }

    private static AuraHandledException newAuraException(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
