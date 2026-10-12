/**
 * @description Shared rule set for leave days. Used by the Leave_Line_Item__c trigger, the PTO tab
 *              and the Timesheet_Line_Item__c trigger, so a leave day and an absence line item are
 *              checked by the same rules. Leave counts while its PTO Request is Submitted or Approved;
 *              a Rejected request no longer holds its days.
 *              Runs without sharing on purpose: a manager applying for a direct report must see that
 *              employee's existing leave and line items to validate the request. It only reads.
 */
public without sharing class LeaveValidator {

    public static final String STATUS_SUBMITTED = 'Submitted';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_REJECTED = 'Rejected';
    public static final String CATEGORY_HOLIDAY = 'Holiday';
    public static final String LINE_TYPE_ABSENCE = 'Absence';
    public static final String SYNC_WAITING = 'Waiting for timesheet';
    public static final String SYNC_DONE = 'On timesheet';
    public static final String SYNC_ERROR = 'Error';
    public static final Decimal DEFAULT_CATEGORY_MAX = 8;
    public static final Decimal DEFAULT_DAILY_MAX = 24;

    private static Timesheet_Default_Value__mdt cachedSettings;

    /**
     * @description One leave day to check.
     */
    public class Row {
        public Id employeeId;
        public Date day;
        public String category;
        public Decimal hours;

        public Row(Id employeeId, Date day, String category, Decimal hours) {
            this.employeeId = employeeId;
            this.day = day;
            this.category = category;
            this.hours = hours;
        }
    }

    public static Timesheet_Default_Value__mdt settings() {
        if (cachedSettings == null) {
            cachedSettings = Timesheet_Default_Value__mdt.getInstance('Default_Values');
            if (cachedSettings == null) {
                cachedSettings = new Timesheet_Default_Value__mdt();
            }
        }
        return cachedSettings;
    }

    /**
     * @description Max hours per day for a category, from Timesheet_Default_Value__mdt.
     */
    public static Decimal maxHours(String category) {
        Timesheet_Default_Value__mdt s = settings();
        Decimal value;
        switch on category {
            when 'PTO-Planned' { value = s.Max_PTO_Planned_Hours__c; }
            when 'PTO-Un Planned' { value = s.Max_PTO_Unplanned_Hours__c; }
            when 'Sick Leave' { value = s.Max_Sick_Leave_Hours__c; }
            when 'Permission' { value = s.Max_Permission_Hours__c; }
            when 'On Duty' { value = s.Max_On_Duty_Hours__c; }
            when 'Holiday' { value = s.Max_Holiday_Hours__c; }
        }
        return value == null ? DEFAULT_CATEGORY_MAX : value;
    }

    public static Decimal dailyMax() {
        Decimal value = settings().Maximum_Working_Hrs_Per_Day__c;
        return value == null ? DEFAULT_DAILY_MAX : value;
    }

    /**
     * @description Value for Leave_Line_Item__c.Unique_Key__c: one live leave day per employee, date and category.
     */
    public static String key(Id employeeId, Date day, String category) {
        if (employeeId == null || day == null || String.isBlank(category)) {
            return null;
        }
        return String.valueOf(employeeId) + '|' + String.valueOf(day) + '|' + category;
    }

    public static String formatHours(Decimal hours) {
        if (hours == null) {
            return '0';
        }
        if (hours == hours.round(System.RoundingMode.DOWN)) {
            return String.valueOf(hours.intValue());
        }
        String text = String.valueOf(hours.setScale(2));
        return text.endsWith('0') ? text.removeEnd('0') : text;
    }

    /**
     * @description Checks every row and returns one message per row, in the same order ('' = valid).
     *              The rows are new days that aren't saved yet. Two queries for any number of rows.
     */
    public static List<String> validate(List<Row> rows) {
        List<String> errors = new List<String>();
        if (rows == null || rows.isEmpty()) {
            return errors;
        }

        Set<Id> employeeIds = new Set<Id>();
        Date minDate;
        Date maxDate;
        Map<String, Decimal> newHoursByDay = new Map<String, Decimal>();
        Map<String, Integer> countByKey = new Map<String, Integer>();
        for (Row r : rows) {
            if (r.employeeId == null || r.day == null) {
                continue;
            }
            employeeIds.add(r.employeeId);
            minDate = (minDate == null || r.day < minDate) ? r.day : minDate;
            maxDate = (maxDate == null || r.day > maxDate) ? r.day : maxDate;
            String dayKey = dayKey(r.employeeId, r.day);
            Decimal hours = r.hours == null ? 0 : r.hours;
            newHoursByDay.put(dayKey, (newHoursByDay.containsKey(dayKey) ? newHoursByDay.get(dayKey) : 0) + hours);
            String k = key(r.employeeId, r.day, r.category);
            if (k != null) {
                countByKey.put(k, (countByKey.containsKey(k) ? countByKey.get(k) : 0) + 1);
            }
        }

        Map<String, List<Leave_Line_Item__c>> leaveByDay = new Map<String, List<Leave_Line_Item__c>>();
        Map<String, List<Timesheet_Line_Item__c>> itemsByDay = new Map<String, List<Timesheet_Line_Item__c>>();
        if (!employeeIds.isEmpty()) {
            for (Leave_Line_Item__c l : [
                SELECT Id, Date__c, Absence_Category__c, Duration__c,
                    PTO_Request__r.Name, PTO_Request__r.Employee__c, PTO_Request__r.Status__c
                FROM Leave_Line_Item__c
                WHERE PTO_Request__r.Employee__c IN :employeeIds
                AND Date__c >= :minDate AND Date__c <= :maxDate
                AND PTO_Request__r.Status__c IN (:STATUS_SUBMITTED, :STATUS_APPROVED)
            ]) {
                String dk = dayKey(l.PTO_Request__r.Employee__c, l.Date__c);
                if (!leaveByDay.containsKey(dk)) {
                    leaveByDay.put(dk, new List<Leave_Line_Item__c>());
                }
                leaveByDay.get(dk).add(l);
            }
            for (Timesheet_Line_Item__c li : [
                SELECT Id, Employee__c, Date__c, Type__c, Absence_Category__c, Duration__c
                FROM Timesheet_Line_Item__c
                WHERE Employee__c IN :employeeIds
                AND Date__c >= :minDate AND Date__c <= :maxDate
            ]) {
                String dk = dayKey(li.Employee__c, li.Date__c);
                if (!itemsByDay.containsKey(dk)) {
                    itemsByDay.put(dk, new List<Timesheet_Line_Item__c>());
                }
                itemsByDay.get(dk).add(li);
            }
        }

        Decimal dayLimit = dailyMax();
        for (Row r : rows) {
            errors.add(checkRow(r, countByKey, leaveByDay, itemsByDay, newHoursByDay, dayLimit));
        }
        return errors;
    }

    private static String checkRow(
        Row r,
        Map<String, Integer> countByKey,
        Map<String, List<Leave_Line_Item__c>> leaveByDay,
        Map<String, List<Timesheet_Line_Item__c>> itemsByDay,
        Map<String, Decimal> newHoursByDay,
        Decimal dayLimit
    ) {
        if (r.employeeId == null) {
            return 'Pick an employee.';
        }
        if (r.day == null) {
            return 'Pick a date.';
        }
        if (String.isBlank(r.category)) {
            return 'Pick an absence category.';
        }
        if (r.hours == null || r.hours <= 0) {
            return 'Hours must be more than 0.';
        }
        Decimal categoryMax = maxHours(r.category);
        if (r.hours > categoryMax) {
            return r.category + ' allows up to ' + formatHours(categoryMax) + ' hours per day.';
        }
        if (countByKey.get(key(r.employeeId, r.day, r.category)) > 1) {
            return r.category + ' on ' + String.valueOf(r.day) + ' is entered more than once.';
        }

        String dk = dayKey(r.employeeId, r.day);
        List<Leave_Line_Item__c> dayLeave = leaveByDay.containsKey(dk) ? leaveByDay.get(dk) : new List<Leave_Line_Item__c>();
        List<Timesheet_Line_Item__c> dayItems = itemsByDay.containsKey(dk) ? itemsByDay.get(dk) : new List<Timesheet_Line_Item__c>();

        for (Leave_Line_Item__c l : dayLeave) {
            if (l.Absence_Category__c == r.category) {
                String state = l.PTO_Request__r.Status__c == STATUS_APPROVED ? 'approved' : 'waiting for approval';
                return r.category + ' on ' + String.valueOf(r.day) + ' is already on ' + l.PTO_Request__r.Name
                    + ', ' + state + '.';
            }
        }

        Set<String> absenceCategories = new Set<String>();
        Decimal total = 0;
        for (Timesheet_Line_Item__c li : dayItems) {
            if (li.Type__c == LINE_TYPE_ABSENCE) {
                absenceCategories.add(li.Absence_Category__c);
                if (li.Absence_Category__c == r.category) {
                    return r.category + ' on ' + String.valueOf(r.day) + ' is already on the timesheet.';
                }
            }
            total += li.Duration__c == null ? 0 : li.Duration__c;
        }
        for (Leave_Line_Item__c l : dayLeave) {
            // Leave already on the timesheet is counted through its line item.
            if (!absenceCategories.contains(l.Absence_Category__c)) {
                total += l.Duration__c == null ? 0 : l.Duration__c;
            }
        }
        total += newHoursByDay.containsKey(dk) ? newHoursByDay.get(dk) : 0;
        if (total > dayLimit) {
            return 'The total for ' + String.valueOf(r.day) + ' would be ' + formatHours(total)
                + ' hours, over the ' + formatHours(dayLimit) + '-hour daily limit.';
        }
        return '';
    }

    /**
     * @description Called from the line item trigger for Absence rows: a manual absence line item may not
     *              duplicate a leave request that is still waiting for approval.
     */
    public static void checkLineItems(List<Timesheet_Line_Item__c> items) {
        List<Timesheet_Line_Item__c> absence = new List<Timesheet_Line_Item__c>();
        Set<Id> employeeIds = new Set<Id>();
        Date minDate;
        Date maxDate;
        for (Timesheet_Line_Item__c li : items) {
            if (li.Type__c != LINE_TYPE_ABSENCE || li.Employee__c == null || li.Date__c == null || String.isBlank(li.Absence_Category__c)) {
                continue;
            }
            absence.add(li);
            employeeIds.add(li.Employee__c);
            minDate = (minDate == null || li.Date__c < minDate) ? li.Date__c : minDate;
            maxDate = (maxDate == null || li.Date__c > maxDate) ? li.Date__c : maxDate;
        }
        if (absence.isEmpty()) {
            return;
        }
        Map<String, String> pendingByKey = new Map<String, String>();
        for (Leave_Line_Item__c l : [
            SELECT Date__c, Absence_Category__c, PTO_Request__r.Name, PTO_Request__r.Employee__c
            FROM Leave_Line_Item__c
            WHERE PTO_Request__r.Employee__c IN :employeeIds
            AND Date__c >= :minDate AND Date__c <= :maxDate
            AND PTO_Request__r.Status__c = :STATUS_SUBMITTED
        ]) {
            pendingByKey.put(key(l.PTO_Request__r.Employee__c, l.Date__c, l.Absence_Category__c), l.PTO_Request__r.Name);
        }
        for (Timesheet_Line_Item__c li : absence) {
            String requestName = pendingByKey.get(key(li.Employee__c, li.Date__c, li.Absence_Category__c));
            if (requestName != null) {
                li.addError('A ' + li.Absence_Category__c + ' leave request for ' + String.valueOf(li.Date__c)
                    + ' (' + requestName + ') is waiting for approval. Approve or reject it in the PTO tab first.');
            }
        }
    }

    private static String dayKey(Id employeeId, Date day) {
        return String.valueOf(employeeId) + '|' + String.valueOf(day);
    }
}
