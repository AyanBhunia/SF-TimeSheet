/**
 * @description Controller for the demo data setup popup (demoDataSetupModal LWC). Creates, lists and deletes
 *              sample records for the Timesheet application, with as few queries as possible:
 *              - Only the Timesheet_HR_Admin permission set grants access to this class, all queries run
 *                WITH USER_MODE and all DML in user mode, so no method repeats an access check.
 *              - The Employee trigger allows one employee per user, which blocks a second demo employee.
 *              - Everything the popup shows comes from two queries: demo employees with their assignments,
 *                timesheets and line items (queryEmployees) and demo projects (queryProjects).
 *              - The blueprint lists every record the demo creates. The create methods build their records
 *                from it and the popup builds its previews from it, so the preview matches what is created.
 *              Demo records are flagged with Is_Demo__c and created by the running user.
 */
public with sharing class DemoDataController {

    @TestVisible private static final String DEMO_FIRST_NAME = 'Demo';
    @TestVisible private static final String PARENT_LAST_NAME = 'Employee';
    @TestVisible private static final String CHILD_LAST_NAME_PREFIX = 'Child Employee ';
    @TestVisible private static final String PROJECT_BILLABLE = 'Demo Project - Billable';
    @TestVisible private static final String PROJECT_NON_BILLABLE = 'Demo Project - Non Billable';
    @TestVisible private static final String PROJECT_LEGACY = 'Demo Project - Legacy';
    private static final List<String> PROJECT_NAMES = new List<String>{ PROJECT_BILLABLE, PROJECT_LEGACY, PROJECT_NON_BILLABLE };
    private static final Decimal HOURLY_RATE = 150;
    private static final String STATUS_NEW = 'New';
    private static final String STATUS_APPROVED = 'Approved';

    /** One row in the employee, project or project assignment table; only the fields for that table are set. */
    public class DemoRecordDetail {
        @AuraEnabled public String recordId { get; set; }
        @AuraEnabled public String name { get; set; }
        @AuraEnabled public String manager { get; set; }
        @AuraEnabled public Date accrualStartDate { get; set; }
        @AuraEnabled public Decimal accrualDivisor { get; set; }
        @AuraEnabled public Boolean isChild { get; set; }
        @AuraEnabled public String billable { get; set; }
        @AuraEnabled public String employeeId { get; set; }
        @AuraEnabled public String employeeName { get; set; }
        @AuraEnabled public String projectId { get; set; }
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
        /** An employee's project assignments and timesheets, so the popup can tell which steps still have gaps. */
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
        @AuraEnabled public String employeeId { get; set; }
        @AuraEnabled public String employeeName { get; set; }
        @AuraEnabled public String periodName { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public String dateRange { get; set; }
        @AuraEnabled public String status { get; set; }
        @AuraEnabled public Decimal totalHours { get; set; }
        @AuraEnabled public Decimal billableHours { get; set; }
        @AuraEnabled public List<TimesheetLineItemDetail> lineItems { get; set; }
    }

    /**
     * What the popup shows. A null list means "unchanged": a create method only returns what it changed,
     * and the popup keeps the rest. employees, projectEmployees and timesheets always come together.
     */
    public class DemoState {
        @AuraEnabled public List<DemoRecordDetail> employees { get; set; }
        @AuraEnabled public List<DemoRecordDetail> projectEmployees { get; set; }
        @AuraEnabled public List<TimesheetDetail> timesheets { get; set; }
        @AuraEnabled public List<DemoRecordDetail> projects { get; set; }
        /** True when a timesheet of the demo employee linked to the running user has no manager. */
        @AuraEnabled public Boolean userTimesheetsWithoutManager { get; set; }
        /** Only returned by getDemoData(). */
        @AuraEnabled public Blueprint blueprint { get; set; }
    }

    /** Every record the demo creates, before it exists. */
    public class Blueprint {
        /** Demo Employee first, then the child employees (isChild). */
        @AuraEnabled public List<DemoRecordDetail> employees { get; set; }
        @AuraEnabled public List<DemoRecordDetail> projects { get; set; }
        @AuraEnabled public Decimal hourlyRate { get; set; }
        /** The four weekly timesheets of every employee, with the line items each one gets. */
        @AuraEnabled public List<WeekPlan> weeks { get; set; }
    }

    public class WeekPlan {
        @AuraEnabled public String periodName { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Date endDate { get; set; }
        @AuraEnabled public String dateRange { get; set; }
        /** 0: stays New; 1 and 2: approved in that order (the second needs the absence balance of the first). */
        @AuraEnabled public Integer approvalRound { get; set; }
        @AuraEnabled public List<LineItemPlan> lineItems { get; set; }
    }

    public class LineItemPlan {
        @AuraEnabled public Date lineDate { get; set; }
        @AuraEnabled public Decimal duration { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public String activity { get; set; }
        @AuraEnabled public String type { get; set; }
        @AuraEnabled public String absenceCategory { get; set; }
        @AuraEnabled public String description { get; set; }
    }

    /** For the production warning. Cacheable: runs once per session. */
    @AuraEnabled(cacheable=true)
    public static Boolean isProductionOrg() {
        Organization org = [SELECT IsSandbox, TrialExpirationDate FROM Organization LIMIT 1];
        return !org.IsSandbox && org.TrialExpirationDate == null;
    }

    /** Everything the popup shows, plus the blueprint for its previews. 2 queries. */
    @AuraEnabled
    public static DemoState getDemoData() {
        try {
            List<Employee__c> emps = queryEmployees();
            DemoState state = toState(emps);
            state.projects = toProjectDetails(queryProjects());
            state.blueprint = buildBlueprint(emps);
            return state;
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    /**
     * Creates "Demo Employee" linked to the running user and, when includeChildren is true, the child
     * employees reporting to them. The Employee trigger rejects a second employee for the same user, so
     * this can only run once. 1 query.
     */
    @AuraEnabled
    public static DemoState createDemoEmployees(Boolean includeChildren) {
        try {
            List<Employee__c> emps = new List<Employee__c>();
            for (Employee__c emp : newDemoEmployees()) {
                if (includeChildren == true || emp.User__c != null) {
                    emps.add(emp);
                }
            }
            Database.insert(emps, AccessLevel.USER_MODE);
            return toState(queryEmployees());
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    /** Creates the demo projects that don't exist yet. 1 query: the result is built from memory. */
    @AuraEnabled
    public static DemoState createDemoProjects() {
        try {
            List<Project__c> projects = queryProjects();
            Set<String> existing = new Set<String>();
            for (Project__c proj : projects) {
                existing.add(proj.Name);
            }
            List<Project__c> toInsert = new List<Project__c>();
            for (Project__c proj : newDemoProjects()) {
                if (!existing.contains(proj.Name)) {
                    toInsert.add(proj);
                }
            }
            if (!toInsert.isEmpty()) {
                Database.insert(toInsert, AccessLevel.USER_MODE);
                projects.addAll(toInsert);
            }
            DemoState state = new DemoState();
            state.projects = toProjectDetails(sortByName(projects));
            return state;
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    /** Assigns every demo employee to every demo project, skipping pairs that exist. 3 queries. */
    @AuraEnabled
    public static DemoState createDemoProjectAssignments() {
        try {
            List<Employee__c> emps = queryEmployees();
            List<Project__c> projects = queryProjects();
            List<Project_Employee__c> toInsert = new List<Project_Employee__c>();
            for (Employee__c emp : emps) {
                Set<Id> assigned = new Set<Id>();
                for (Project_Employee__c pe : emp.Project_Employees__r) {
                    assigned.add(pe.Project__c);
                }
                for (Project__c proj : projects) {
                    if (!assigned.contains(proj.Id)) {
                        toInsert.add(new Project_Employee__c(Employee__c = emp.Id, Project__c = proj.Id, Hourly_Rate__c = HOURLY_RATE));
                    }
                }
            }
            if (!toInsert.isEmpty()) {
                Database.insert(toInsert, AccessLevel.USER_MODE);
            }
            return toState(queryEmployees());
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    /** Creates the blueprint's four weekly timesheets per employee (status New, no line items), skipping weeks that exist. 2 queries. */
    @AuraEnabled
    public static DemoState createDemoTimesheets() {
        try {
            List<Employee__c> emps = queryEmployees();
            if (emps.isEmpty()) {
                throw newAuraException('Create the demo employees first.');
            }
            List<WeekPlan> weeks = buildWeeks(emps);
            List<Timesheet__c> toInsert = new List<Timesheet__c>();
            for (Employee__c emp : emps) {
                Set<Date> existing = new Set<Date>();
                for (Timesheet__c ts : emp.Timesheet_Masters__r) {
                    existing.add(ts.Start_Date__c);
                }
                for (WeekPlan week : weeks) {
                    if (!existing.contains(week.startDate)) {
                        toInsert.add(new Timesheet__c(
                            Name = 'Timesheet for ' + String.valueOf(week.startDate) + ' to ' + String.valueOf(week.endDate),
                            Employee__c = emp.Id,
                            Manager__c = emp.Manager__c,
                            Start_Date__c = week.startDate,
                            End_Date__c = week.endDate,
                            Status__c = STATUS_NEW,
                            Is_Demo__c = true
                        ));
                    }
                }
            }
            if (!toInsert.isEmpty()) {
                Database.insert(toInsert, AccessLevel.USER_MODE);
            }
            return toState(queryEmployees());
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    /**
     * Adds the blueprint's line items to every New demo timesheet that has none, approves the timesheets of
     * approval rounds 1 and 2 in that order, then deactivates the legacy project to show hours logged against
     * an inactive project. 3 queries (plus what the triggers run).
     */
    @AuraEnabled
    public static DemoState createDemoLineItems() {
        try {
            List<Employee__c> emps = queryEmployees();
            List<Project__c> projects = queryProjects();
            Map<String, Project__c> projectsByName = new Map<String, Project__c>();
            for (Project__c proj : projects) {
                projectsByName.put(proj.Name, proj);
            }
            if (!projectsByName.keySet().containsAll(PROJECT_NAMES)) {
                throw newAuraException('Create the demo projects first.');
            }
            Map<Date, WeekPlan> weeksByStart = new Map<Date, WeekPlan>();
            for (WeekPlan week : buildWeeks(emps)) {
                weeksByStart.put(week.startDate, week);
            }

            List<Timesheet_Line_Item__c> items = new List<Timesheet_Line_Item__c>();
            List<Timesheet__c> approveFirst = new List<Timesheet__c>();
            List<Timesheet__c> approveSecond = new List<Timesheet__c>();
            for (Employee__c emp : emps) {
                Set<Id> withItems = new Set<Id>();
                for (Timesheet_Line_Item__c tli : emp.Time_Sheets__r) {
                    withItems.add(tli.Timesheet__c);
                }
                for (Timesheet__c ts : emp.Timesheet_Masters__r) {
                    WeekPlan week = weeksByStart.get(ts.Start_Date__c);
                    if (week == null || week.lineItems.isEmpty() || ts.Status__c != STATUS_NEW || withItems.contains(ts.Id)) {
                        continue;
                    }
                    for (LineItemPlan plan : week.lineItems) {
                        Project__c proj = projectsByName.get(plan.projectName);
                        items.add(new Timesheet_Line_Item__c(
                            Timesheet__c = ts.Id,
                            Employee__c = emp.Id,
                            Date__c = plan.lineDate,
                            Duration__c = plan.duration,
                            Description__c = plan.description,
                            Project__c = proj != null ? proj.Id : null,
                            Activity__c = plan.activity,
                            Type__c = plan.type,
                            Absence_Category__c = plan.absenceCategory
                        ));
                    }
                    if (week.approvalRound == 1) {
                        approveFirst.add(new Timesheet__c(Id = ts.Id, Status__c = STATUS_APPROVED));
                    } else if (week.approvalRound == 2) {
                        approveSecond.add(new Timesheet__c(Id = ts.Id, Status__c = STATUS_APPROVED));
                    }
                }
            }
            if (items.isEmpty()) {
                return toState(emps);
            }
            Database.insert(items, AccessLevel.USER_MODE);
            // Approve in two steps: the first approval sets the employee's absence balance, which
            // Prevent_Insufficient_Absence_Hours checks when the week with sick leave is approved.
            if (!approveFirst.isEmpty()) {
                Database.update(approveFirst, AccessLevel.USER_MODE);
            }
            if (!approveSecond.isEmpty()) {
                Database.update(approveSecond, AccessLevel.USER_MODE);
            }
            Project__c legacy = projectsByName.get(PROJECT_LEGACY);
            if (legacy.Active__c) {
                Database.update(new Project__c(Id = legacy.Id, Active__c = false), AccessLevel.USER_MODE);
                legacy.Active__c = false;
            }
            DemoState state = toState(queryEmployees());
            state.projects = toProjectDetails(projects);
            return state;
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    /**
     * Deletes every demo record of the running user: timesheets (their line items go with them, master-detail),
     * projects (their assignments go with them, master-detail), then employees. 2 queries.
     */
    @AuraEnabled
    public static void deleteDemoRecords() {
        try {
            List<Employee__c> emps = queryEmployees();
            List<Timesheet__c> timesheets = new List<Timesheet__c>();
            for (Employee__c emp : emps) {
                timesheets.addAll(emp.Timesheet_Masters__r);
            }
            deleteRecords(timesheets);
            deleteRecords(queryProjects());
            deleteRecords(emps);
        } catch (Exception e) {
            throw toAuraException(e);
        }
    }

    /** Query 1: the running user's demo employees with their assignments, timesheets and line items. */
    private static List<Employee__c> queryEmployees() {
        return [
            SELECT Id, Name, User__c, Manager__c, Manager__r.Name, Email__c, Employment_Type__c, Active__c,
                Accrual_Start_Date__c, Accrual_Divisor__c, Extra_Accrued_Hours__c, Extra_Absence_Hours__c,
                Total_Accrued_Hours__c, Total_Absence_Hours__c,
                (SELECT Id, Project__c, Project__r.Name, Hourly_Rate__c
                 FROM Project_Employees__r ORDER BY Project__r.Name),
                (SELECT Id, Start_Date__c, End_Date__c, Status__c, Total_Hours__c, Billable_Hours__c, Manager__c, Is_Demo__c
                 FROM Timesheet_Masters__r ORDER BY Start_Date__c),
                (SELECT Id, Timesheet__c, Date__c, Activity__c, Absence_Category__c, Project__r.Name, Duration__c
                 FROM Time_Sheets__r ORDER BY Date__c, Type__c)
            FROM Employee__c
            WHERE Is_Demo__c = true AND CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY CreatedDate, User__c NULLS LAST, Last_Name__c
        ];
    }

    /** Query 2: the running user's demo projects. A project with no assignments can't be reached from query 1. */
    private static List<Project__c> queryProjects() {
        return [
            SELECT Id, Name, Billable__c, Active__c, Start_Date__c, End_Date__c
            FROM Project__c
            WHERE Is_Demo__c = true AND CreatedById = :UserInfo.getUserId()
            WITH USER_MODE
            ORDER BY Name
        ];
    }

    /** The employee side of the popup (employees, assignments, timesheets with line items) from query 1. */
    private static DemoState toState(List<Employee__c> emps) {
        DemoState state = new DemoState();
        state.employees = new List<DemoRecordDetail>();
        state.projectEmployees = new List<DemoRecordDetail>();
        state.timesheets = new List<TimesheetDetail>();
        state.userTimesheetsWithoutManager = false;
        Map<Date, String> periodNames = new Map<Date, String>();
        for (WeekPlan week : buildWeeks(emps)) {
            periodNames.put(week.startDate, week.periodName);
        }
        for (Employee__c emp : emps) {
            DemoRecordDetail detail = toEmployeeDetail(emp, emp.Name, emp.Manager__r != null ? emp.Manager__r.Name : null);
            detail.assignmentCount = emp.Project_Employees__r.size();
            detail.timesheetCount = emp.Timesheet_Masters__r.size();
            state.employees.add(detail);

            for (Project_Employee__c pe : emp.Project_Employees__r) {
                DemoRecordDetail row = new DemoRecordDetail();
                row.recordId = pe.Id;
                row.employeeId = emp.Id;
                row.employeeName = emp.Name;
                row.projectId = pe.Project__c;
                row.projectName = pe.Project__r.Name;
                row.hourlyRate = pe.Hourly_Rate__c;
                state.projectEmployees.add(row);
            }

            Map<Id, List<TimesheetLineItemDetail>> itemsByTimesheet = new Map<Id, List<TimesheetLineItemDetail>>();
            for (Timesheet_Line_Item__c tli : emp.Time_Sheets__r) {
                if (!itemsByTimesheet.containsKey(tli.Timesheet__c)) {
                    itemsByTimesheet.put(tli.Timesheet__c, new List<TimesheetLineItemDetail>());
                }
                TimesheetLineItemDetail item = new TimesheetLineItemDetail();
                item.id = tli.Id;
                item.timesheetId = tli.Timesheet__c;
                item.lineDate = tli.Date__c;
                item.projectName = tli.Project__r != null ? tli.Project__r.Name : null;
                item.activity = tli.Activity__c;
                item.absenceCategory = tli.Absence_Category__c;
                item.duration = tli.Duration__c;
                itemsByTimesheet.get(tli.Timesheet__c).add(item);
            }
            for (Timesheet__c ts : emp.Timesheet_Masters__r) {
                if (emp.User__c == UserInfo.getUserId() && ts.Manager__c == null) {
                    state.userTimesheetsWithoutManager = true;
                }
                TimesheetDetail row = new TimesheetDetail();
                row.recordId = ts.Id;
                row.employeeId = emp.Id;
                row.employeeName = emp.Name;
                row.periodName = periodNames.containsKey(ts.Start_Date__c) ? periodNames.get(ts.Start_Date__c) : 'Weekly Timesheet';
                row.startDate = ts.Start_Date__c;
                row.dateRange = ts.Start_Date__c.format() + ' - ' + ts.End_Date__c.format();
                row.status = ts.Status__c;
                row.totalHours = ts.Total_Hours__c != null ? ts.Total_Hours__c : 0;
                row.billableHours = ts.Billable_Hours__c != null ? ts.Billable_Hours__c : 0;
                row.lineItems = itemsByTimesheet.containsKey(ts.Id) ? itemsByTimesheet.get(ts.Id) : new List<TimesheetLineItemDetail>();
                state.timesheets.add(row);
            }
        }
        return state;
    }

    /** Employee table row; name and manager are passed in because an unsaved employee has neither yet. */
    private static DemoRecordDetail toEmployeeDetail(Employee__c emp, String name, String manager) {
        DemoRecordDetail detail = new DemoRecordDetail();
        detail.recordId = emp.Id;
        detail.name = name;
        detail.manager = manager;
        detail.email = emp.Email__c;
        detail.employmentType = emp.Employment_Type__c;
        detail.active = emp.Active__c;
        detail.accrualStartDate = emp.Accrual_Start_Date__c;
        detail.accrualDivisor = emp.Accrual_Divisor__c;
        detail.extraAccruedHours = emp.Extra_Accrued_Hours__c;
        detail.extraAbsenceHours = emp.Extra_Absence_Hours__c;
        detail.totalAccruedHours = emp.Total_Accrued_Hours__c;
        detail.totalAbsenceHours = emp.Total_Absence_Hours__c;
        // A child employee is not linked to a user and reports to the running user.
        detail.isChild = emp.User__c == null && emp.Manager__c == UserInfo.getUserId();
        detail.assignmentCount = 0;
        detail.timesheetCount = 0;
        return detail;
    }

    private static List<DemoRecordDetail> toProjectDetails(List<Project__c> projects) {
        List<DemoRecordDetail> details = new List<DemoRecordDetail>();
        for (Project__c proj : projects) {
            DemoRecordDetail detail = new DemoRecordDetail();
            detail.recordId = proj.Id;
            detail.name = proj.Name;
            detail.active = proj.Active__c;
            detail.billable = proj.Billable__c;
            detail.startDate = proj.Start_Date__c;
            detail.endDate = proj.End_Date__c;
            details.add(detail);
        }
        return details;
    }

    private static List<Project__c> sortByName(List<Project__c> projects) {
        Map<String, Project__c> byName = new Map<String, Project__c>();
        for (Project__c proj : projects) {
            byName.put(proj.Name, proj);
        }
        List<String> names = new List<String>(byName.keySet());
        names.sort();
        List<Project__c> sorted = new List<Project__c>();
        for (String name : names) {
            sorted.add(byName.get(name));
        }
        return sorted;
    }

    private static Blueprint buildBlueprint(List<Employee__c> emps) {
        Blueprint blueprint = new Blueprint();
        blueprint.employees = new List<DemoRecordDetail>();
        for (Employee__c emp : newDemoEmployees()) {
            blueprint.employees.add(toEmployeeDetail(emp, emp.First_Name__c + ' ' + emp.Last_Name__c,
                emp.Manager__c != null ? UserInfo.getName() : null));
        }
        blueprint.projects = toProjectDetails(newDemoProjects());
        blueprint.hourlyRate = HOURLY_RATE;
        blueprint.weeks = buildWeeks(emps);
        return blueprint;
    }

    /** Demo Employee linked to the running user (no manager), and two child employees reporting to them. */
    private static List<Employee__c> newDemoEmployees() {
        Employee__c parent = newDemoEmployee(PARENT_LAST_NAME, null);
        parent.User__c = UserInfo.getUserId();
        return new List<Employee__c>{
            parent,
            newDemoEmployee(CHILD_LAST_NAME_PREFIX + 'A', UserInfo.getUserId()),
            newDemoEmployee(CHILD_LAST_NAME_PREFIX + 'B', UserInfo.getUserId())
        };
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

    /** Billable, legacy and non-billable projects, in name order. */
    private static List<Project__c> newDemoProjects() {
        List<Project__c> projects = new List<Project__c>();
        for (String name : PROJECT_NAMES) {
            projects.add(new Project__c(Name = name, Active__c = true, Billable__c = name == PROJECT_BILLABLE ? 'Yes' : 'No', Is_Demo__c = true));
        }
        return projects;
    }

    /**
     * The four weeks, Monday to Sunday, from two weeks before the demo's current week to the week after it:
     *  - two weeks ago: 8h a day on the legacy project, approved first
     *  - last week: 4h billable + 4h non-billable a day, sick on Tuesday, approved second
     *  - current week: the same, sick on Tuesday and Wednesday, stays New
     *  - next week: no line items, stays New
     * The names describe the weeks as they were when the timesheets were created.
     */
    private static List<WeekPlan> buildWeeks(List<Employee__c> emps) {
        Date thisWeek = getDemoWeek(emps);
        return new List<WeekPlan>{
            newWeek('Two Weeks Ago', thisWeek.addDays(-14), 1, true, new Set<Integer>()),
            newWeek('Last Week', thisWeek.addDays(-7), 2, false, new Set<Integer>{ 1 }),
            newWeek('Current Week', thisWeek, 0, false, new Set<Integer>{ 1, 2 }),
            newWeek('Next Week', thisWeek.addDays(7), 0, null, null)
        };
    }

    /**
     * Monday of the demo's current week. Once demo timesheets exist it is two weeks after the oldest one, so the
     * plan doesn't move when a later step (or a later visit) falls in another week; before that, this week.
     */
    private static Date getDemoWeek(List<Employee__c> emps) {
        Date oldest;
        for (Employee__c emp : emps) {
            for (Timesheet__c ts : emp.Timesheet_Masters__r) {
                if (ts.Is_Demo__c && (oldest == null || ts.Start_Date__c < oldest)) {
                    oldest = ts.Start_Date__c;
                }
            }
        }
        return oldest != null ? getWeekStart(oldest).addDays(14) : getWeekStart(Date.today());
    }

    /** legacyOnly null: no line items. Days in sickDays (0 = Monday) get an 8h Sick Leave absence. */
    private static WeekPlan newWeek(String periodName, Date startDate, Integer approvalRound, Boolean legacyOnly, Set<Integer> sickDays) {
        WeekPlan week = new WeekPlan();
        week.periodName = periodName;
        week.startDate = startDate;
        week.endDate = startDate.addDays(6);
        week.dateRange = startDate.format() + ' - ' + week.endDate.format();
        week.approvalRound = approvalRound;
        week.lineItems = new List<LineItemPlan>();
        if (legacyOnly == null) {
            return week;
        }
        for (Integer day = 0; day < 5; day++) {
            Date workDate = startDate.addDays(day);
            if (sickDays.contains(day)) {
                week.lineItems.add(newLineItem(workDate, 8, 'Demo - Sick leave', null, null, 'Absence', 'Sick Leave'));
            } else if (legacyOnly) {
                week.lineItems.add(newLineItem(workDate, 8, 'Demo - Project work', PROJECT_LEGACY, 'Development-Coding', 'Attendance', null));
            } else {
                week.lineItems.add(newLineItem(workDate, 4, 'Demo - Billable work', PROJECT_BILLABLE, 'Development-Coding', 'Attendance', null));
                week.lineItems.add(newLineItem(workDate, 4, 'Demo - Non-billable work', PROJECT_NON_BILLABLE, 'Meeting', 'Attendance', null));
            }
        }
        return week;
    }

    private static LineItemPlan newLineItem(Date lineDate, Decimal duration, String description, String projectName,
            String activity, String type, String absenceCategory) {
        LineItemPlan item = new LineItemPlan();
        item.lineDate = lineDate;
        item.duration = duration;
        item.description = description;
        item.projectName = projectName;
        item.activity = activity;
        item.type = type;
        item.absenceCategory = absenceCategory;
        return item;
    }

    /** Monday of the week containing the given date (1900-01-01 was a Monday). */
    private static Date getWeekStart(Date value) {
        return value.addDays(-Math.mod(Date.newInstance(1900, 1, 1).daysBetween(value), 7));
    }

    private static void deleteRecords(List<SObject> records) {
        if (!records.isEmpty()) {
            Database.delete(records, AccessLevel.USER_MODE);
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
