/**
 * @description Reads for the PTO tab that must see records the running user doesn't own (Employee__c
 *              and PTO_Request__c are private). Only PtoController calls this class, and it checks
 *              that the running user may see the employee or request before every call.
 */
public without sharing class PtoData {

    private static final Integer MAX_ROWS = 1000;

    public static Employee__c currentEmployee() {
        List<Employee__c> rows = [
            SELECT Id, Name, Active__c, Manager__c, Manager__r.Name, User__c, User__r.IsActive, User__r.ManagerId,
                Total_Absence_Hours_Available__c, Accrual_Start_Date__c, Accrual_Divisor__c
            FROM Employee__c
            WHERE User__c = :UserInfo.getUserId()
            ORDER BY Active__c DESC, CreatedDate DESC
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public static Employee__c employeeById(Id employeeId) {
        List<Employee__c> rows = [
            SELECT Id, Name, Active__c, Manager__c, Manager__r.Name, User__c, User__r.IsActive, User__r.ManagerId,
                Total_Absence_Hours_Available__c, Accrual_Start_Date__c, Accrual_Divisor__c
            FROM Employee__c
            WHERE Id = :employeeId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Active employees whose Manager__c is the running user and whose user's manager is too.
     */
    public static List<Employee__c> directReports() {
        Id me = UserInfo.getUserId();
        return [
            SELECT Id, Name, Active__c, Manager__c, Manager__r.Name, User__c, User__r.IsActive, User__r.ManagerId,
                Total_Absence_Hours_Available__c, Accrual_Start_Date__c, Accrual_Divisor__c
            FROM Employee__c
            WHERE Active__c = true AND Manager__c = :me AND User__r.ManagerId = :me
            ORDER BY Name
            LIMIT :MAX_ROWS
        ];
    }

    public static List<Employee__c> allActiveEmployees(Integer maxRows) {
        return [
            SELECT Id, Name, Active__c, Manager__c, Manager__r.Name, User__c, User__r.IsActive, User__r.ManagerId,
                Total_Absence_Hours_Available__c, Accrual_Start_Date__c, Accrual_Divisor__c
            FROM Employee__c
            WHERE Active__c = true
            ORDER BY Name
            LIMIT :maxRows
        ];
    }

    /**
     * @description Hours of leave that are not taken off the balance yet, per employee: days on Submitted
     *              requests, and days on Approved requests whose week's timesheet is not Approved yet (the
     *              balance only drops when that timesheet is approved).
     */
    public static Map<Id, Decimal> pendingLeaveHours(Set<Id> employeeIds) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT PTO_Request__r.Employee__c employeeId, SUM(Duration__c) hours
            FROM Leave_Line_Item__c
            WHERE PTO_Request__r.Employee__c IN :employeeIds
            AND (PTO_Request__r.Status__c = :LeaveValidator.STATUS_SUBMITTED
                OR (PTO_Request__r.Status__c = :LeaveValidator.STATUS_APPROVED
                    AND (Timesheet_Line_Item__c = null OR Timesheet_Line_Item__r.Timesheet__r.Status__c != 'Approved')))
            GROUP BY PTO_Request__r.Employee__c
        ]) {
            Decimal hours = (Decimal) ar.get('hours');
            result.put((Id) ar.get('employeeId'), hours == null ? 0 : hours);
        }
        return result;
    }

    /**
     * @description Leave days in a date range whose request is Submitted or Approved.
     */
    public static List<Leave_Line_Item__c> leaveInRange(Id employeeId, Date startDate, Date endDate) {
        return [
            SELECT Id, Date__c, Absence_Category__c, Duration__c, Sync_Status__c,
                PTO_Request__c, PTO_Request__r.Name, PTO_Request__r.Status__c
            FROM Leave_Line_Item__c
            WHERE PTO_Request__r.Employee__c = :employeeId
            AND Date__c >= :startDate AND Date__c <= :endDate
            AND PTO_Request__r.Status__c IN (:LeaveValidator.STATUS_SUBMITTED, :LeaveValidator.STATUS_APPROVED)
            ORDER BY Date__c, Absence_Category__c
            LIMIT :MAX_ROWS
        ];
    }

    public static List<Timesheet_Line_Item__c> lineItemsInRange(Id employeeId, Date startDate, Date endDate) {
        return [
            SELECT Id, Date__c, Type__c, Absence_Category__c, Duration__c
            FROM Timesheet_Line_Item__c
            WHERE Employee__c = :employeeId AND Date__c >= :startDate AND Date__c <= :endDate
            ORDER BY Date__c
            LIMIT :MAX_ROWS
        ];
    }

    /**
     * @description The employee's requests, newest first (by first day, then by when they were made).
     */
    public static List<PTO_Request__c> requestsForEmployee(Id employeeId, Integer rowLimit, Integer offsetRows) {
        return [
            SELECT Id, Name, Employee__c, Employee__r.Name, Status__c, Notes__c, Decision_Notes__c, Approver__c,
                Approver__r.Name, Decided_By__r.Name, Decided_On__c, Start_Date__c, End_Date__c, Day_Count__c,
                Total_Hours__c, Sync_Error_Count__c, CreatedDate
            FROM PTO_Request__c
            WHERE Employee__c = :employeeId
            ORDER BY Start_Date__c DESC NULLS LAST, CreatedDate DESC
            LIMIT :rowLimit
            OFFSET :offsetRows
        ];
    }

    public static PTO_Request__c requestById(Id requestId) {
        List<PTO_Request__c> rows = [
            SELECT Id, Name, Employee__c, Employee__r.Name, Employee__r.Manager__c, Employee__r.User__c,
                Employee__r.User__r.ManagerId, Status__c, Notes__c, Decision_Notes__c, Approver__c, Approver__r.Name,
                Decided_By__r.Name, Decided_On__c, Start_Date__c, End_Date__c, Day_Count__c, Total_Hours__c,
                Sync_Error_Count__c, CreatedDate
            FROM PTO_Request__c
            WHERE Id = :requestId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    public static List<Leave_Line_Item__c> requestLines(Id requestId) {
        return [
            SELECT Id, Date__c, Absence_Category__c, Duration__c, Sync_Status__c, Sync_Error__c
            FROM Leave_Line_Item__c
            WHERE PTO_Request__c = :requestId
            ORDER BY Date__c, Absence_Category__c
            LIMIT :MAX_ROWS
        ];
    }

    public static List<AggregateResult> yearTotals(Id employeeId, Integer year) {
        return [
            SELECT Absence_Category__c category, PTO_Request__r.Status__c status, SUM(Duration__c) hours
            FROM Leave_Line_Item__c
            WHERE PTO_Request__r.Employee__c = :employeeId
            AND CALENDAR_YEAR(Date__c) = :year
            AND PTO_Request__r.Status__c IN (:LeaveValidator.STATUS_SUBMITTED, :LeaveValidator.STATUS_APPROVED)
            GROUP BY Absence_Category__c, PTO_Request__r.Status__c
        ];
    }

    public static Integer pendingRequestCount(Id employeeId) {
        return [
            SELECT COUNT() FROM PTO_Request__c
            WHERE Employee__c = :employeeId AND Status__c = :LeaveValidator.STATUS_SUBMITTED
        ];
    }

    public static List<Leave_Line_Item__c> upcomingLeave(Id employeeId) {
        Date today = Date.today();
        return [
            SELECT Id, Date__c, PTO_Request__r.Status__c
            FROM Leave_Line_Item__c
            WHERE PTO_Request__r.Employee__c = :employeeId
            AND Date__c >= :today
            AND PTO_Request__r.Status__c IN (:LeaveValidator.STATUS_SUBMITTED, :LeaveValidator.STATUS_APPROVED)
            ORDER BY Date__c
            LIMIT 60
        ];
    }

    /**
     * @description Approved leave hours of a year per employee and day of the week (1 = Sunday .. 7 = Saturday).
     */
    public static List<AggregateResult> approvedWeekdayTotals(Set<Id> employeeIds, Integer year) {
        return [
            SELECT PTO_Request__r.Employee__c employeeId, DAY_IN_WEEK(Date__c) weekday, SUM(Duration__c) hours
            FROM Leave_Line_Item__c
            WHERE PTO_Request__r.Employee__c IN :employeeIds
            AND CALENDAR_YEAR(Date__c) = :year
            AND PTO_Request__r.Status__c = :LeaveValidator.STATUS_APPROVED
            GROUP BY PTO_Request__r.Employee__c, DAY_IN_WEEK(Date__c)
        ];
    }

    /**
     * @description Requests waiting for approval. HR sees everyone's; a manager sees direct reports' only.
     *              Nobody sees their own.
     */
    public static List<PTO_Request__c> pendingRequests(Boolean allEmployees) {
        Id me = UserInfo.getUserId();
        if (allEmployees) {
            return [
                SELECT Id, Name, Employee__c, Employee__r.Name, Status__c, Notes__c, Decision_Notes__c, Approver__c,
                    Approver__r.Name, Decided_By__r.Name, Decided_On__c, Start_Date__c, End_Date__c, Day_Count__c,
                    Total_Hours__c, Sync_Error_Count__c, CreatedDate
                FROM PTO_Request__c
                WHERE Status__c = :LeaveValidator.STATUS_SUBMITTED
                AND (Employee__r.User__c = null OR Employee__r.User__c != :me)
                ORDER BY Start_Date__c, Employee__r.Name
                LIMIT :MAX_ROWS
            ];
        }
        return [
            SELECT Id, Name, Employee__c, Employee__r.Name, Status__c, Notes__c, Decision_Notes__c, Approver__c,
                Approver__r.Name, Decided_By__r.Name, Decided_On__c, Start_Date__c, End_Date__c, Day_Count__c,
                Total_Hours__c, Sync_Error_Count__c, CreatedDate
            FROM PTO_Request__c
            WHERE Status__c = :LeaveValidator.STATUS_SUBMITTED
            AND Employee__r.Manager__c = :me
            AND Employee__r.User__r.ManagerId = :me
            AND Employee__r.User__c != :me
            ORDER BY Start_Date__c, Employee__r.Name
            LIMIT :MAX_ROWS
        ];
    }

    public static List<PTO_Request__c> requestsForDecision(Set<Id> requestIds) {
        return [
            SELECT Id, Name, Employee__c, Employee__r.Name, Employee__r.Manager__c, Employee__r.User__c,
                Employee__r.User__r.ManagerId, Status__c
            FROM PTO_Request__c
            WHERE Id IN :requestIds
        ];
    }
}
