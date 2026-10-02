/**
 * @description Invocable action used by the "In-app Guidence using STF" flow to fetch permission set
 *              assignments with ALL ROWS. Expired assignments are soft deleted by the platform and are
 *              not returned by a standard Get Records element, which caused the flow to try to insert a
 *              duplicate assignment. Querying with ALL ROWS lets the flow update those records instead.
 * @author Ayan
 */
public inherited sharing class GetPermissionSetAssignments {

    /**
     * @description Returns the permission set assignments (including expired / soft deleted ones)
     * @param permissionSetIds Permission set Ids from the flow
     * @return List<List<PermissionSetAssignment>> One list of assignments per permission set Id
     */
    @InvocableMethod(
        label='Get Permission Set Assignments (All Rows)'
        description='Returns permission set assignments for a permission set, including expired (soft deleted) assignments.'
        category='Timesheet'
    )
    public static List<List<PermissionSetAssignment>> getAssignments(List<Id> permissionSetIds) {
        List<List<PermissionSetAssignment>> results = new List<List<PermissionSetAssignment>>();

        for (Id permissionSetId : permissionSetIds) {
            // System mode: this runs from a scheduled flow (automated process user) that manages
            // Timesheet_Reminder_Access assignments on behalf of all users.
            results.add([
                SELECT Id, AssigneeId, PermissionSetId, ExpirationDate
                FROM PermissionSetAssignment
                WHERE PermissionSetId = :permissionSetId
                WITH SYSTEM_MODE
                ALL ROWS
            ]);
        }

        return results;
    }
}
