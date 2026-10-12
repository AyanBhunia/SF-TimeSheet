/**
 * @description Turns the Leave_Line_Item__c days of approved PTO requests into absence Timesheet_Line_Item__c rows.
 *              A day is matched to the employee's timesheet whose Start/End contains it. If the employee
 *              already has an absence line item with the same date and category, that item gets its
 *              duration set to the leave hours, otherwise a new line item is inserted. Setting (not adding)
 *              the hours makes a second run harmless.
 *              Each day records the outcome on itself: On timesheet, Waiting for timesheet (no timesheet for
 *              that week yet), or Error with the message. A failed day never undoes the approval.
 *              Runs without sharing: line items are written to the employee's timesheet whoever approved.
 */
public without sharing class LeaveToLineItem {

    private static final Integer DESCRIPTION_MAX = 255;
    private static final Integer ERROR_MAX = 255;

    /**
     * @description Called from the request trigger when requests become Approved, and for an HR retry.
     *              Days already on a timesheet are skipped.
     */
    public static void convertRequests(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty()) {
            return;
        }
        run([
            SELECT Id, Date__c, Absence_Category__c, Duration__c, Sync_Status__c, Sync_Error__c, Timesheet_Line_Item__c,
                PTO_Request__r.Employee__c, PTO_Request__r.Notes__c
            FROM Leave_Line_Item__c
            WHERE PTO_Request__c IN :requestIds
            AND PTO_Request__r.Status__c = :LeaveValidator.STATUS_APPROVED
            AND Sync_Status__c != :LeaveValidator.SYNC_DONE
        ], null);
    }

    /**
     * @description Called from TimesheetTrigger after insert: picks up approved days in the new weeks.
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
            SELECT Id, Date__c, Absence_Category__c, Duration__c, Sync_Status__c, Sync_Error__c, Timesheet_Line_Item__c,
                PTO_Request__r.Employee__c, PTO_Request__r.Notes__c
            FROM Leave_Line_Item__c
            WHERE PTO_Request__r.Employee__c IN :employeeIds
            AND Date__c >= :minDate AND Date__c <= :maxDate
            AND PTO_Request__r.Status__c = :LeaveValidator.STATUS_APPROVED
            AND Sync_Status__c != :LeaveValidator.SYNC_DONE
        ], usable);
    }

    private static void run(List<Leave_Line_Item__c> lines, List<Timesheet__c> timesheets) {
        if (lines.isEmpty()) {
            return;
        }
        Set<Id> employeeIds = new Set<Id>();
        Date minDate;
        Date maxDate;
        for (Leave_Line_Item__c l : lines) {
            employeeIds.add(l.PTO_Request__r.Employee__c);
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

        Map<Id, Leave_Line_Item__c> outcome = new Map<Id, Leave_Line_Item__c>();
        List<Timesheet_Line_Item__c> inserts = new List<Timesheet_Line_Item__c>();
        List<Leave_Line_Item__c> insertLines = new List<Leave_Line_Item__c>();
        List<Timesheet_Line_Item__c> updates = new List<Timesheet_Line_Item__c>();
        List<Leave_Line_Item__c> updateLines = new List<Leave_Line_Item__c>();
        for (Leave_Line_Item__c l : lines) {
            Id employeeId = l.PTO_Request__r.Employee__c;
            Id timesheetId = timesheetFor(timesheetsByEmployee.get(employeeId), l.Date__c);
            if (timesheetId == null) {
                setOutcome(outcome, l, LeaveValidator.SYNC_WAITING, null, null);
                continue;
            }
            Timesheet_Line_Item__c match = existing.get(itemKey(employeeId, l.Date__c, l.Absence_Category__c));
            if (match != null) {
                if (match.Duration__c != l.Duration__c) {
                    updates.add(new Timesheet_Line_Item__c(Id = match.Id, Duration__c = l.Duration__c));
                    updateLines.add(l);
                }
                setOutcome(outcome, l, LeaveValidator.SYNC_DONE, match.Id, null);
                continue;
            }
            inserts.add(new Timesheet_Line_Item__c(
                Timesheet__c = timesheetId,
                Employee__c = employeeId,
                Date__c = l.Date__c,
                Type__c = LeaveValidator.LINE_TYPE_ABSENCE,
                Absence_Category__c = l.Absence_Category__c,
                Duration__c = l.Duration__c,
                Description__c = description(l.PTO_Request__r.Notes__c)
            ));
            insertLines.add(l);
        }

        if (!inserts.isEmpty()) {
            List<Database.SaveResult> results = Database.insert(inserts, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    setOutcome(outcome, insertLines[i], LeaveValidator.SYNC_DONE, results[i].getId(), null);
                } else {
                    setOutcome(outcome, insertLines[i], LeaveValidator.SYNC_ERROR, null, message(results[i]));
                }
            }
        }
        if (!updates.isEmpty()) {
            List<Database.SaveResult> results = Database.update(updates, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    setOutcome(outcome, updateLines[i], LeaveValidator.SYNC_ERROR, null, message(results[i]));
                }
            }
        }

        // Write back only the days whose outcome changed.
        Map<Id, Leave_Line_Item__c> before = new Map<Id, Leave_Line_Item__c>(lines);
        List<Leave_Line_Item__c> changed = new List<Leave_Line_Item__c>();
        for (Leave_Line_Item__c o : outcome.values()) {
            Leave_Line_Item__c b = before.get(o.Id);
            if (o.Sync_Status__c != b.Sync_Status__c || o.Sync_Error__c != b.Sync_Error__c
                || o.Timesheet_Line_Item__c != b.Timesheet_Line_Item__c) {
                changed.add(o);
            }
        }
        if (!changed.isEmpty()) {
            Database.update(changed, false);
        }
    }

    private static void setOutcome(Map<Id, Leave_Line_Item__c> outcome, Leave_Line_Item__c l, String status, Id itemId, String error) {
        outcome.put(l.Id, new Leave_Line_Item__c(
            Id = l.Id,
            Sync_Status__c = status,
            Timesheet_Line_Item__c = itemId,
            Sync_Error__c = error == null ? null : error.left(ERROR_MAX)
        ));
    }

    private static Id timesheetFor(List<Timesheet__c> candidates, Date day) {
        if (candidates == null) {
            return null;
        }
        for (Timesheet__c ts : candidates) {
            if (ts.Start_Date__c <= day && day <= ts.End_Date__c) {
                return ts.Id;
            }
        }
        return null;
    }

    private static String message(Database.SaveResult result) {
        List<String> messages = new List<String>();
        for (Database.Error e : result.getErrors()) {
            messages.add(e.getMessage());
        }
        return String.join(messages, '; ');
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
