/**
 * @description Controller for the Demo Data Setup tab. Creates, lists and deletes sample records
 *              for the Timesheet application. Every demo record is flagged with Is_Demo__c and only
 *              the records flagged and created by the running user are ever read or deleted.
 *              All queries and DML run in user mode.
 */
public with sharing class DemoDataController {

    @TestVisible private static final String DEMO_PERMISSION = 'Timesheet_Demo_Data_Access';
    @TestVisible private static final String DEMO_FIRST_NAME = 'Demo';
    @TestVisible private static final String PARENT_LAST_NAME = 'Employee';
    @TestVisible private static final String CHILD_LAST_NAME_PREFIX = 'Child Employee ';
    @TestVisible private static final String PROJECT_BILLABLE = 'Demo Project - Billable';
    @TestVisible private static final String PROJECT_NON_BILLABLE = 'Demo Project - Non Billable';
    @TestVisible private static final String PROJECT_LEGACY = 'Demo Project - Legacy';
    private static final List<String> PROJECT_NAMES = new List<String>{ PROJECT_BILLABLE, PROJECT_NON_BILLABLE, PROJECT_LEGACY };
    private static final Decimal HOURLY_RATE = 150;

    /** One row in the employee, project or project assignment table; only the fields for that table are set. */
    public class DemoRecordDetail {
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String manager { get; set; }
        @AuraEnabled public Date accrualStartDate { get; set; }
        @AuraEnabled public Decimal accrualDivisor { get; set; }
        @AuraEnabled public Boolean canCreateChildren { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public String billable { get; set; }
        @AuraEnabled public String employeeName { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public Decimal hourlyRate { get; set; }
    }

    public class TimesheetLineItemDetail {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String dateStr { get; set; }
        @AuraEnabled public String projectOrType { get; set; }
        @AuraEnabled public Decimal duration { get; set; }
        @AuraEnabled public String description { get; set; }
    }

    public class TimesheetDetail {
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String employeeName { get; set; }
        @AuraEnabled public String periodName { get; set; }
        @AuraEnabled public String dateRange { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Decimal totalHours { get; set; }
        @AuraEnabled public List<TimesheetLineItemDetail> lineItems { get; set; }
    }

    public class DemoDataWrapper {
        @AuraEnabled public List<DemoRecordDetail> employees { get; set; }
        @AuraEnabled public List<DemoRecordDetail> projects { get; set; }
        @AuraEnabled public List<DemoRecordDetail> projectEmployees { get; set; }
        @AuraEnabled public List<TimesheetDetail> timesheets { get; set; }
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
        public Boolean hasDemoEmployees = false;
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
        result.put('hasEmployee', state.hasDemoEmployees);
        return result;
    }

    @AuraEnabled
    public static void createDemoEmployee() {
        assertCanCreate();
        try {
            if (!getDemoEmployees().isEmpty()) {
                throw newAuraException('A demo employee already exists.');
            }
            User currentUser = [SELECT Id, ManagerId FROM User WHERE Id = :UserInfo.getUserId() WITH USER_MODE LIMIT 1];
            Id managerId = currentUser.ManagerId != null ? currentUser.ManagerId : currentUser.Id;
            Database.insert(newDemoEmployee(PARENT_LAST_NAME, managerId), AccessLevel.USER_MODE);
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
                if (emp.Last_Name__c == PARENT_LAST_NAME) {
                    hasParent = true;
                } else if (emp.Last_Name__c != null && emp.Last_Name__c.startsWith(CHILD_LAST_NAME_PREFIX)) {
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
                Database.insert(toInsert, AccessLevel.USER_MODE);
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
            if (!items.isEmpty()) {
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

            Database.update(new Project__c(Id = legacyId, Active__c = false), AccessLevel.USER_MODE);
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

        List<Employee__c> emps = getDemoEmployees();
        Boolean childExists = false;
        for (Employee__c emp : emps) {
            if (emp.Last_Name__c != null && emp.Last_Name__c.startsWith(CHILD_LAST_NAME_PREFIX)) {
                childExists = true;
            }
        }
        for (Employee__c emp : emps) {
            DemoRecordDetail detail = new DemoRecordDetail();
            detail.recordId = emp.Id;
            detail.name = emp.Name;
            detail.manager = emp.Manager__r != null ? emp.Manager__r.Name : null;
            detail.accrualStartDate = emp.Accrual_Start_Date__c;
            detail.accrualDivisor = emp.Accrual_Divisor__c;
            detail.canCreateChildren = emp.Last_Name__c == PARENT_LAST_NAME && !childExists;
            wrapper.employees.add(detail);
        }

        for (Project__c proj : [
            SELECT Id, Name, Active__c, Billable__c
            FROM Project__c
            WHERE Is_Demo__c = true AND CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Name
        ]) {
            DemoRecordDetail detail = new DemoRecordDetail();
            detail.recordId = proj.Id;
            detail.name = proj.Name;
            detail.status = proj.Active__c ? 'Active' : 'Inactive';
            detail.billable = proj.Billable__c;
            wrapper.projects.add(detail);
        }

        for (Project_Employee__c pe : [
            SELECT Id, Project__r.Name, Employee__r.Name, Hourly_Rate__c
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
        }

        Date thisWeek = getWeekStart(Date.today());
        Map<Date, String> periodNames = new Map<Date, String>{
            thisWeek.addDays(-14) => 'Two Weeks Ago',
            thisWeek.addDays(-7) => 'Last Week',
            thisWeek => 'Current Week',
            thisWeek.addDays(7) => 'Next Week'
        };
        for (Timesheet__c ts : [
            SELECT Id, Start_Date__c, End_Date__c, Status__c, Total_Hours__c, Employee__r.Name,
                (SELECT Id, Date__c, Type__c, Absence_Category__c, Project__r.Name, Duration__c, Description__c
                 FROM Timesheets__r ORDER BY Date__c, Type__c)
            FROM Timesheet__c
            WHERE Employee__c IN :emps AND Is_Demo__c = true AND CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Employee__r.Name, Start_Date__c
        ]) {
            TimesheetDetail detail = new TimesheetDetail();
            detail.recordId = ts.Id;
            detail.employeeName = ts.Employee__r.Name;
            detail.periodName = periodNames.containsKey(ts.Start_Date__c) ? periodNames.get(ts.Start_Date__c) : 'Weekly Timesheet';
            detail.dateRange = ts.Start_Date__c.format() + ' - ' + ts.End_Date__c.format();
            detail.status = ts.Status__c;
            detail.totalHours = ts.Total_Hours__c != null ? ts.Total_Hours__c : 0;
            detail.lineItems = new List<TimesheetLineItemDetail>();
            for (Timesheet_Line_Item__c tli : ts.Timesheets__r) {
                TimesheetLineItemDetail item = new TimesheetLineItemDetail();
                item.id = tli.Id;
                item.dateStr = tli.Date__c.format();
                item.projectOrType = tli.Project__r != null ? tli.Project__r.Name : tli.Type__c + ' - ' + tli.Absence_Category__c;
                item.duration = tli.Duration__c;
                item.description = tli.Description__c;
                detail.lineItems.add(item);
            }
            wrapper.timesheets.add(detail);
        }

        return wrapper;
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
            SELECT Id, Name, Last_Name__c, Manager__c, Manager__r.Name, Accrual_Start_Date__c, Accrual_Divisor__c
            FROM Employee__c
            WHERE Is_Demo__c = true AND CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY CreatedDate, Last_Name__c
        ];
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
     * HR admins (Timesheet_Demo_Data_Access) without an active employee record can create demo data.
     * HR admins who still own demo records can always review and delete them.
     */
    private static AccessState getAccessState() {
        AccessState state = new AccessState();
        if (!FeatureManagement.checkPermission(DEMO_PERMISSION)) {
            return state;
        }
        Id currentUserId = UserInfo.getUserId();
        Boolean hasActiveEmployee = ![
            SELECT Id FROM Employee__c
            WHERE User__c = :currentUserId AND Active__c = true
            WITH USER_MODE
            LIMIT 1
        ].isEmpty();
        state.hasDemoEmployees = !getDemoEmployees().isEmpty();
        Boolean hasDemoRecords = state.hasDemoEmployees || ![
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
