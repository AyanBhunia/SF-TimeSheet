/**
 * @description Invocable action used by the "In-app Guidence using STF" flow to save permission set
 *              assignments with partial success. A user who cannot receive the permission set (for
 *              example because of the user license) fails alone; the other users still get it.
 * @author Ayan
 */
public inherited sharing class SavePermissionSetAssignments {

    /**
     * @description Flow input: assignments to insert and assignments to update
     */
    public class Request {
        @InvocableVariable(label='Assignments To Insert')
        public List<PermissionSetAssignment> toInsert;

        @InvocableVariable(label='Assignments To Update')
        public List<PermissionSetAssignment> toUpdate;
    }

    /**
     * @description Flow output: how many rows were saved and why the others failed
     */
    public class Response {
        @InvocableVariable(label='Inserted')
        public Integer inserted = 0;

        @InvocableVariable(label='Updated')
        public Integer updated = 0;

        @InvocableVariable(label='Failed')
        public Integer failed = 0;

        @InvocableVariable(label='Errors')
        public String errors = '';
    }

    /**
     * @description Inserts and updates the assignments with allOrNone = false
     * @param requests One request per flow interview
     * @return List<Response> One response per request
     */
    @InvocableMethod(
        label='Save Permission Set Assignments (Partial)'
        description='Inserts and updates permission set assignments; rows that fail are skipped and reported.'
        category='Timesheet'
    )
    public static List<Response> save(List<Request> requests) {
        List<Response> responses = new List<Response>();
        for (Request request : requests) {
            Response response = new Response();
            // System mode: runs from a scheduled flow (automated process user) for all users.
            if (request.toUpdate != null && !request.toUpdate.isEmpty()) {
                collect(Database.update(request.toUpdate, false, AccessLevel.SYSTEM_MODE), request.toUpdate, response, false);
            }
            if (request.toInsert != null && !request.toInsert.isEmpty()) {
                collect(Database.insert(request.toInsert, false, AccessLevel.SYSTEM_MODE), request.toInsert, response, true);
            }
            if (response.failed > 0) {
                System.debug(LoggingLevel.WARN, 'SavePermissionSetAssignments: ' + response.failed + ' row(s) failed. ' + response.errors);
            }
            responses.add(response);
        }
        return responses;
    }

    private static void collect(List<Database.SaveResult> results, List<PermissionSetAssignment> rows, Response response, Boolean isInsert) {
        for (Integer i = 0; i < results.size(); i++) {
            if (results[i].isSuccess()) {
                if (isInsert) {
                    response.inserted++;
                } else {
                    response.updated++;
                }
                continue;
            }
            response.failed++;
            String user = rows[i].AssigneeId != null ? String.valueOf(rows[i].AssigneeId) : String.valueOf(rows[i].Id);
            for (Database.Error error : results[i].getErrors()) {
                response.errors += user + ': ' + error.getStatusCode() + ' ' + error.getMessage() + '\n';
            }
        }
    }
}
