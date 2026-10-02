/**
 * @description Server side of the PTO tab (ptoApp and its sections).
 *              Roles come from custom permissions: PTO_Approve_Team (managers) and PTO_Admin_All (HR).
 *              A direct report is an active employee whose Manager__c is the running user AND whose
 *              user's ManagerId is the running user. Every method checks that the running user may act
 *              for the employee or record before reading or writing it; the reads themselves run through
 *              the without sharing PtoData class because Employee__c and leave records are private to their owner.
 */
public with sharing class PtoController {

    public static final String PERM_APPROVE_TEAM = 'PTO_Approve_Team';
    public static final String PERM_ADMIN_ALL = 'PTO_Admin_All';
    public static final Integer PAGE_SIZE = 25;
    public static final Integer MAX_OFFSET = 2000;
    public static final Integer MAX_RANGE_DAYS = 62;
    public static final Integer MAX_TEAM = 200;
    private static final Date REFERENCE_MONDAY = Date.newInstance(1900, 1, 1);

    // ---------------------------------------------------------------- response types

    public class EmployeeInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id managerId;
        @AuraEnabled public String managerName;
        @AuraEnabled public Boolean hasManager;
        @AuraEnabled public Decimal available;
    }

    public class CategoryOption {
        @AuraEnabled public String value;
        @AuraEnabled public String label;
        @AuraEnabled public Decimal maxHours;
    }

    public class Context {
        @AuraEnabled public EmployeeInfo employee;
        @AuraEnabled public Boolean isManager;
        @AuraEnabled public Boolean isHrAdmin;
        @AuraEnabled public Boolean canApprove;
        @AuraEnabled public List<EmployeeInfo> employees;
        @AuraEnabled public List<CategoryOption> categories;
        @AuraEnabled public Decimal dailyMax;
        @AuraEnabled public String today;
        @AuraEnabled public Integer pendingCount;
    }

    public class LeaveRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String leaveDate;
        @AuraEnabled public String type;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal hours;
        @AuraEnabled public String status;
        @AuraEnabled public String displayStatus;
        @AuraEnabled public String notes;
    }

    public class LineRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String leaveDate;
        @AuraEnabled public String type;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal hours;
    }

    public class DayRecords {
        @AuraEnabled public EmployeeInfo employee;
        @AuraEnabled public List<LeaveRow> leaves;
        @AuraEnabled public List<LineRow> lineItems;
    }

    public class SubmitResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public List<String> rowErrors;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public Integer submittedCount;
        @AuraEnabled public Integer resubmittedCount;
    }

    public class PastPage {
        @AuraEnabled public List<LeaveRow> rows;
        @AuraEnabled public Boolean hasMore;
        @AuraEnabled public Integer offset;
    }

    public class CategoryTotal {
        @AuraEnabled public String category;
        @AuraEnabled public Decimal approved;
        @AuraEnabled public Decimal submitted;
    }

    public class Overview {
        @AuraEnabled public Decimal available;
        @AuraEnabled public Decimal takenHours;
        @AuraEnabled public Decimal pendingHours;
        @AuraEnabled public String nextLeaveDate;
        @AuraEnabled public Integer nextLeaveCount;
        @AuraEnabled public List<CategoryTotal> byCategory;
    }

    public class TeamRow {
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String name;
        @AuraEnabled public List<Decimal> hours;
    }

    public class TeamWeek {
        @AuraEnabled public String weekStart;
        @AuraEnabled public List<String> days;
        @AuraEnabled public List<TeamRow> rows;
    }

    public class ActionResult {
        @AuraEnabled public Integer processed;
        @AuraEnabled public List<String> errors;
    }

    // ---------------------------------------------------------------- endpoints

    @AuraEnabled
    public static Context getContext() {
        try {
            Access a = new Access();
            Context c = new Context();
            c.employee = a.employee == null ? null : toInfo(a.employee, PtoData.pendingLeaveHours(new Set<Id>{ a.employee.Id }));
            c.isManager = a.isManager;
            c.isHrAdmin = a.isHrAdmin;
            c.canApprove = a.isManager || a.isHrAdmin;
            c.employees = new List<EmployeeInfo>();
            List<Employee__c> others = a.isHrAdmin ? PtoData.allActiveEmployees(2000)
                : (a.isManager ? PtoData.directReports() : new List<Employee__c>());
            for (Employee__c e : others) {
                if (a.employee == null || e.Id != a.employee.Id) {
                    c.employees.add(toInfo(e, null));
                }
            }
            c.categories = categories();
            c.dailyMax = LeaveValidator.dailyMax();
            c.today = String.valueOf(Date.today());
            c.pendingCount = c.canApprove ? PtoData.pendingApprovals(a.isHrAdmin).size() : 0;
            return c;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static DayRecords getDayRecords(Id employeeId, Date startDate, Date endDate) {
        try {
            Access a = new Access();
            Employee__c emp = a.requireEmployee(employeeId);
            if (startDate == null || endDate == null || endDate < startDate) {
                throw new PtoException('Pick a start date on or before the end date.');
            }
            if (startDate.daysBetween(endDate) > MAX_RANGE_DAYS) {
                throw new PtoException('Pick a range of ' + MAX_RANGE_DAYS + ' days or fewer.');
            }
            DayRecords result = new DayRecords();
            result.employee = toInfo(emp, PtoData.pendingLeaveHours(new Set<Id>{ emp.Id }));
            result.leaves = new List<LeaveRow>();
            for (Leave_and_Holiday__c l : PtoData.leaveInRange(emp.Id, startDate, endDate)) {
                result.leaves.add(toRow(l));
            }
            result.lineItems = new List<LineRow>();
            for (Timesheet_Line_Item__c li : PtoData.lineItemsInRange(emp.Id, startDate, endDate)) {
                LineRow r = new LineRow();
                r.id = li.Id;
                r.leaveDate = String.valueOf(li.Date__c);
                r.type = li.Type__c;
                r.category = li.Absence_Category__c;
                r.hours = li.Duration__c;
                result.lineItems.add(r);
            }
            return result;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static SubmitResponse submitLeave(Id employeeId, String rowsJson) {
        try {
            Access a = new Access();
            Employee__c emp = a.requireEmployee(employeeId);

            List<Object> input = String.isBlank(rowsJson) ? new List<Object>() : (List<Object>) JSON.deserializeUntyped(rowsJson);
            if (input.isEmpty()) {
                throw new PtoException('Add at least one day.');
            }
            Set<String> allowed = new Set<String>();
            for (CategoryOption o : categories()) {
                allowed.add(o.value);
            }

            List<Leave_and_Holiday__c> records = new List<Leave_and_Holiday__c>();
            List<LeaveValidator.Row> rows = new List<LeaveValidator.Row>();
            List<String> rowErrors = new List<String>();
            Boolean hasError = false;
            Decimal newHours = 0;
            for (Object o : input) {
                Map<String, Object> m = (Map<String, Object>) o;
                Date day = parseDate(m.get('date'));
                String category = m.get('category') == null ? null : String.valueOf(m.get('category'));
                Decimal hours = parseDecimal(m.get('hours'));
                String notes = m.get('notes') == null ? null : String.valueOf(m.get('notes')).trim();
                String error = '';
                if (String.isNotBlank(category) && !allowed.contains(category)) {
                    error = category + ' can\'t be requested here.';
                } else if (notes != null && notes.length() > 1000) {
                    error = 'Keep the note under 1,000 characters.';
                }
                rowErrors.add(error);
                hasError = hasError || String.isNotBlank(error);
                records.add(new Leave_and_Holiday__c(
                    Date__c = day,
                    Absence_Category__c = category,
                    Duration__c = hours,
                    Notes__c = String.isBlank(notes) ? null : notes
                ));
                rows.add(new LeaveValidator.Row(emp.Id, day, category, hours, null));
                newHours += hours == null ? 0 : hours;
            }

            List<String> checks = LeaveValidator.validate(rows);
            for (Integer i = 0; i < checks.size(); i++) {
                if (String.isBlank(rowErrors[i]) && String.isNotBlank(checks[i])) {
                    rowErrors[i] = checks[i];
                    hasError = true;
                }
            }

            SubmitResponse response = new SubmitResponse();
            response.rowErrors = rowErrors;
            response.warnings = new List<String>();
            response.submittedCount = 0;
            response.resubmittedCount = 0;
            if (hasError) {
                response.success = false;
                return response;
            }

            Savepoint sp = Database.setSavepoint();
            try {
                LeaveService.SubmitResult result = LeaveService.submit(emp, records);
                response.submittedCount = result.submitted;
                response.resubmittedCount = result.resubmitted;
            } catch (DmlException dmlError) {
                Database.rollback(sp);
                response.success = false;
                for (Integer i = 0; i < dmlError.getNumDml(); i++) {
                    Integer index = dmlError.getDmlIndex(i);
                    if (index != null && index < rowErrors.size()) {
                        rowErrors[index] = dmlError.getDmlMessage(i);
                    }
                }
                if (dmlError.getNumDml() == 0) {
                    response.warnings.add(dmlError.getMessage());
                }
                return response;
            }

            response.success = true;
            if (emp.Manager__c == null) {
                response.warnings.add('This employee has no manager, so the request will stay pending until HR approves it.');
            }
            Decimal available = availableHours(emp, PtoData.pendingLeaveHours(new Set<Id>{ emp.Id }));
            if (available != null && available < 0) {
                response.warnings.add('This goes over the leave balance by ' + LeaveValidator.formatHours(-available) + ' hours.');
            }
            return response;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static PastPage getPast(Id employeeId, Integer offsetRows) {
        try {
            Access a = new Access();
            Employee__c emp = a.requireEmployee(employeeId);
            Integer offset = offsetRows == null || offsetRows < 0 ? 0 : Math.min(offsetRows, MAX_OFFSET);
            List<Leave_and_Holiday__c> records = PtoData.pastLeave(emp.Id, PAGE_SIZE + 1, offset);
            PastPage page = new PastPage();
            page.offset = offset;
            page.hasMore = records.size() > PAGE_SIZE && offset + PAGE_SIZE < MAX_OFFSET;
            page.rows = new List<LeaveRow>();
            for (Integer i = 0; i < Math.min(records.size(), PAGE_SIZE); i++) {
                page.rows.add(toRow(records[i]));
            }
            return page;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static Overview getOverview(Id employeeId, Integer year) {
        try {
            Access a = new Access();
            Employee__c emp = a.requireEmployee(employeeId);
            Integer y = year == null ? Date.today().year() : year;

            Overview o = new Overview();
            o.takenHours = 0;
            o.pendingHours = 0;
            Map<String, CategoryTotal> totals = new Map<String, CategoryTotal>();
            for (String category : picklistValues()) {
                CategoryTotal t = new CategoryTotal();
                t.category = category;
                t.approved = 0;
                t.submitted = 0;
                totals.put(category, t);
            }
            for (AggregateResult ar : PtoData.yearTotals(emp.Id, y)) {
                String category = (String) ar.get('category');
                String status = (String) ar.get('status');
                Decimal hours = (Decimal) ar.get('hours');
                hours = hours == null ? 0 : hours;
                CategoryTotal t = totals.get(category);
                if (t == null) {
                    continue;
                }
                if (status == LeaveValidator.STATUS_APPROVED) {
                    t.approved += hours;
                    o.takenHours += hours;
                } else {
                    t.submitted += hours;
                    o.pendingHours += hours;
                }
            }
            o.byCategory = new List<CategoryTotal>();
            for (CategoryTotal t : totals.values()) {
                if (t.approved > 0 || t.submitted > 0) {
                    o.byCategory.add(t);
                }
            }
            o.available = availableHours(emp, PtoData.pendingLeaveHours(new Set<Id>{ emp.Id }));

            List<Leave_and_Holiday__c> upcoming = PtoData.upcomingLeave(emp.Id);
            o.nextLeaveCount = 0;
            if (!upcoming.isEmpty()) {
                Date previous = upcoming[0].Date__c;
                o.nextLeaveDate = String.valueOf(previous);
                Set<Date> days = new Set<Date>();
                for (Leave_and_Holiday__c l : upcoming) {
                    // Count the first run of leave days; a gap of more than 3 days (a weekend fits) ends it.
                    if (previous.daysBetween(l.Date__c) > 3) {
                        break;
                    }
                    days.add(l.Date__c);
                    previous = l.Date__c;
                }
                o.nextLeaveCount = days.size();
            }
            return o;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static TeamWeek getTeamWeek(Date weekStart) {
        try {
            Access a = new Access();
            if (!a.isManager && !a.isHrAdmin) {
                throw new PtoException('Only managers and HR can see the team week.');
            }
            Date monday = mondayOf(weekStart == null ? Date.today() : weekStart);
            List<Employee__c> employees = a.isHrAdmin ? PtoData.allActiveEmployees(MAX_TEAM) : PtoData.directReports();

            TeamWeek week = new TeamWeek();
            week.weekStart = String.valueOf(monday);
            week.days = new List<String>();
            for (Integer i = 0; i < 7; i++) {
                week.days.add(String.valueOf(monday.addDays(i)));
            }
            Map<Id, TeamRow> rowsById = new Map<Id, TeamRow>();
            week.rows = new List<TeamRow>();
            for (Employee__c e : employees) {
                TeamRow r = new TeamRow();
                r.employeeId = e.Id;
                r.name = e.Name;
                r.hours = new List<Decimal>{ 0, 0, 0, 0, 0, 0, 0 };
                rowsById.put(e.Id, r);
                week.rows.add(r);
            }
            if (!rowsById.isEmpty()) {
                for (AggregateResult ar : PtoData.weekTotals(rowsById.keySet(), monday, monday.addDays(6))) {
                    TeamRow r = rowsById.get((Id) ar.get('employeeId'));
                    Integer index = monday.daysBetween((Date) ar.get('day'));
                    Decimal hours = (Decimal) ar.get('hours');
                    if (r != null && index >= 0 && index < 7) {
                        r.hours[index] = hours == null ? 0 : hours;
                    }
                }
            }
            return week;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static List<LeaveRow> getPendingApprovals() {
        try {
            Access a = new Access();
            if (!a.isManager && !a.isHrAdmin) {
                throw new PtoException('Only managers and HR can approve leave.');
            }
            List<LeaveRow> rows = new List<LeaveRow>();
            for (Leave_and_Holiday__c l : PtoData.pendingApprovals(a.isHrAdmin)) {
                rows.add(toRow(l));
            }
            return rows;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static ActionResult approveLeave(List<Id> leaveIds) {
        try {
            return decide(leaveIds, true, null);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static ActionResult rejectLeave(List<Id> leaveIds, String reason) {
        try {
            if (String.isBlank(reason)) {
                throw new PtoException('Enter a reason before rejecting.');
            }
            return decide(leaveIds, false, reason);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    // ---------------------------------------------------------------- internals

    private static ActionResult decide(List<Id> leaveIds, Boolean approve, String reason) {
        Access a = new Access();
        if (!a.isManager && !a.isHrAdmin) {
            throw new PtoException('Only managers and HR can approve or reject leave.');
        }
        ActionResult result = new ActionResult();
        result.errors = new List<String>();
        result.processed = 0;
        if (leaveIds == null || leaveIds.isEmpty()) {
            return result;
        }
        List<Leave_and_Holiday__c> allowed = new List<Leave_and_Holiday__c>();
        for (Leave_and_Holiday__c l : PtoData.leaveForDecision(new Set<Id>(leaveIds))) {
            String label = l.Employee__r.Name + ', ' + l.Absence_Category__c + ' on ' + String.valueOf(l.Date__c);
            if (l.Status__c != LeaveValidator.STATUS_SUBMITTED) {
                result.errors.add(label + ' is no longer waiting for approval.');
            } else if (!a.canDecide(l)) {
                result.errors.add('You can\'t approve or reject ' + label + '.');
            } else {
                allowed.add(l);
            }
        }
        if (allowed.isEmpty()) {
            return result;
        }
        List<String> errors = approve ? LeaveService.approve(allowed) : LeaveService.reject(allowed, reason);
        result.errors.addAll(errors);
        result.processed = allowed.size() - errors.size();
        return result;
    }

    /**
     * @description The running user's employee record and PTO role.
     */
    private class Access {
        Employee__c employee;
        Boolean isManager;
        Boolean isHrAdmin;

        Access() {
            employee = PtoData.currentEmployee();
            isHrAdmin = hasPermission(PERM_ADMIN_ALL);
            isManager = hasPermission(PERM_APPROVE_TEAM);
        }

        /**
         * @description The employee the user may act for: blank = self; others need HR, or a manager
         *              with that employee as a direct report.
         */
        Employee__c requireEmployee(Id employeeId) {
            if (employeeId == null || (employee != null && employeeId == employee.Id)) {
                if (employee == null) {
                    throw new PtoException('Your user isn\'t linked to an employee record. Ask HR to set User on your Employee record.');
                }
                return employee;
            }
            Employee__c other = PtoData.employeeById(employeeId);
            if (other == null) {
                throw new PtoException('That employee doesn\'t exist.');
            }
            if (isHrAdmin || (isManager && isDirectReport(other))) {
                return other;
            }
            throw new PtoException('You can only manage leave for yourself and your direct reports.');
        }

        Boolean canDecide(Leave_and_Holiday__c l) {
            if (l.Employee__r.User__c == UserInfo.getUserId()) {
                return false;
            }
            return isHrAdmin || (isManager && isDirectReport(l.Employee__r));
        }
    }

    private static Boolean isDirectReport(Employee__c e) {
        Id me = UserInfo.getUserId();
        return e != null && e.Manager__c == me && e.User__c != null && e.User__r.ManagerId == me;
    }

    /**
     * @description Custom permissions are checked with and without the package namespace so the code
     *              works in the packaging org, a namespaced scratch org and a subscriber org.
     */
    public static Boolean hasPermission(String name) {
        if (FeatureManagement.checkPermission(name)) {
            return true;
        }
        String className = PtoController.class.getName();
        if (className.contains('.')) {
            return FeatureManagement.checkPermission(className.substringBefore('.') + '__' + name);
        }
        return false;
    }

    private static List<CategoryOption> categories() {
        List<CategoryOption> options = new List<CategoryOption>();
        for (Schema.PicklistEntry p : Leave_and_Holiday__c.Absence_Category__c.getDescribe().getPicklistValues()) {
            if (!p.isActive() || p.getValue() == LeaveValidator.CATEGORY_HOLIDAY) {
                continue;
            }
            CategoryOption o = new CategoryOption();
            o.value = p.getValue();
            o.label = p.getLabel();
            o.maxHours = LeaveValidator.maxHours(p.getValue());
            options.add(o);
        }
        return options;
    }

    private static List<String> picklistValues() {
        List<String> values = new List<String>();
        for (Schema.PicklistEntry p : Leave_and_Holiday__c.Absence_Category__c.getDescribe().getPicklistValues()) {
            values.add(p.getValue());
        }
        return values;
    }

    private static EmployeeInfo toInfo(Employee__c e, Map<Id, Decimal> pending) {
        EmployeeInfo info = new EmployeeInfo();
        info.id = e.Id;
        info.name = e.Name;
        info.managerId = e.Manager__c;
        info.managerName = e.Manager__r == null ? null : e.Manager__r.Name;
        info.hasManager = e.Manager__c != null;
        info.available = pending == null ? null : availableHours(e, pending);
        return info;
    }

    /**
     * @description Leave balance minus leave that is submitted but not approved yet (holidays excluded).
     */
    private static Decimal availableHours(Employee__c e, Map<Id, Decimal> pending) {
        Decimal balance = e.Total_Absence_Hours_Available__c == null ? 0 : e.Total_Absence_Hours_Available__c;
        Decimal waiting = pending != null && pending.containsKey(e.Id) ? pending.get(e.Id) : 0;
        return balance - waiting;
    }

    private static LeaveRow toRow(Leave_and_Holiday__c l) {
        LeaveRow r = new LeaveRow();
        r.id = l.Id;
        r.employeeId = l.Employee__c;
        r.employeeName = l.Employee__r == null ? null : l.Employee__r.Name;
        r.leaveDate = String.valueOf(l.Date__c);
        r.type = l.Type__c;
        r.category = l.Absence_Category__c;
        r.hours = l.Duration__c;
        r.status = l.Status__c;
        r.notes = l.Notes__c;
        if (l.Status__c == LeaveValidator.STATUS_NEW) {
            r.displayStatus = LeaveService.isConversionError(l.Notes__c) ? 'Conversion error' : 'Rejected';
        } else {
            r.displayStatus = l.Status__c;
        }
        return r;
    }

    private static Date mondayOf(Date d) {
        Integer offset = Math.mod(REFERENCE_MONDAY.daysBetween(d), 7);
        if (offset < 0) {
            offset += 7;
        }
        return d.addDays(-offset);
    }

    private static Date parseDate(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        try {
            return Date.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal parseDecimal(Object value) {
        if (value == null || String.isBlank(String.valueOf(value))) {
            return null;
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @description Readable error for the caller. AuraHandledException may only be thrown in a Lightning
     *              (Aura) request, so other callers (REST, Apex) get a PtoException with the same message.
     */
    private static Exception fail(Exception e) {
        String message = e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage();
        Quiddity q = Request.getCurrent().getQuiddity();
        if (q == Quiddity.AURA || q == Quiddity.VF || Test.isRunningTest()) {
            AuraHandledException ae = new AuraHandledException(message);
            ae.setMessage(message);
            return ae;
        }
        return new PtoException(message);
    }

    public class PtoException extends Exception {}

}
