/**
 * @description Reads for the PTO tab that must see records the running user doesn't own (Employee__c
 *              and Leave_and_Holiday__c are private). Only PtoController calls this class, and it checks
 *              that the running user may see the employee or record before every call.
 */
public without sharing class PtoData {

    private static final Integer MAX_ROWS = 1000;

    public static Employee__c currentEmployee() {
        List<Employee__c> rows = [
            SELECT Id, Name, Active__c, Manager__c, Manager__r.Name, User__c, User__r.IsActive, User__r.ManagerId,
                Total_Absence_Hours_Available__c
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
                Total_Absence_Hours_Available__c
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
                Total_Absence_Hours_Available__c
            FROM Employee__c
            WHERE Active__c = true AND Manager__c = :me AND User__r.ManagerId = :me
            ORDER BY Name
            LIMIT :MAX_ROWS
        ];
    }

    public static List<Employee__c> allActiveEmployees(Integer maxRows) {
        return [
            SELECT Id, Name, Active__c, Manager__c, Manager__r.Name, User__c, User__r.IsActive, User__r.ManagerId,
                Total_Absence_Hours_Available__c
            FROM Employee__c
            WHERE Active__c = true
            ORDER BY Name
            LIMIT :maxRows
        ];
    }

    /**
     * @description Submitted (not yet approved) leave hours per employee, holidays excluded.
     */
    public static Map<Id, Decimal> pendingLeaveHours(Set<Id> employeeIds) {
        Map<Id, Decimal> result = new Map<Id, Decimal>();
        for (AggregateResult ar : [
            SELECT Employee__c employeeId, SUM(Duration__c) hours
            FROM Leave_and_Holiday__c
            WHERE Employee__c IN :employeeIds
            AND Status__c = :LeaveValidator.STATUS_SUBMITTED
            AND Type__c = :LeaveValidator.TYPE_LEAVE
            GROUP BY Employee__c
        ]) {
            Decimal hours = (Decimal) ar.get('hours');
            result.put((Id) ar.get('employeeId'), hours == null ? 0 : hours);
        }
        return result;
    }

    public static List<Leave_and_Holiday__c> leaveInRange(Id employeeId, Date startDate, Date endDate) {
        return [
            SELECT Id, Employee__c, Employee__r.Name, Date__c, Type__c, Absence_Category__c, Duration__c,
                Status__c, Notes__c
            FROM Leave_and_Holiday__c
            WHERE Employee__c = :employeeId AND Date__c >= :startDate AND Date__c <= :endDate
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

    public static List<Leave_and_Holiday__c> pastLeave(Id employeeId, Integer rowLimit, Integer offsetRows) {
        return [
            SELECT Id, Employee__c, Employee__r.Name, Date__c, Type__c, Absence_Category__c, Duration__c,
                Status__c, Notes__c
            FROM Leave_and_Holiday__c
            WHERE Employee__c = :employeeId
            ORDER BY Date__c DESC, Absence_Category__c
            LIMIT :rowLimit
            OFFSET :offsetRows
        ];
    }

    public static List<AggregateResult> yearTotals(Id employeeId, Integer year) {
        return [
            SELECT Absence_Category__c category, Status__c status, SUM(Duration__c) hours
            FROM Leave_and_Holiday__c
            WHERE Employee__c = :employeeId
            AND CALENDAR_YEAR(Date__c) = :year
            AND Status__c IN (:LeaveValidator.STATUS_SUBMITTED, :LeaveValidator.STATUS_APPROVED)
            GROUP BY Absence_Category__c, Status__c
        ];
    }

    public static List<Leave_and_Holiday__c> upcomingLeave(Id employeeId) {
        Date today = Date.today();
        return [
            SELECT Id, Date__c
            FROM Leave_and_Holiday__c
            WHERE Employee__c = :employeeId
            AND Date__c >= :today
            AND Type__c = :LeaveValidator.TYPE_LEAVE
            AND Status__c IN (:LeaveValidator.STATUS_SUBMITTED, :LeaveValidator.STATUS_APPROVED)
            ORDER BY Date__c
            LIMIT 60
        ];
    }

    public static List<AggregateResult> weekTotals(Set<Id> employeeIds, Date startDate, Date endDate) {
        return [
            SELECT Employee__c employeeId, Date__c day, SUM(Duration__c) hours
            FROM Leave_and_Holiday__c
            WHERE Employee__c IN :employeeIds
            AND Date__c >= :startDate AND Date__c <= :endDate
            AND Status__c IN (:LeaveValidator.STATUS_SUBMITTED, :LeaveValidator.STATUS_APPROVED)
            GROUP BY Employee__c, Date__c
        ];
    }

    /**
     * @description Leave waiting for approval. HR sees everyone's; a manager sees direct reports' only.
     *              Nobody sees their own.
     */
    public static List<Leave_and_Holiday__c> pendingApprovals(Boolean allEmployees) {
        Id me = UserInfo.getUserId();
        if (allEmployees) {
            return [
                SELECT Id, Employee__c, Employee__r.Name, Date__c, Type__c, Absence_Category__c, Duration__c,
                    Status__c, Notes__c
                FROM Leave_and_Holiday__c
                WHERE Status__c = :LeaveValidator.STATUS_SUBMITTED
                AND (Employee__r.User__c = null OR Employee__r.User__c != :me)
                ORDER BY Date__c, Employee__r.Name
                LIMIT :MAX_ROWS
            ];
        }
        return [
            SELECT Id, Employee__c, Employee__r.Name, Date__c, Type__c, Absence_Category__c, Duration__c,
                Status__c, Notes__c
            FROM Leave_and_Holiday__c
            WHERE Status__c = :LeaveValidator.STATUS_SUBMITTED
            AND Employee__r.Manager__c = :me
            AND Employee__r.User__r.ManagerId = :me
            AND Employee__r.User__c != :me
            ORDER BY Date__c, Employee__r.Name
            LIMIT :MAX_ROWS
        ];
    }

    public static List<Leave_and_Holiday__c> leaveForDecision(Set<Id> leaveIds) {
        return [
            SELECT Id, Employee__c, Employee__r.Name, Employee__r.Manager__c, Employee__r.User__c,
                Employee__r.User__r.ManagerId, Date__c, Type__c, Absence_Category__c, Duration__c, Status__c, Notes__c
            FROM Leave_and_Holiday__c
            WHERE Id IN :leaveIds
        ];
    }
}
