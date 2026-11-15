/**
 * @description Server side of the PTO tab (ptoApp and its sections).
 *              Roles come from custom permissions: PTO_Approve_Team (managers) and PTO_Admin_All (HR).
 *              A direct report is an active employee whose Manager__c is the running user AND whose
 *              user's ManagerId is the running user. Every method checks that the running user may act
 *              for the employee or request before reading or writing it; the reads themselves run through
 *              the without sharing PtoData class because Employee__c and PTO_Request__c are private to their owner.
 */
public with sharing class PtoController {

    public static final String PERM_APPROVE_TEAM = 'PTO_Approve_Team';
    public static final String PERM_ADMIN_ALL = 'PTO_Admin_All';
    public static final Integer PAGE_SIZE = 25;
    public static final Integer MAX_OFFSET = 2000;
    public static final Integer MAX_RANGE_DAYS = 62;
    public static final Integer MAX_TEAM = 200;
    public static final String SYNC_ERROR_LABEL = 'Approved, sync error';

    // ---------------------------------------------------------------- response types

    public class EmployeeInfo {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id managerId;
        @AuraEnabled public String managerName;
        @AuraEnabled public Boolean hasManager;
        @AuraEnabled public Decimal available;
        @AuraEnabled public Boolean accrualConfigured; // the timesheet balance rule applies to this employee
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

    public class DayLeave {
        @AuraEnabled public Id id;
        @AuraEnabled public String leaveDate;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal hours;
        @AuraEnabled public String status;
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestName;
    }

    public class DayItem {
        @AuraEnabled public Id id;
        @AuraEnabled public String leaveDate;
        @AuraEnabled public String type;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal hours;
    }

    public class DayRecords {
        @AuraEnabled public EmployeeInfo employee;
        @AuraEnabled public List<DayLeave> leaves;
        @AuraEnabled public List<DayItem> lineItems;
    }

    public class SubmitResponse {
        @AuraEnabled public Boolean success;
        @AuraEnabled public List<String> rowErrors;
        @AuraEnabled public List<String> warnings;
        @AuraEnabled public Id requestId;
        @AuraEnabled public String requestName;
        @AuraEnabled public Integer dayCount;
    }

    public class RequestRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String name;
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String employeeName;
        @AuraEnabled public String startDate;
        @AuraEnabled public String endDate;
        @AuraEnabled public Integer dayCount;
        @AuraEnabled public Decimal totalHours;
        @AuraEnabled public String status;
        @AuraEnabled public String displayStatus;
        @AuraEnabled public String notes;
        @AuraEnabled public String decisionNotes;
        @AuraEnabled public Boolean hasManager;
        @AuraEnabled public String approverName;
        @AuraEnabled public String decidedByName;
        @AuraEnabled public String decidedOn;
        @AuraEnabled public String submittedOn;
        @AuraEnabled public Integer syncErrorCount;
    }

    public class LineRow {
        @AuraEnabled public Id id;
        @AuraEnabled public String leaveDate;
        @AuraEnabled public String category;
        @AuraEnabled public Decimal hours;
        @AuraEnabled public String syncStatus;
        @AuraEnabled public String syncError;
    }

    public class RequestDetail {
        @AuraEnabled public RequestRow request;
        @AuraEnabled public List<LineRow> lines;
        @AuraEnabled public Decimal overBalanceHours; // set when this waiting request takes the balance below 0
    }

    public class PastPage {
        @AuraEnabled public List<RequestRow> rows;
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
        @AuraEnabled public Integer pendingRequests;
        @AuraEnabled public String nextLeaveDate;
        @AuraEnabled public Integer nextLeaveCount;
        // Days of the next leave whose request is still waiting for approval (0 = all approved).
        @AuraEnabled public Integer nextLeavePendingCount;
        @AuraEnabled public List<CategoryTotal> byCategory;
    }

    public class TeamRow {
        @AuraEnabled public Id employeeId;
        @AuraEnabled public String name;
        @AuraEnabled public List<Decimal> hours;
        @AuraEnabled public Decimal total;
    }

    public class TeamYear {
        @AuraEnabled public Integer year;
        @AuraEnabled public List<TeamRow> rows;
    }

    public class ActionResult {
        @AuraEnabled public Integer processed;
        @AuraEnabled public List<String> errors;
        @AuraEnabled public List<String> syncErrors;
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
            c.pendingCount = c.canApprove ? PtoData.pendingRequests(a.isHrAdmin).size() : 0;
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
            result.leaves = new List<DayLeave>();
            for (Leave_Line_Item__c l : PtoData.leaveInRange(emp.Id, startDate, endDate)) {
                DayLeave d = new DayLeave();
                d.id = l.Id;
                d.leaveDate = String.valueOf(l.Date__c);
                d.category = l.Absence_Category__c;
                d.hours = l.Duration__c;
                d.status = l.PTO_Request__r.Status__c;
                d.requestId = l.PTO_Request__c;
                d.requestName = l.PTO_Request__r.Name;
                result.leaves.add(d);
            }
            result.lineItems = new List<DayItem>();
            for (Timesheet_Line_Item__c li : PtoData.lineItemsInRange(emp.Id, startDate, endDate)) {
                DayItem r = new DayItem();
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
    public static SubmitResponse submitLeave(Id employeeId, String rowsJson, String notes) {
        try {
            Access a = new Access();
            Employee__c emp = a.requireEmployee(employeeId);

            List<Object> input = String.isBlank(rowsJson) ? new List<Object>() : (List<Object>) JSON.deserializeUntyped(rowsJson);
            if (input.isEmpty()) {
                throw new PtoException('Add at least one day.');
            }
            if (notes != null && notes.trim().length() > PtoRequestService.NOTES_MAX) {
                throw new PtoException('Keep the reason under 2,000 characters.');
            }
            Set<String> allowed = new Set<String>();
            for (CategoryOption o : categories()) {
                allowed.add(o.value);
            }

            List<Leave_Line_Item__c> lines = new List<Leave_Line_Item__c>();
            List<LeaveValidator.Row> rows = new List<LeaveValidator.Row>();
            List<String> rowErrors = new List<String>();
            Boolean hasError = false;
            for (Object o : input) {
                Map<String, Object> m = (Map<String, Object>) o;
                Date day = parseDate(m.get('date'));
                String category = m.get('category') == null ? null : String.valueOf(m.get('category'));
                Decimal hours = parseDecimal(m.get('hours'));
                String error = '';
                if (String.isNotBlank(category) && !allowed.contains(category)) {
                    error = category + ' can\'t be requested here.';
                }
                rowErrors.add(error);
                hasError = hasError || String.isNotBlank(error);
                lines.add(new Leave_Line_Item__c(Date__c = day, Absence_Category__c = category, Duration__c = hours));
                rows.add(new LeaveValidator.Row(emp.Id, day, category, hours));
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
            response.dayCount = 0;
            if (hasError) {
                response.success = false;
                return response;
            }

            Savepoint sp = Database.setSavepoint();
            try {
                PtoRequestService.SubmitResult result = PtoRequestService.submit(emp, lines, notes);
                response.requestId = result.request.Id;
                response.requestName = result.request.Name;
                response.dayCount = result.dayCount;
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
            } catch (PtoRequestService.PtoException serviceError) {
                Database.rollback(sp);
                response.success = false;
                response.warnings.add(serviceError.getMessage());
                return response;
            }

            response.success = true;
            if (emp.Manager__c == null) {
                response.warnings.add('This employee has no manager, so the request will stay pending until HR approves it.');
            }
            Decimal available = availableHours(emp, PtoData.pendingLeaveHours(new Set<Id>{ emp.Id }));
            if (available != null && available < 0) {
                response.warnings.add('This goes over the leave balance by ' + LeaveValidator.formatHours(-available) + ' hours.'
                    + (accrualConfigured(emp) ? ' Your timesheet for that week may not be submitted or approved until your manager adds extra accrued hours to your balance.' : ''));
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
            List<PTO_Request__c> records = PtoData.requestsForEmployee(emp.Id, PAGE_SIZE + 1, offset);
            PastPage page = new PastPage();
            page.offset = offset;
            page.hasMore = records.size() > PAGE_SIZE && offset + PAGE_SIZE < MAX_OFFSET;
            page.rows = new List<RequestRow>();
            for (Integer i = 0; i < Math.min(records.size(), PAGE_SIZE); i++) {
                page.rows.add(toRequestRow(records[i]));
            }
            return page;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static RequestDetail getRequestLines(Id requestId) {
        try {
            Access a = new Access();
            PTO_Request__c request = requestId == null ? null : PtoData.requestById(requestId);
            if (request == null) {
                throw new PtoException('That leave request doesn\'t exist.');
            }
            if (!a.canSee(request)) {
                throw new PtoException('You can only see leave requests of yourself and your direct reports.');
            }
            RequestDetail detail = new RequestDetail();
            detail.request = toRequestRow(request);
            detail.lines = new List<LineRow>();
            for (Leave_Line_Item__c l : PtoData.requestLines(request.Id)) {
                LineRow r = new LineRow();
                r.id = l.Id;
                r.leaveDate = String.valueOf(l.Date__c);
                r.category = l.Absence_Category__c;
                r.hours = l.Duration__c;
                r.syncStatus = l.Sync_Status__c;
                r.syncError = l.Sync_Error__c;
                detail.lines.add(r);
            }
            if (request.Status__c == LeaveValidator.STATUS_SUBMITTED) {
                Employee__c e = PtoData.employeeById(request.Employee__c);
                Decimal available = e == null || !accrualConfigured(e) ? null
                    : availableHours(e, PtoData.pendingLeaveHours(new Set<Id>{ e.Id }));
                detail.overBalanceHours = available != null && available < 0 ? -available : null;
            }
            return detail;
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
            o.pendingRequests = PtoData.pendingRequestCount(emp.Id);

            List<Leave_Line_Item__c> upcoming = PtoData.upcomingLeave(emp.Id);
            o.nextLeaveCount = 0;
            o.nextLeavePendingCount = 0;
            if (!upcoming.isEmpty()) {
                Date previous = upcoming[0].Date__c;
                o.nextLeaveDate = String.valueOf(previous);
                Set<Date> days = new Set<Date>();
                Set<Date> pendingDays = new Set<Date>();
                for (Leave_Line_Item__c l : upcoming) {
                    // Count the first run of leave days; a gap of more than 3 days (a weekend fits) ends it.
                    if (previous.daysBetween(l.Date__c) > 3) {
                        break;
                    }
                    days.add(l.Date__c);
                    if (l.PTO_Request__r.Status__c == LeaveValidator.STATUS_SUBMITTED) {
                        pendingDays.add(l.Date__c);
                    }
                    previous = l.Date__c;
                }
                o.nextLeaveCount = days.size();
                o.nextLeavePendingCount = pendingDays.size();
            }
            return o;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    /**
     * @description Approved leave hours of a year per weekday for the team: a manager's direct reports, or every
     *              active employee for HR. hours has 7 entries (Mon..Sun); total is the year.
     */
    @AuraEnabled
    public static TeamYear getTeamYear(Integer year) {
        try {
            Access a = new Access();
            if (!a.isManager && !a.isHrAdmin) {
                throw new PtoException('Only managers and HR can see team leave.');
            }
            TeamYear result = new TeamYear();
            result.year = year == null ? Date.today().year() : year;
            result.rows = new List<TeamRow>();
            Map<Id, TeamRow> rowsById = new Map<Id, TeamRow>();
            for (Employee__c e : a.isHrAdmin ? PtoData.allActiveEmployees(MAX_TEAM) : PtoData.directReports()) {
                TeamRow r = new TeamRow();
                r.employeeId = e.Id;
                r.name = e.Name;
                r.hours = new List<Decimal>{ 0, 0, 0, 0, 0, 0, 0 };
                r.total = 0;
                rowsById.put(e.Id, r);
                result.rows.add(r);
            }
            if (!rowsById.isEmpty()) {
                for (AggregateResult ar : PtoData.approvedWeekdayTotals(rowsById.keySet(), result.year)) {
                    TeamRow r = rowsById.get((Id) ar.get('employeeId'));
                    // DAY_IN_WEEK: 1 = Sunday .. 7 = Saturday; the chart runs Monday .. Sunday.
                    Integer weekday = (Integer) ar.get('weekday');
                    Decimal hours = (Decimal) ar.get('hours');
                    if (r != null && hours != null && weekday >= 1 && weekday <= 7) {
                        r.hours[Math.mod(weekday + 5, 7)] = hours;
                        r.total += hours;
                    }
                }
            }
            return result;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static List<RequestRow> getPendingApprovals() {
        try {
            Access a = new Access();
            if (!a.isManager && !a.isHrAdmin) {
                throw new PtoException('Only managers and HR can approve leave.');
            }
            List<RequestRow> rows = new List<RequestRow>();
            for (PTO_Request__c r : PtoData.pendingRequests(a.isHrAdmin)) {
                rows.add(toRequestRow(r));
            }
            return rows;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static ActionResult approveRequests(List<Id> requestIds) {
        try {
            return decide(requestIds, true, null);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static ActionResult rejectRequests(List<Id> requestIds, String reason) {
        try {
            if (String.isBlank(reason)) {
                throw new PtoException('Enter a reason before rejecting.');
            }
            return decide(requestIds, false, reason);
        } catch (Exception e) {
            throw fail(e);
        }
    }

    @AuraEnabled
    public static ActionResult retrySync(Id requestId) {
        try {
            Access a = new Access();
            if (!a.isHrAdmin) {
                throw new PtoException('Only HR can retry adding a request to the timesheet.');
            }
            PTO_Request__c request = requestId == null ? null : PtoData.requestById(requestId);
            if (request == null) {
                throw new PtoException('That leave request doesn\'t exist.');
            }
            if (request.Status__c != LeaveValidator.STATUS_APPROVED) {
                throw new PtoException(request.Name + ' isn\'t approved, so it has nothing to add to the timesheet.');
            }
            LeaveToLineItem.convertRequests(new Set<Id>{ request.Id });
            ActionResult result = new ActionResult();
            result.errors = new List<String>();
            result.syncErrors = new List<String>();
            result.processed = 0;
            for (Leave_Line_Item__c l : PtoData.requestLines(request.Id)) {
                if (l.Sync_Status__c == LeaveValidator.SYNC_ERROR) {
                    result.syncErrors.add(l.Absence_Category__c + ' on ' + String.valueOf(l.Date__c) + ': ' + l.Sync_Error__c);
                } else if (l.Sync_Status__c == LeaveValidator.SYNC_DONE) {
                    result.processed++;
                }
            }
            return result;
        } catch (Exception e) {
            throw fail(e);
        }
    }

    // ---------------------------------------------------------------- internals

    private static ActionResult decide(List<Id> requestIds, Boolean approve, String reason) {
        Access a = new Access();
        if (!a.isManager && !a.isHrAdmin) {
            throw new PtoException('Only managers and HR can approve or reject leave.');
        }
        ActionResult result = new ActionResult();
        result.errors = new List<String>();
        result.syncErrors = new List<String>();
        result.processed = 0;
        if (requestIds == null || requestIds.isEmpty()) {
            return result;
        }
        List<PTO_Request__c> allowed = new List<PTO_Request__c>();
        for (PTO_Request__c r : PtoData.requestsForDecision(new Set<Id>(requestIds))) {
            String label = r.Name + ' (' + r.Employee__r.Name + ')';
            if (r.Status__c != LeaveValidator.STATUS_SUBMITTED) {
                result.errors.add(label + ' is no longer waiting for approval.');
            } else if (!a.canDecide(r)) {
                result.errors.add('You can\'t approve or reject ' + label + '.');
            } else {
                allowed.add(r);
            }
        }
        if (allowed.isEmpty()) {
            return result;
        }
        PtoRequestService.DecisionResult decision = approve
            ? PtoRequestService.approve(allowed)
            : PtoRequestService.reject(allowed, reason);
        result.processed = decision.processed;
        result.errors.addAll(decision.errors);
        result.syncErrors.addAll(decision.syncErrors);
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

        Boolean canSee(PTO_Request__c r) {
            if (employee != null && r.Employee__c == employee.Id) {
                return true;
            }
            return isHrAdmin || (isManager && isDirectReport(r.Employee__r));
        }

        Boolean canDecide(PTO_Request__c r) {
            if (r.Employee__r.User__c == UserInfo.getUserId()) {
                return false;
            }
            return isHrAdmin || (isManager && isDirectReport(r.Employee__r));
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
        for (Schema.PicklistEntry p : Leave_Line_Item__c.Absence_Category__c.getDescribe().getPicklistValues()) {
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
        for (Schema.PicklistEntry p : Leave_Line_Item__c.Absence_Category__c.getDescribe().getPicklistValues()) {
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
        info.accrualConfigured = accrualConfigured(e);
        return info;
    }

    // The timesheet rule Prevent_Insufficient_Absence_Hours only applies when accrual is set up.
    private static Boolean accrualConfigured(Employee__c e) {
        return e.Accrual_Start_Date__c != null && e.Accrual_Divisor__c != null && e.Accrual_Divisor__c > 0;
    }

    /**
     * @description Leave balance minus leave that is submitted but not approved yet.
     */
    private static Decimal availableHours(Employee__c e, Map<Id, Decimal> pending) {
        Decimal balance = e.Total_Absence_Hours_Available__c == null ? 0 : e.Total_Absence_Hours_Available__c;
        Decimal waiting = pending != null && pending.containsKey(e.Id) ? pending.get(e.Id) : 0;
        return balance - waiting;
    }

    private static RequestRow toRequestRow(PTO_Request__c r) {
        RequestRow row = new RequestRow();
        row.id = r.Id;
        row.name = r.Name;
        row.employeeId = r.Employee__c;
        row.employeeName = r.Employee__r == null ? null : r.Employee__r.Name;
        row.startDate = r.Start_Date__c == null ? null : String.valueOf(r.Start_Date__c);
        row.endDate = r.End_Date__c == null ? null : String.valueOf(r.End_Date__c);
        row.dayCount = r.Day_Count__c == null ? 0 : r.Day_Count__c.intValue();
        row.totalHours = r.Total_Hours__c == null ? 0 : r.Total_Hours__c;
        row.status = r.Status__c;
        row.syncErrorCount = r.Sync_Error_Count__c == null ? 0 : r.Sync_Error_Count__c.intValue();
        row.displayStatus = r.Status__c == LeaveValidator.STATUS_APPROVED && row.syncErrorCount > 0 ? SYNC_ERROR_LABEL : r.Status__c;
        row.notes = r.Notes__c;
        row.decisionNotes = r.Decision_Notes__c;
        row.hasManager = r.Approver__c != null;
        row.approverName = r.Approver__r == null ? null : r.Approver__r.Name;
        row.decidedByName = r.Decided_By__r == null ? null : r.Decided_By__r.Name;
        row.decidedOn = r.Decided_On__c == null ? null : r.Decided_On__c.format('yyyy-MM-dd');
        row.submittedOn = r.CreatedDate == null ? null : r.CreatedDate.format('yyyy-MM-dd');
        return row;
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
