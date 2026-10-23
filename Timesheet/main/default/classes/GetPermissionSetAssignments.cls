/**
 * @description Invocable action used by the "In-app Guidence using STF" flow to fetch permission set
 *              assignments with ALL ROWS. Expired assignments are hidden from a standard Get Records
 *              element but still block a new insert (DUPLICATE_VALUE). Querying with ALL ROWS lets the
 *              flow update those records instead. Only the given users' assignments are returned.
 * @author Ayan
 */
public inherited sharing class GetPermissionSetAssignments {

    /**
     * @description Flow input: the permission set and the users to look up
     */
    public class Request {
        @InvocableVariable(label='Permission Set Id' required=true)
        public Id permissionSetId;

        @InvocableVariable(label='User Ids' required=true)
        public List<String> userIds;
    }

    /**
     * @description Flow output: the matching assignments (active and expired)
     */
    public class Response {
        @InvocableVariable(label='Assignments')
        public List<PermissionSetAssignment> assignments;
    }

    /**
     * @description Returns the permission set assignments of the given users, including expired ones
     * @param requests One request per flow interview
     * @return List<Response> One response per request
     */
    @InvocableMethod(
        label='Get Permission Set Assignments (All Rows)'
        description='Returns the given users\' assignments of a permission set, including expired assignments.'
        category='Timesheet'
    )
    public static List<Response> getAssignments(List<Request> requests) {
        Set<Id> permissionSetIds = new Set<Id>();
        Set<Id> userIds = new Set<Id>();
        for (Request request : requests) {
            if (request.permissionSetId == null || request.userIds == null) {
                continue;
            }
            permissionSetIds.add(request.permissionSetId);
            userIds.addAll(toIdSet(request.userIds));
        }

        // System mode: this runs from a scheduled flow (automated process user) that manages
        // Timesheet_Reminder_Access assignments on behalf of all users. One query for all requests.
        List<PermissionSetAssignment> found = new List<PermissionSetAssignment>();
        if (!permissionSetIds.isEmpty() && !userIds.isEmpty()) {
            found = [
                SELECT Id, AssigneeId, PermissionSetId, ExpirationDate
                FROM PermissionSetAssignment
                WHERE PermissionSetId IN :permissionSetIds
                AND AssigneeId IN :userIds
                WITH SYSTEM_MODE
                ALL ROWS
            ];
        }

        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            Response response = new Response();
            response.assignments = new List<PermissionSetAssignment>();
            Set<Id> requestUsers = toIdSet(request.userIds);
            for (PermissionSetAssignment assignment : found) {
                if (assignment.PermissionSetId == request.permissionSetId
                        && requestUsers.contains(assignment.AssigneeId)) {
                    response.assignments.add(assignment);
                }
            }
            responses.add(response);
        }
        return responses;
    }

    private static Set<Id> toIdSet(List<String> values) {
        Set<Id> ids = new Set<Id>();
        if (values == null) {
            return ids;
        }
        for (String value : values) {
            if (String.isNotBlank(value)) {
                ids.add(Id.valueOf(value));
            }
        }
        return ids;
    }
}
