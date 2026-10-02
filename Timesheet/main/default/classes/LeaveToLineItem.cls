/**
 * @description Turns approved Leave_and_Holiday__c days into absence Timesheet_Line_Item__c rows.
 *              A day is matched to the employee's timesheet whose Start/End contains it. If the employee
 *              already has an absence line item with the same date and category, that item gets its
 *              duration set to the leave hours, otherwise a new line item is inserted. Setting (not adding)
 *              the hours makes a second run harmless.
 *              A day that can't be written goes back to Status New with "Not in Timesheet [error]" in Notes.
 *              Runs without sharing: line items are written to the employee's timesheet whoever approved.
 */
public without sharing class LeaveToLineItem {

    private static final Integer DESCRIPTION_MAX = 255;

    /**
     * @description Called from the leave trigger when records become Approved.
     */
    public static void convert(Set<Id> leaveIds) {
        if (leaveIds == null || leaveIds.isEmpty()) {
            return;
        }
        run([
            SELECT Id, Employee__c, Date__c, Absence_Category__c, Duration__c, Notes__c
            FROM Leave_and_Holiday__c
            WHERE Id IN :leaveIds AND Status__c = :LeaveValidator.STATUS_APPROVED
        ], null);
    }

    /**
     * @description Called from TimesheetTrigger after insert: picks up approved leave in the new weeks.
     */
    public static void forTimesheets(List<Timesheet__c> timesheets) {
        Set<Id> employeeIds = new Set<Id>();
        Date minDate;
        Date maxDate;
        List<Timesheet__c> usable = new List<Timesheet__c>();
        for (Timesheet__c ts : timesheets) {
            if (ts.Employee__c == null || ts.Start_Date__c == null || ts.End_Date__c == null) {
                continue;
            }
            usable.add(ts);
            employeeIds.add(ts.Employee__c);
            minDate = (minDate == null || ts.Start_Date__c < minDate) ? ts.Start_Date__c : minDate;
            maxDate = (maxDate == null || ts.End_Date__c > maxDate) ? ts.End_Date__c : maxDate;
        }
        if (usable.isEmpty()) {
            return;
        }
        run([
            SELECT Id, Employee__c, Date__c, Absence_Category__c, Duration__c, Notes__c
            FROM Leave_and_Holiday__c
            WHERE Employee__c IN :employeeIds
            AND Date__c >= :minDate AND Date__c <= :maxDate
            AND Status__c = :LeaveValidator.STATUS_APPROVED
        ], usable);
    }

    private static void run(List<Leave_and_Holiday__c> leaves, List<Timesheet__c> timesheets) {
        if (leaves.isEmpty()) {
            return;
        }
        Set<Id> employeeIds = new Set<Id>();
        Date minDate;
        Date maxDate;
        for (Leave_and_Holiday__c l : leaves) {
            employeeIds.add(l.Employee__c);
            minDate = (minDate == null || l.Date__c < minDate) ? l.Date__c : minDate;
            maxDate = (maxDate == null || l.Date__c > maxDate) ? l.Date__c : maxDate;
        }
        if (timesheets == null) {
            timesheets = [
                SELECT Id, Employee__c, Start_Date__c, End_Date__c
                FROM Timesheet__c
                WHERE Employee__c IN :employeeIds
                AND Start_Date__c <= :maxDate AND End_Date__c >= :minDate
                ORDER BY Start_Date__c
            ];
        }
        Map<Id, List<Timesheet__c>> timesheetsByEmployee = new Map<Id, List<Timesheet__c>>();
        for (Timesheet__c ts : timesheets) {
            if (!timesheetsByEmployee.containsKey(ts.Employee__c)) {
                timesheetsByEmployee.put(ts.Employee__c, new List<Timesheet__c>());
            }
            timesheetsByEmployee.get(ts.Employee__c).add(ts);
        }

        Map<Id, Id> timesheetByLeave = new Map<Id, Id>();
        for (Leave_and_Holiday__c l : leaves) {
            List<Timesheet__c> candidates = timesheetsByEmployee.get(l.Employee__c);
            if (candidates == null) {
                continue;
            }
            for (Timesheet__c ts : candidates) {
                if (ts.Start_Date__c <= l.Date__c && l.Date__c <= ts.End_Date__c) {
                    timesheetByLeave.put(l.Id, ts.Id);
                    break;
                }
            }
        }
        if (timesheetByLeave.isEmpty()) {
            return;
        }

        // Match on employee + date + category across all of the employee's timesheets, so a day that is
        // already on a timesheet is never added a second time (e.g. two timesheets overlap a week).
        Map<String, Timesheet_Line_Item__c> existing = new Map<String, Timesheet_Line_Item__c>();
        for (Timesheet_Line_Item__c li : [
            SELECT Id, Employee__c, Date__c, Absence_Category__c, Duration__c
            FROM Timesheet_Line_Item__c
            WHERE Employee__c IN :employeeIds
            AND Date__c >= :minDate AND Date__c <= :maxDate
            AND Type__c = :LeaveValidator.LINE_TYPE_ABSENCE
        ]) {
            existing.put(itemKey(li.Employee__c, li.Date__c, li.Absence_Category__c), li);
        }

        List<Timesheet_Line_Item__c> inserts = new List<Timesheet_Line_Item__c>();
        List<Leave_and_Holiday__c> insertLeave = new List<Leave_and_Holiday__c>();
        List<Timesheet_Line_Item__c> updates = new List<Timesheet_Line_Item__c>();
        List<Leave_and_Holiday__c> updateLeave = new List<Leave_and_Holiday__c>();
        for (Leave_and_Holiday__c l : leaves) {
            Id timesheetId = timesheetByLeave.get(l.Id);
            if (timesheetId == null) {
                continue;
            }
            Timesheet_Line_Item__c match = existing.get(itemKey(l.Employee__c, l.Date__c, l.Absence_Category__c));
            if (match != null) {
                if (match.Duration__c != l.Duration__c) {
                    updates.add(new Timesheet_Line_Item__c(Id = match.Id, Duration__c = l.Duration__c));
                    updateLeave.add(l);
                }
                continue;
            }
            inserts.add(new Timesheet_Line_Item__c(
                Timesheet__c = timesheetId,
                Employee__c = l.Employee__c,
                Date__c = l.Date__c,
                Type__c = LeaveValidator.LINE_TYPE_ABSENCE,
                Absence_Category__c = l.Absence_Category__c,
                Duration__c = l.Duration__c,
                Description__c = description(l.Notes__c)
            ));
            insertLeave.add(l);
        }

        Map<Id, String> failures = new Map<Id, String>();
        if (!inserts.isEmpty()) {
            collectFailures(Database.insert(inserts, false), insertLeave, failures);
        }
        if (!updates.isEmpty()) {
            collectFailures(Database.update(updates, false), updateLeave, failures);
        }
        if (failures.isEmpty()) {
            return;
        }

        Map<Id, Leave_and_Holiday__c> leaveById = new Map<Id, Leave_and_Holiday__c>(leaves);
        List<Leave_and_Holiday__c> sentBack = new List<Leave_and_Holiday__c>();
        for (Id leaveId : failures.keySet()) {
            sentBack.add(new Leave_and_Holiday__c(
                Id = leaveId,
                Status__c = LeaveValidator.STATUS_NEW,
                Notes__c = LeaveService.appendNote(
                    leaveById.get(leaveId).Notes__c,
                    LeaveService.NOT_IN_TIMESHEET + ' [' + failures.get(leaveId) + ']'
                )
            ));
        }
        Database.update(sentBack, false);
    }

    private static void collectFailures(List<Database.SaveResult> results, List<Leave_and_Holiday__c> source, Map<Id, String> failures) {
        for (Integer i = 0; i < results.size(); i++) {
            if (!results[i].isSuccess()) {
                List<String> messages = new List<String>();
                for (Database.Error e : results[i].getErrors()) {
                    messages.add(e.getMessage());
                }
                failures.put(source[i].Id, String.join(messages, '; '));
            }
        }
    }

    private static String description(String notes) {
        if (String.isBlank(notes)) {
            return null;
        }
        List<String> lines = notes.split('\n');
        String first = lines[0].trim();
        return first.left(DESCRIPTION_MAX);
    }

    private static String itemKey(Id employeeId, Date day, String category) {
        return String.valueOf(employeeId) + '|' + String.valueOf(day) + '|' + category;
    }
}
