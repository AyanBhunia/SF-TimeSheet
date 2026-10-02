/**
 * @description Writes to Leave_and_Holiday__c: submit, approve, reject, and the trigger entry points.
 *              Runs without sharing because a manager approves records owned by the employee.
 *              Callers (PtoController) must check that the running user may act on each record first.
 */
public without sharing class LeaveService {

    public static final Integer NOTES_MAX = 2000;
    public static final String NOT_IN_TIMESHEET = 'Not in Timesheet';

    public class LeaveException extends Exception {}

    public class SubmitResult {
        public Integer submitted = 0;
        public Integer resubmitted = 0;
        public List<Leave_and_Holiday__c> records = new List<Leave_and_Holiday__c>();
    }

    // ---------------------------------------------------------------- trigger entry points

    /**
     * @description Before insert/update: stamp the key and defaults, then run LeaveValidator on rows that
     *              are new, being resubmitted, or have their date, category, hours or employee changed.
     *              Approving or rejecting alone is not re-validated.
     */
    public static void beforeSave(List<Leave_and_Holiday__c> records, Map<Id, Leave_and_Holiday__c> oldMap) {
        List<Leave_and_Holiday__c> toCheck = new List<Leave_and_Holiday__c>();
        List<LeaveValidator.Row> rows = new List<LeaveValidator.Row>();
        for (Leave_and_Holiday__c r : records) {
            if (r.Type__c == null) {
                r.Type__c = LeaveValidator.TYPE_LEAVE;
            }
            if (r.Status__c == null) {
                r.Status__c = LeaveValidator.STATUS_SUBMITTED;
            }
            r.Unique_Key__c = LeaveValidator.key(r.Employee__c, r.Date__c, r.Absence_Category__c);

            Leave_and_Holiday__c old = oldMap == null ? null : oldMap.get(r.Id);
            if (old != null && old.Status__c == LeaveValidator.STATUS_APPROVED && r.Status__c == LeaveValidator.STATUS_APPROVED
                && (r.Date__c != old.Date__c || r.Absence_Category__c != old.Absence_Category__c || r.Employee__c != old.Employee__c)) {
                // Its line item already sits on that day's timesheet; moving the leave would leave it behind.
                r.addError('Approved leave can\'t change date, category or employee. Reject it and apply again.');
                continue;
            }
            Boolean needsCheck;
            if (old == null) {
                needsCheck = r.Status__c != LeaveValidator.STATUS_NEW;
            } else {
                Boolean resubmitted = r.Status__c == LeaveValidator.STATUS_SUBMITTED && old.Status__c != LeaveValidator.STATUS_SUBMITTED;
                Boolean dayChanged = r.Date__c != old.Date__c || r.Absence_Category__c != old.Absence_Category__c
                    || r.Duration__c != old.Duration__c || r.Employee__c != old.Employee__c;
                needsCheck = resubmitted || (dayChanged && r.Status__c != LeaveValidator.STATUS_NEW);
            }
            if (needsCheck) {
                toCheck.add(r);
                rows.add(new LeaveValidator.Row(r.Employee__c, r.Date__c, r.Absence_Category__c, r.Duration__c, r.Id));
            }
        }
        List<String> errors = LeaveValidator.validate(rows);
        for (Integer i = 0; i < errors.size(); i++) {
            if (String.isNotBlank(errors[i])) {
                toCheck[i].addError(errors[i]);
            }
        }
    }

    /**
     * @description After insert/update: convert leave that has just become Approved (or whose hours
     *              changed while Approved) into timesheet line items.
     */
    public static void afterSave(List<Leave_and_Holiday__c> records, Map<Id, Leave_and_Holiday__c> oldMap) {
        Set<Id> toConvert = new Set<Id>();
        for (Leave_and_Holiday__c r : records) {
            if (r.Status__c != LeaveValidator.STATUS_APPROVED) {
                continue;
            }
            Leave_and_Holiday__c old = oldMap == null ? null : oldMap.get(r.Id);
            if (old == null || old.Status__c != LeaveValidator.STATUS_APPROVED || old.Duration__c != r.Duration__c) {
                toConvert.add(r.Id);
            }
        }
        if (!toConvert.isEmpty()) {
            LeaveToLineItem.convert(toConvert);
        }
    }

    // ---------------------------------------------------------------- submit

    /**
     * @description Submits leave rows for one employee. Each row needs Date__c, Absence_Category__c,
     *              Duration__c and optionally Notes__c. A rejected (New) record with the same employee,
     *              date and category is reused: its old notes stay and the new note is appended.
     *              The caller validates first; the trigger validates again.
     */
    public static SubmitResult submit(Employee__c employee, List<Leave_and_Holiday__c> rows) {
        SubmitResult result = new SubmitResult();
        Id ownerId = (employee.User__c != null && employee.User__r != null && employee.User__r.IsActive)
            ? employee.User__c
            : UserInfo.getUserId();

        Set<String> keys = new Set<String>();
        for (Leave_and_Holiday__c r : rows) {
            r.Employee__c = employee.Id;
            r.Type__c = LeaveValidator.TYPE_LEAVE;
            r.Status__c = LeaveValidator.STATUS_SUBMITTED;
            r.Approver__c = employee.Manager__c;
            r.OwnerId = ownerId;
            r.Unique_Key__c = LeaveValidator.key(employee.Id, r.Date__c, r.Absence_Category__c);
            keys.add(r.Unique_Key__c);
        }

        Map<String, Leave_and_Holiday__c> existingByKey = new Map<String, Leave_and_Holiday__c>();
        for (Leave_and_Holiday__c ex : [
            SELECT Id, Unique_Key__c, Status__c, Notes__c
            FROM Leave_and_Holiday__c
            WHERE Unique_Key__c IN :keys
        ]) {
            existingByKey.put(ex.Unique_Key__c, ex);
        }

        String today = String.valueOf(Date.today());
        for (Leave_and_Holiday__c r : rows) {
            Leave_and_Holiday__c ex = existingByKey.get(r.Unique_Key__c);
            if (ex == null) {
                result.submitted++;
                continue;
            }
            if (ex.Status__c != LeaveValidator.STATUS_NEW) {
                throw new LeaveException(r.Absence_Category__c + ' on ' + String.valueOf(r.Date__c) + ' is already '
                    + (ex.Status__c == LeaveValidator.STATUS_APPROVED ? 'approved.' : 'waiting for approval.'));
            }
            String line = 'Resubmitted on ' + today + (String.isBlank(r.Notes__c) ? '' : ': ' + r.Notes__c.trim());
            r.Notes__c = appendNote(ex.Notes__c, line);
            result.resubmitted++;
        }

        // One upsert on the key: a rejected record is updated, anything else is inserted, and a
        // DmlException index points at the same position as the caller's rows.
        upsert rows Leave_and_Holiday__c.Unique_Key__c;
        result.records.addAll(rows);
        submitForApproval(rows);
        return result;
    }

    // ---------------------------------------------------------------- approve / reject

    /**
     * @description Approves Submitted records. A record with an open Approval Process step is approved
     *              through Approval.process so the standard process closes too. Returns error messages.
     */
    public static List<String> approve(List<Leave_and_Holiday__c> records) {
        return decide(records, true, null);
    }

    /**
     * @description Rejects Submitted records: Status back to New and the reason appended to Notes.
     */
    public static List<String> reject(List<Leave_and_Holiday__c> records, String reason) {
        if (String.isBlank(reason)) {
            throw new LeaveException('Enter a reason before rejecting.');
        }
        return decide(records, false, reason.trim());
    }

    private static List<String> decide(List<Leave_and_Holiday__c> records, Boolean approve, String reason) {
        List<String> errors = new List<String>();
        if (records == null || records.isEmpty()) {
            return errors;
        }
        Map<Id, Leave_and_Holiday__c> byId = new Map<Id, Leave_and_Holiday__c>(records);
        Map<Id, Id> workitemByRecord = openWorkitems(byId.keySet());

        List<Approval.ProcessWorkitemRequest> requests = new List<Approval.ProcessWorkitemRequest>();
        List<Id> requestRecordIds = new List<Id>();
        for (Id recordId : workitemByRecord.keySet()) {
            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(workitemByRecord.get(recordId));
            req.setAction(approve ? 'Approve' : 'Reject');
            req.setComments(approve ? 'Approved in the PTO tab.' : reason);
            requests.add(req);
            requestRecordIds.add(recordId);
        }
        if (!requests.isEmpty()) {
            List<Approval.ProcessResult> results = Approval.process(requests, false);
            for (Integer i = 0; i < results.size(); i++) {
                if (!results[i].isSuccess()) {
                    errors.add(describe(byId.get(requestRecordIds[i])) + ': ' + results[i].getErrors()[0].getMessage());
                    byId.remove(requestRecordIds[i]);
                }
            }
        }

        // Re-read after the Approval Process step: its field update may already have set the status (and the
        // trigger may already have converted the day), so only records still Submitted get our status update.
        // A reject always appends the reason.
        String decidedBy = UserInfo.getName();
        String today = String.valueOf(Date.today());
        List<Leave_and_Holiday__c> updates = new List<Leave_and_Holiday__c>();
        for (Leave_and_Holiday__c r : [SELECT Id, Status__c, Notes__c FROM Leave_and_Holiday__c WHERE Id IN :byId.keySet()]) {
            Boolean waiting = r.Status__c == LeaveValidator.STATUS_SUBMITTED;
            if (approve) {
                if (waiting) {
                    updates.add(new Leave_and_Holiday__c(Id = r.Id, Status__c = LeaveValidator.STATUS_APPROVED));
                }
            } else {
                Leave_and_Holiday__c u = new Leave_and_Holiday__c(Id = r.Id);
                if (waiting) {
                    u.Status__c = LeaveValidator.STATUS_NEW;
                }
                u.Notes__c = appendNote(r.Notes__c, 'Rejected by ' + decidedBy + ' on ' + today + ': ' + reason);
                updates.add(u);
            }
        }
        List<Database.SaveResult> saved = Database.update(updates, false);
        for (Integer i = 0; i < saved.size(); i++) {
            if (!saved[i].isSuccess()) {
                errors.add(describe(byId.get(updates[i].Id)) + ': ' + saved[i].getErrors()[0].getMessage());
                byId.remove(updates[i].Id);
            }
        }

        // An approved day that couldn't be written to its timesheet goes back to New (see LeaveToLineItem).
        if (approve && !byId.isEmpty()) {
            for (Leave_and_Holiday__c r : [SELECT Id, Status__c, Notes__c FROM Leave_and_Holiday__c WHERE Id IN :byId.keySet()]) {
                if (r.Status__c == LeaveValidator.STATUS_NEW && isConversionError(r.Notes__c)) {
                    List<String> lines = r.Notes__c.split('\n');
                    errors.add(describe(byId.get(r.Id)) + ' was approved but could not be added to the timesheet, so it went back to the employee: '
                        + lines[lines.size() - 1]);
                }
            }
        }
        return errors;
    }

    // ---------------------------------------------------------------- helpers

    /**
     * @description Appends a line to Notes__c and keeps the newest text when the field would overflow.
     */
    public static String appendNote(String existing, String line) {
        String text = String.isBlank(existing) ? line : existing + '\n' + line;
        if (text.length() > NOTES_MAX) {
            text = text.right(NOTES_MAX);
        }
        return text;
    }

    /**
     * @description True when the latest note line is a conversion error written by LeaveToLineItem.
     */
    public static Boolean isConversionError(String notes) {
        if (String.isBlank(notes)) {
            return false;
        }
        List<String> lines = notes.split('\n');
        return lines[lines.size() - 1].startsWith(NOT_IN_TIMESHEET);
    }

    private static String describe(Leave_and_Holiday__c r) {
        return r == null ? 'Leave' : (r.Absence_Category__c + ' on ' + String.valueOf(r.Date__c));
    }

    private static Map<Id, Id> openWorkitems(Set<Id> recordIds) {
        Map<Id, Id> result = new Map<Id, Id>();
        for (ProcessInstanceWorkitem wi : [
            SELECT Id, ProcessInstance.TargetObjectId
            FROM ProcessInstanceWorkitem
            WHERE ProcessInstance.TargetObjectId IN :recordIds
            AND ProcessInstance.Status = 'Pending'
        ]) {
            result.put(wi.ProcessInstance.TargetObjectId, wi.Id);
        }
        return result;
    }

    /**
     * @description When the org has an active approval process on this object (deployed separately,
     *              outside the package), send each submitted record into it so approvers get the
     *              standard notification. Records with no approver, or that no process accepts, are skipped.
     */
    private static void submitForApproval(List<Leave_and_Holiday__c> records) {
        String objectName = Leave_and_Holiday__c.SObjectType.getDescribe().getName();
        Integer active = [
            SELECT COUNT() FROM ProcessDefinition
            WHERE TableEnumOrId = :objectName AND State = 'Active' AND Type = 'Approval'
        ];
        if (active == 0) {
            return;
        }
        List<Approval.ProcessSubmitRequest> requests = new List<Approval.ProcessSubmitRequest>();
        for (Leave_and_Holiday__c r : records) {
            if (r.Id == null || r.Approver__c == null) {
                continue;
            }
            Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
            req.setObjectId(r.Id);
            req.setSubmitterId(r.OwnerId);
            req.setComments(String.isBlank(r.Notes__c) ? 'Submitted from the PTO tab.' : r.Notes__c.right(4000));
            requests.add(req);
        }
        if (!requests.isEmpty()) {
            Approval.process(requests, false);
        }
    }
}
