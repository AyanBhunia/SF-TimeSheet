import re

with open('Timesheet/main/default/classes/TimesheetApprovalController.cls', 'r') as f:
    content = f.read()

# Replace approveTimesheets
content = re.sub(
    r'(?s)// Approves the selected timesheets\..*?public static String approveTimesheets\(List<Id> timesheetIds\)\s*\{.*?(?=// Approves the selected line items\.)',
    '''// Approves the selected timesheets.
@AuraEnabled
public static String approveTimesheets(List<Id> timesheetIds) {
    if (timesheetIds == null || timesheetIds.isEmpty()) {
        return \\'Success\\';
    }
    try {
        List<Timesheet__c> manualUpdate = new List<Timesheet__c>();
        for (Id tsId : timesheetIds) {
            Boolean processed = approveSalesforceApproval(tsId);
            if (!processed) {
                manualUpdate.add(new Timesheet__c(Id = tsId, Status__c = \\'Approved\\'));
            }
        }
        if (!manualUpdate.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, manualUpdate, true);
            update decision.getRecords();
        }
        return \\'Success\\';
    } catch (Exception e) {
        return \\'Error: \\' + e.getMessage();
    }
}
''',
    content
)

# Replace rejectTimesheets
content = re.sub(
    r'(?s)// Rejects the selected timesheets\..*?public static String rejectTimesheets\(List<Id> timesheetIds, String rejectionNotes\)\s*\{.*?(?=// Rejects the selected line items with notes\.)',
    '''// Rejects the selected timesheets.
@AuraEnabled
public static String rejectTimesheets(List<Id> timesheetIds, String rejectionNotes) {
    if (timesheetIds == null || timesheetIds.isEmpty()) {
        return \\'Success\\';
    }
    try {
        List<Timesheet__c> manualUpdate = new List<Timesheet__c>();
        for (Id tsId : timesheetIds) {
            Boolean processed = rejectSalesforceApproval(tsId, rejectionNotes);
            if (!processed) {
                manualUpdate.add(new Timesheet__c(Id = tsId, Status__c = \\'New\\'));
            }
        }
        if (!manualUpdate.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, manualUpdate, true);
            update decision.getRecords();
        }
        return \\'Success\\';
    } catch (Exception e) {
        return \\'Error: \\' + e.getMessage();
    }
}
''',
    content
)

# Replace approveLineItems
content = re.sub(
    r'(?s)// Approves the selected line items\..*?public static String approveLineItems\(List<Id> lineItemIds\)\s*\{.*?(?=// Rejects the selected timesheets\.)',
    '''// Approves the selected line items.
@AuraEnabled
public static String approveLineItems(List<Id> lineItemIds) {
    if (lineItemIds == null || lineItemIds.isEmpty()) {
        return \\'Error: No line items provided.\\';
    }
    try {
        List<Timesheet_Line_Item__c> selectedItems = [
            SELECT Id, Line_Item_Status__c
            FROM Timesheet_Line_Item__c
            WHERE Id IN :lineItemIds
            WITH SECURITY_ENFORCED
        ];
        
        for (Timesheet_Line_Item__c li : selectedItems) {
            li.Line_Item_Status__c = \\'Approved\\';
        }
        
        if (!selectedItems.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE,
                selectedItems,
                true
            );
            update decision.getRecords();
        }
        return \\'Success\\';
    } catch (Exception e) {
        return \\'Error: \\' + e.getMessage();
    }
}
''',
    content
)

# Replace rejectLineItemsWithNotes
content = re.sub(
    r'(?s)// Rejects the selected line items with notes\..*?public static String rejectLineItemsWithNotes\(List<Id> lineItemIds, String rejectionNotes\)\s*\{.*?(?=private static void updateParentSubmittedStatus)',
    '''// Rejects the selected line items with notes.
@AuraEnabled
public static String rejectLineItemsWithNotes(List<Id> lineItemIds, String rejectionNotes) {
    if (lineItemIds == null || lineItemIds.isEmpty()) {
        return \\'Error: No line items provided.\\';
    }
    try {
        List<Timesheet_Line_Item__c> selectedItems = [
            SELECT Id, Line_Item_Status__c, Rejection_Notes__c
            FROM Timesheet_Line_Item__c
            WHERE Id IN :lineItemIds
            WITH SECURITY_ENFORCED
        ];
        
        for (Timesheet_Line_Item__c li : selectedItems) {
            li.Line_Item_Status__c = \\'New\\';
            li.Rejection_Notes__c = rejectionNotes;
        }
        
        if (!selectedItems.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE,
                selectedItems,
                true
            );
            update decision.getRecords();
        }
        return \\'Success\\';
    } catch (Exception e) {
        return \\'Error: \\' + e.getMessage();
    }
}
''',
    content
)

# Delete updateParentSubmittedStatus and updateParentPartialStatus
content = re.sub(
    r'(?s)private static void updateParentSubmittedStatus\(Set<Id> timesheetIds\)\s*\{.*?(?=// Approves the pending Salesforce approval request)',
    '',
    content
)

# Replace approveSalesforceApproval
content = re.sub(
    r'(?s)// Approves the pending Salesforce approval request\..*?private static void approveSalesforceApproval\(Id timesheetId\)\s*\{.*?(?=// Rejects the pending Salesforce approval request)',
    '''// Approves the pending Salesforce approval request.
private static Boolean approveSalesforceApproval(Id timesheetId) {
    List<ProcessInstanceWorkitem> pendingWorkItems = [
        SELECT Id
        FROM ProcessInstanceWorkitem
        WHERE ProcessInstance.TargetObjectId = :timesheetId
        AND ProcessInstance.Status = \\'Pending\\'
    ];
    if (pendingWorkItems.isEmpty()) {
        return false;
    }
    for (ProcessInstanceWorkitem wi : pendingWorkItems) {
        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setComments(\\'Approved by Manager\\');
        req.setAction(\\'Approve\\');
        req.setWorkitemId(wi.Id);
        Approval.ProcessResult result = Approval.process(req);
    }
    return true;
}
''',
    content
)

# Replace rejectSalesforceApproval
content = re.sub(
    r'(?s)// Rejects the pending Salesforce approval request\..*?private static void rejectSalesforceApproval\(Id timesheetId, String rejectionNotes\)\s*\{.*?\}(?=\s*$)',
    '''// Rejects the pending Salesforce approval request.
private static Boolean rejectSalesforceApproval(Id timesheetId, String rejectionNotes) {
    List<ProcessInstanceWorkitem> pendingWorkItems = [
        SELECT Id
        FROM ProcessInstanceWorkitem
        WHERE ProcessInstance.TargetObjectId = :timesheetId
        AND ProcessInstance.Status = \\'Pending\\'
    ];
    if (pendingWorkItems.isEmpty()) {
        return false;
    }
    for (ProcessInstanceWorkitem wi : pendingWorkItems) {
        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setComments(rejectionNotes);
        req.setAction(\\'Reject\\');
        req.setWorkitemId(wi.Id);
        Approval.ProcessResult result = Approval.process(req);
    }
    return true;
}''',
    content
)

with open('Timesheet/main/default/classes/TimesheetApprovalController.cls', 'w') as f:
    f.write(content)
