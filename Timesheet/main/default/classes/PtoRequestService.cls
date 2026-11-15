/**
 * @description Writes to PTO_Request__c and Leave_Line_Item__c: submit, approve, reject, and the trigger
 *              entry points for both objects.
 *              Runs without sharing because a manager approves requests owned by the employee.
 *              Callers (PtoController) must check that the running user may act on each request first.
 */
public without sharing class PtoRequestService {

    public static final Integer NOTES_MAX = 2000;

    // True while approve/reject writes the decision fields itself.
    private static Boolean deciding = false;

    // PTO tab comments by request Id, read by stampDecision while Approval.process closes the step. The decision
    // is stamped in that same save, so the approval process's email alerts already show it.
    private static Map<Id, String> tabComments = new Map<Id, String>();

    // Requests whose decision was written before Approval.process closed the step; stampDecision leaves them alone.
    private static Set<Id> preStamped = new Set<Id>();

    public class PtoException extends Exception {}

    public class SubmitResult {
        public PTO_Request__c request;
        public Integer dayCount = 0;
    }

    public class DecisionResult {
        public Integer processed = 0;
        public List<String> errors = new List<String>();
        public List<String> syncErrors = new List<String>();
    }

    // ---------------------------------------------------------------- request trigger

    /**
     * @description Before insert/update: default status, stamp the approver on insert, and keep the
     *              status moving one way only (Submitted to Approved or Rejected). A decision made outside
     *              the PTO tab (the standard approval screen, a data load) gets who, when and the approver's
     *              comment stamped here.
     */
    public static void beforeRequestSave(List<PTO_Request__c> records, Map<Id, PTO_Request__c> oldMap) {
        Set<Id> employeeIds = new Set<Id>();
        List<PTO_Request__c> decidedElsewhere = new List<PTO_Request__c>();
        for (PTO_Request__c r : records) {
            if (r.Status__c == null) {
                r.Status__c = LeaveValidator.STATUS_SUBMITTED;
            }
            PTO_Request__c old = oldMap == null ? null : oldMap.get(r.Id);
            if (old == null) {
                if (r.Approver__c == null && r.Employee__c != null) {
                    employeeIds.add(r.Employee__c);
                }
                continue;
            }
            if (r.Employee__c != old.Employee__c) {
                r.addError('A PTO request can\'t move to another employee.');
            } else if (r.Status__c != old.Status__c && old.Status__c != LeaveValidator.STATUS_SUBMITTED) {
                r.addError(old.Status__c == LeaveValidator.STATUS_APPROVED
                    ? 'Approved requests can\'t change status. Cancelling approved leave isn\'t supported.'
                    : 'Rejected requests can\'t be reopened. Apply again to create a new request.');
            } else if (r.Status__c != old.Status__c && !deciding) {
                decidedElsewhere.add(r);
            }
        }
        if (!decidedElsewhere.isEmpty()) {
            stampDecision(decidedElsewhere);
        }
        if (employeeIds.isEmpty()) {
            return;
        }
        Map<Id, Employee__c> employees = new Map<Id, Employee__c>([
            SELECT Id, Manager__c FROM Employee__c WHERE Id IN :employeeIds
        ]);
        for (PTO_Request__c r : records) {
            if (r.Id == null && r.Approver__c == null && employees.containsKey(r.Employee__c)) {
                r.Approver__c = employees.get(r.Employee__c).Manager__c;
            }
        }
    }

    private static void stampDecision(List<PTO_Request__c> stampable) {
        List<PTO_Request__c> records = new List<PTO_Request__c>();
        for (PTO_Request__c r : stampable) {
            if (!preStamped.contains(r.Id)) {
                records.add(r);
            }
        }
        if (records.isEmpty()) {
            return;
        }
        Set<Id> ids = new Set<Id>();
        for (PTO_Request__c r : records) {
            if (!tabComments.containsKey(r.Id)) {
                ids.add(r.Id);
            }
        }
        Map<Id, String> commentById = new Map<Id, String>(tabComments);
        for (ProcessInstanceStep s : ids.isEmpty() ? new List<ProcessInstanceStep>() : [
            SELECT ProcessInstance.TargetObjectId, Comments
            FROM ProcessInstanceStep
            WHERE ProcessInstance.TargetObjectId IN :ids AND StepStatus IN ('Approved', 'Rejected')
            ORDER BY CreatedDate DESC
        ]) {
            Id target = s.ProcessInstance.TargetObjectId;
            if (!commentById.containsKey(target)) {
                commentById.put(target, s.Comments);
            }
        }
        for (PTO_Request__c r : records) {
            String line = decisionLine(r.Status__c == LeaveValidator.STATUS_APPROVED, commentById.get(r.Id));
            r.Decided_By__c = UserInfo.getUserId();
            r.Decided_On__c = System.now();
            r.Decision_Notes__c = appendNote(r.Decision_Notes__c, line);
        }
    }

    /**
     * @description After insert: the approver gets read access to the request.
     */
    public static void afterRequestInsert(List<PTO_Request__c> records) {
        shareWithApprovers(records, null);
    }

    /**
     * @description Requests are private to their owner, so the approver is given read access (sharing reason
     *              Approver__c). Without it Salesforce's own approval screens (approval page, Items to Approve)
     *              refuse the approver. A changed approver loses the share and the new one gets it. Leave lines
     *              follow the request. A share that can't be made (approver is the owner, or inactive) is skipped.
     */
    private static void shareWithApprovers(List<PTO_Request__c> records, Map<Id, PTO_Request__c> oldMap) {
        List<PTO_Request__Share> shares = new List<PTO_Request__Share>();
        Set<Id> changed = new Set<Id>();
        for (PTO_Request__c r : records) {
            PTO_Request__c old = oldMap == null ? null : oldMap.get(r.Id);
            if (old != null && old.Approver__c == r.Approver__c) {
                continue;
            }
            if (old != null && old.Approver__c != null) {
                changed.add(r.Id);
            }
            if (r.Approver__c != null && r.Approver__c != r.OwnerId) {
                shares.add(new PTO_Request__Share(
                    ParentId = r.Id,
                    UserOrGroupId = r.Approver__c,
                    AccessLevel = 'Read',
                    RowCause = Schema.PTO_Request__Share.RowCause.Approver__c
                ));
            }
        }
        if (!changed.isEmpty()) {
            delete [
                SELECT Id FROM PTO_Request__Share
                WHERE ParentId IN :changed AND RowCause = :Schema.PTO_Request__Share.RowCause.Approver__c
            ];
        }
        if (!shares.isEmpty()) {
            Database.insert(shares, false);
        }
    }

    /**
     * @description After update: an approved request is written to its timesheets; a rejected request
     *              lets go of its days (keys cleared) so a new request can use the same dates. The owner gets a
     *              bell notification either way, wherever the decision was made.
     */
    public static void afterRequestUpdate(List<PTO_Request__c> records, Map<Id, PTO_Request__c> oldMap) {
        shareWithApprovers(records, oldMap);
        Set<Id> approved = new Set<Id>();
        Set<Id> rejected = new Set<Id>();
        for (PTO_Request__c r : records) {
            PTO_Request__c old = oldMap.get(r.Id);
            if (r.Status__c == old.Status__c) {
                continue;
            }
            if (r.Status__c == LeaveValidator.STATUS_APPROVED) {
                approved.add(r.Id);
            } else if (r.Status__c == LeaveValidator.STATUS_REJECTED) {
                rejected.add(r.Id);
            }
        }
        if (!rejected.isEmpty()) {
            List<Leave_Line_Item__c> lines = [
                SELECT Id FROM Leave_Line_Item__c WHERE PTO_Request__c IN :rejected AND Unique_Key__c != null
            ];
            for (Leave_Line_Item__c l : lines) {
                l.Unique_Key__c = null;
            }
            update lines;
        }
        if (!approved.isEmpty()) {
            LeaveToLineItem.convertRequests(approved);
        }
        Set<Id> decided = new Set<Id>(approved);
        decided.addAll(rejected);
        PtoNotifier.decided(decided);
    }

    // ---------------------------------------------------------------- line trigger

    /**
     * @description Before insert: a day can only be added to a Submitted request. Stamps the key and the
     *              sync defaults, then runs LeaveValidator.
     */
    public static void beforeLineInsert(List<Leave_Line_Item__c> lines) {
        Set<Id> requestIds = new Set<Id>();
        for (Leave_Line_Item__c l : lines) {
            requestIds.add(l.PTO_Request__c);
        }
        Map<Id, PTO_Request__c> requests = new Map<Id, PTO_Request__c>([
            SELECT Id, Employee__c, Status__c FROM PTO_Request__c WHERE Id IN :requestIds
        ]);
        List<Leave_Line_Item__c> toCheck = new List<Leave_Line_Item__c>();
        List<LeaveValidator.Row> rows = new List<LeaveValidator.Row>();
        for (Leave_Line_Item__c l : lines) {
            PTO_Request__c request = requests.get(l.PTO_Request__c);
            if (request == null) {
                continue;
            }
            if (request.Status__c != LeaveValidator.STATUS_SUBMITTED) {
                l.addError('Days can only be added to a request that is waiting for approval.');
                continue;
            }
            l.Unique_Key__c = LeaveValidator.key(request.Employee__c, l.Date__c, l.Absence_Category__c);
            l.Sync_Status__c = LeaveValidator.SYNC_WAITING;
            l.Sync_Error__c = null;
            l.Timesheet_Line_Item__c = null;
            toCheck.add(l);
            rows.add(new LeaveValidator.Row(request.Employee__c, l.Date__c, l.Absence_Category__c, l.Duration__c));
        }
        List<String> errors = LeaveValidator.validate(rows);
        for (Integer i = 0; i < errors.size(); i++) {
            if (String.isNotBlank(errors[i])) {
                toCheck[i].addError(errors[i]);
            }
        }
    }

    /**
     * @description Before update: a day is fixed once submitted. Only the sync fields and the key change,
     *              and only through Apex (users can't edit them).
     */
    public static void beforeLineUpdate(List<Leave_Line_Item__c> lines, Map<Id, Leave_Line_Item__c> oldMap) {
        for (Leave_Line_Item__c l : lines) {
            Leave_Line_Item__c old = oldMap.get(l.Id);
            if (l.Date__c != old.Date__c || l.Absence_Category__c != old.Absence_Category__c
                || l.Duration__c != old.Duration__c) {
                l.addError('Leave days can\'t be changed after submitting.');
            }
        }
    }

    /**
     * @description Before delete: only days of a rejected request, or anything for HR.
     */
    public static void beforeLineDelete(List<Leave_Line_Item__c> lines) {
        if (PtoController.hasPermission(PtoController.PERM_ADMIN_ALL)) {
            return;
        }
        Set<Id> requestIds = new Set<Id>();
        for (Leave_Line_Item__c l : lines) {
            requestIds.add(l.PTO_Request__c);
        }
        Map<Id, PTO_Request__c> requests = new Map<Id, PTO_Request__c>([
            SELECT Id, Status__c FROM PTO_Request__c WHERE Id IN :requestIds
        ]);
        for (Leave_Line_Item__c l : lines) {
            PTO_Request__c request = requests.get(l.PTO_Request__c);
            if (request != null && request.Status__c != LeaveValidator.STATUS_REJECTED) {
                l.addError('Days of a request that is waiting for approval or approved can\'t be deleted.');
            }
        }
    }

    // ---------------------------------------------------------------- submit

    /**
     * @description Creates one Submitted request for the employee with one line per day. Each line needs
     *              Date__c, Absence_Category__c and Duration__c. The caller validates first and wraps the
     *              call in a savepoint; the line trigger validates again. A DmlException from the line insert
     *              has indexes that match the caller's lines.
     */
    public static SubmitResult submit(Employee__c employee, List<Leave_Line_Item__c> lines, String notes) {
        if (lines == null || lines.isEmpty()) {
            throw new PtoException('Add at least one day.');
        }
        Id ownerId = (employee.User__c != null && employee.User__r != null && employee.User__r.IsActive)
            ? employee.User__c
            : UserInfo.getUserId();
        PTO_Request__c request = new PTO_Request__c(
            Employee__c = employee.Id,
            Status__c = LeaveValidator.STATUS_SUBMITTED,
            Approver__c = employee.Manager__c,
            OwnerId = ownerId,
            Notes__c = String.isBlank(notes) ? null : notes.trim().left(NOTES_MAX)
        );
        try {
            insert request;
        } catch (DmlException e) {
            throw new PtoException(e.getDmlMessage(0));
        }
        for (Leave_Line_Item__c l : lines) {
            l.PTO_Request__c = request.Id;
        }
        insert lines;

        SubmitResult result = new SubmitResult();
        result.request = [SELECT Id, Name, Approver__c, OwnerId, Notes__c FROM PTO_Request__c WHERE Id = :request.Id];
        result.dayCount = lines.size();
        submitForApproval(result.request);
        PtoNotifier.submitted(new Set<Id>{ request.Id });
        return result;
    }

    // ---------------------------------------------------------------- approve / reject

    /**
     * @description Approves Submitted requests. A request with an open Approval Process step is approved
     *              through Approval.process so the standard process closes too.
     */
    public static DecisionResult approve(List<PTO_Request__c> requests) {
        return decide(requests, true, null);
    }

    /**
     * @description Rejects Submitted requests with a reason, written to Decision_Notes__c.
     */
    public static DecisionResult reject(List<PTO_Request__c> requests, String reason) {
        if (String.isBlank(reason)) {
            throw new PtoException('Enter a reason before rejecting.');
        }
        return decide(requests, false, reason.trim());
    }

    private static DecisionResult decide(List<PTO_Request__c> requests, Boolean approve, String reason) {
        DecisionResult result = new DecisionResult();
        if (requests == null || requests.isEmpty()) {
            return result;
        }
        Map<Id, PTO_Request__c> byId = new Map<Id, PTO_Request__c>(requests);
        Set<Id> stampedIds = new Set<Id>();
        Set<Id> closedByProcess = closeWorkitems(byId, approve, reason, result, stampedIds);
        deciding = true;
        try {
            return writeDecisions(byId, closedByProcess, stampedIds, approve, reason, result);
        } finally {
            deciding = false;
        }
    }

    /**
     * @description Approves or rejects the open Approval Process step of each request that has one. The decision
     *              is written first (preStampDecisions), then the process's field update sets the status, so the
     *              process's email alerts show the decision. Returns the requests whose step closed; failures are removed
     *              from byId and reported. stampedIds gets the requests whose decision is already written.
     */
    private static Set<Id> closeWorkitems(Map<Id, PTO_Request__c> byId, Boolean approve, String reason, DecisionResult result,
            Set<Id> stampedIds) {
        Map<Id, Id> workitemByRecord = openWorkitems(byId.keySet());
        List<Approval.ProcessWorkitemRequest> processRequests = new List<Approval.ProcessWorkitemRequest>();
        List<Id> processRecordIds = new List<Id>();
        for (Id recordId : workitemByRecord.keySet()) {
            Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
            req.setWorkitemId(workitemByRecord.get(recordId));
            req.setAction(approve ? 'Approve' : 'Reject');
            req.setComments(approve ? 'Approved in the PTO tab.' : reason);
            processRequests.add(req);
            processRecordIds.add(recordId);
            tabComments.put(recordId, approve ? null : reason);
        }
        Set<Id> closed = new Set<Id>();
        if (processRequests.isEmpty()) {
            return closed;
        }
        Map<Id, PTO_Request__c> beforeStamp = preStampDecisions(processRecordIds, approve, reason);
        List<Approval.ProcessResult> results;
        try {
            results = Approval.process(processRequests, false);
        } finally {
            tabComments.clear();
            preStamped.clear();
        }
        List<PTO_Request__c> restore = new List<PTO_Request__c>();
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                closed.add(processRecordIds[i]);
            } else {
                result.errors.add(byId.get(processRecordIds[i]).Name + ': ' + results[i].getErrors()[0].getMessage());
                byId.remove(processRecordIds[i]);
                if (beforeStamp.containsKey(processRecordIds[i])) {
                    restore.add(beforeStamp.get(processRecordIds[i]));
                }
            }
        }
        if (!restore.isEmpty()) {
            Database.update(restore, false);
        }
        stampedIds.addAll(beforeStamp.keySet());
        stampedIds.retainAll(closed);
        return closed;
    }

    /**
     * @description Writes who decided, when and the comment onto each request before its Approval Process step
     *              closes. The process's email alerts read the record as it is when the step closes, so the
     *              decision has to be there already. Returns each stamped request's previous values, to put back if
     *              the step then fails. A request that can't be stamped (locked for this user) is stamped by the
     *              trigger instead, as before.
     */
    private static Map<Id, PTO_Request__c> preStampDecisions(List<Id> recordIds, Boolean approve, String reason) {
        Map<Id, PTO_Request__c> previous = new Map<Id, PTO_Request__c>();
        List<PTO_Request__c> stamps = new List<PTO_Request__c>();
        String line = decisionLine(approve, reason);
        for (PTO_Request__c r : [
            SELECT Id, Decided_By__c, Decided_On__c, Decision_Notes__c FROM PTO_Request__c WHERE Id IN :recordIds
        ]) {
            previous.put(r.Id, r);
            stamps.add(new PTO_Request__c(
                Id = r.Id,
                Decided_By__c = UserInfo.getUserId(),
                Decided_On__c = System.now(),
                Decision_Notes__c = appendNote(r.Decision_Notes__c, line)
            ));
        }
        List<Database.SaveResult> saved = Database.update(stamps, false);
        Map<Id, PTO_Request__c> stamped = new Map<Id, PTO_Request__c>();
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) {
                preStamped.add(stamps[i].Id);
                stamped.put(stamps[i].Id, previous.get(stamps[i].Id));
            }
        }
        return stamped;
    }

    private static String decisionLine(Boolean approve, String comment) {
        return (approve ? 'Approved by ' : 'Rejected by ') + UserInfo.getName() + ' on ' + String.valueOf(Date.today())
            + (String.isBlank(comment) ? '' : ': ' + comment.trim());
    }

    private static DecisionResult writeDecisions(Map<Id, PTO_Request__c> byId, Set<Id> closedByProcess, Set<Id> stampedIds,
            Boolean approve, String reason, DecisionResult result) {
        // Re-read after the Approval Process step: its field update has usually set the status already (and the
        // trigger has stamped the decision and written the days to the timesheet). Only requests still Submitted,
        // or with no Approval Process step, are updated here.
        String target = approve ? LeaveValidator.STATUS_APPROVED : LeaveValidator.STATUS_REJECTED;
        String line = decisionLine(approve, reason);
        List<PTO_Request__c> updates = new List<PTO_Request__c>();
        for (PTO_Request__c r : [SELECT Id, Name, Status__c, Decision_Notes__c FROM PTO_Request__c WHERE Id IN :byId.keySet()]) {
            if (r.Status__c != LeaveValidator.STATUS_SUBMITTED && r.Status__c != target) {
                result.errors.add(r.Name + ' is no longer waiting for approval.');
                byId.remove(r.Id);
                continue;
            }
            if (closedByProcess.contains(r.Id) && r.Status__c == target) {
                result.processed++;
                continue;
            }
            // A step that closed without setting the status (another step follows, say) already has the decision
            // written by preStampDecisions; only the status is left to set.
            PTO_Request__c u = new PTO_Request__c(Id = r.Id, Status__c = target);
            if (!stampedIds.contains(r.Id)) {
                u.Decided_By__c = UserInfo.getUserId();
                u.Decided_On__c = System.now();
                u.Decision_Notes__c = appendNote(r.Decision_Notes__c, line);
            }
            updates.add(u);
        }
        List<Database.SaveResult> saved = Database.update(updates, false);
        for (Integer i = 0; i < saved.size(); i++) {
            if (saved[i].isSuccess()) {
                result.processed++;
            } else {
                result.errors.add(byId.get(updates[i].Id).Name + ': ' + saved[i].getErrors()[0].getMessage());
                byId.remove(updates[i].Id);
            }
        }

        // An approved day that couldn't be written to its timesheet is flagged on its line; the request stays approved.
        if (approve && !byId.isEmpty()) {
            for (Leave_Line_Item__c l : [
                SELECT Date__c, Absence_Category__c, Sync_Error__c, PTO_Request__r.Name
                FROM Leave_Line_Item__c
                WHERE PTO_Request__c IN :byId.keySet() AND Sync_Status__c = :LeaveValidator.SYNC_ERROR
                ORDER BY Date__c
            ]) {
                result.syncErrors.add(l.PTO_Request__r.Name + ', ' + l.Absence_Category__c + ' on ' + String.valueOf(l.Date__c)
                    + ' could not be added to the timesheet: ' + l.Sync_Error__c);
            }
        }
        return result;
    }

    // ---------------------------------------------------------------- helpers

    /**
     * @description Appends a line to a long text field and keeps the newest text when it would overflow.
     */
    public static String appendNote(String existing, String line) {
        String text = String.isBlank(existing) ? line : existing + '\n' + line;
        if (text.length() > NOTES_MAX) {
            text = text.right(NOTES_MAX);
        }
        return text;
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
     * @description When the org has an active approval process on PTO_Request__c (deployed separately,
     *              outside the package), send the new request into it so the approver gets the standard
     *              notification. A request with no approver, or that no process accepts, is skipped.
     */
    private static void submitForApproval(PTO_Request__c request) {
        if (request.Approver__c == null) {
            return;
        }
        String objectName = PTO_Request__c.SObjectType.getDescribe().getName();
        Integer active = [
            SELECT COUNT() FROM ProcessDefinition
            WHERE TableEnumOrId = :objectName AND State = 'Active' AND Type = 'Approval'
        ];
        if (active == 0) {
            return;
        }
        Approval.ProcessSubmitRequest req = new Approval.ProcessSubmitRequest();
        req.setObjectId(request.Id);
        req.setSubmitterId(request.OwnerId);
        req.setComments(String.isBlank(request.Notes__c) ? 'Submitted from the PTO tab.' : request.Notes__c.left(4000));
        Approval.process(new List<Approval.ProcessSubmitRequest>{ req }, false);
    }
}
