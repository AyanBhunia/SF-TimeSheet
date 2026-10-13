const fs = require('fs');

let content = fs.readFileSync('Timesheet/main/default/classes/TimesheetApprovalController.cls', 'utf8');

content = content.replace(
    /\/\/ Approves the selected timesheets\..*?public static void approveTimesheets\(List<Id> timesheetIds\)\s*\{.*?\}\s*\}/s,
    // Approves the selected timesheets.
@AuraEnabled
public static String approveTimesheets(List<Id> timesheetIds) {
    if (timesheetIds == null || timesheetIds.isEmpty()) {
        return 'Success';
    }
    try {
        List<Timesheet__c> manualUpdate = new List<Timesheet__c>();
        for (Id tsId : timesheetIds) {
            Boolean processed = approveSalesforceApproval(tsId);
            if (!processed) {
                manualUpdate.add(new Timesheet__c(Id = tsId, Status__c = 'Approved'));
            }
        }
        if (!manualUpdate.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, manualUpdate, true);
            update decision.getRecords();
        }
        return 'Success';
    } catch (Exception e) {
        return 'Error: ' + e.getMessage();
    }
}
);

content = content.replace(
    /\/\/ Rejects the selected timesheets\..*?public static void rejectTimesheets\(.*?\s*\}/s,
    // Rejects the selected timesheets.
@AuraEnabled
public static String rejectTimesheets(List<Id> timesheetIds, String rejectionNotes) {
    if (timesheetIds == null || timesheetIds.isEmpty()) {
        return 'Success';
    }
    try {
        List<Timesheet__c> manualUpdate = new List<Timesheet__c>();
        for (Id tsId : timesheetIds) {
            Boolean processed = rejectSalesforceApproval(tsId, rejectionNotes);
            if (!processed) {
                manualUpdate.add(new Timesheet__c(Id = tsId, Status__c = 'New'));
            }
        }
        if (!manualUpdate.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, manualUpdate, true);
            update decision.getRecords();
        }
        return 'Success';
    } catch (Exception e) {
        return 'Error: ' + e.getMessage();
    }
}
);

content = content.replace(
    /\/\/ Approves the selected line items\..*?public static String approveLineItems\(List<Id> lineItemIds\)\s*\{.*?\}\s*\}/s,
    // Approves the selected line items.
@AuraEnabled
public static String approveLineItems(List<Id> lineItemIds) {
    if (lineItemIds == null || lineItemIds.isEmpty()) {
        return 'Error: No line items provided.';
    }
    try {
        List<Timesheet_Line_Item__c> selectedItems = [
            SELECT Id, Line_Item_Status__c
            FROM Timesheet_Line_Item__c
            WHERE Id IN :lineItemIds
            WITH SECURITY_ENFORCED
        ];
        
        for (Timesheet_Line_Item__c li : selectedItems) {
            li.Line_Item_Status__c = 'Approved';
        }
        
        if (!selectedItems.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.UPDATABLE,
                selectedItems,
                true
            );
            update decision.getRecords();
        }
        return 'Success';
    } catch (Exception e) {
        return 'Error: ' + e.getMessage();
    }
}
);

content = content.replace(
    /\/\/ Rejects the selected line items with notes\..*?public static String rejectLineItemsWithNotes\(List<Id> lineItemIds, String rejectionNotes\)\s*\{.*?\}\s*\}\s*private static void updateParentSubmittedStatus/s,
    // Rejects the selected line items with notes.
@AuraEnabled
public static String rejectLineItemsWithNotes(List<Id> lineItemIds, String rejectionNotes) {
    if (lineItemIds == null || lineItemIds.isEmpty()) {
        return 'Error: No line items provided.';
    }
    try {
        List<Timesheet_Line_Item__c> selectedItems = [
            SELECT Id, Line_Item_Status__c, Rejection_Notes__c
            FROM Timesheet_Line_Item__c
            WHERE Id IN :lineItemIds
            WITH SECURITY_ENFORCED
        ];
        
        for (Timesheet_Line_Item__c li : selectedItems) {
            li.Line_Item_Status__c = 'New';
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
        return 'Success';
    } catch (Exception e) {
        return 'Error: ' + e.getMessage();
    }
}
private static void updateParentSubmittedStatus
);

content = content.replace(
    /private static void updateParentSubmittedStatus\(Set<Id> timesheetIds\)\s*\{.*?\/\/ Approves the pending Salesforce approval request\./s,
    // Approves the pending Salesforce approval request.
);

content = content.replace(
    /\/\/ Approves the pending Salesforce approval request\..*?private static void approveSalesforceApproval\(Id timesheetId\)\s*\{.*?\/\/ Rejects the pending Salesforce approval request\./s,
    // Approves the pending Salesforce approval request.
private static Boolean approveSalesforceApproval(Id timesheetId) {
    List<ProcessInstanceWorkitem> pendingWorkItems = [
        SELECT Id
        FROM ProcessInstanceWorkitem
        WHERE ProcessInstance.TargetObjectId = :timesheetId
        AND ProcessInstance.Status = 'Pending'
    ];
    if (pendingWorkItems.isEmpty()) {
        return false;
    }
    for (ProcessInstanceWorkitem wi : pendingWorkItems) {
        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setComments('Approved by Manager');
        req.setAction('Approve');
        req.setWorkitemId(wi.Id);
        Approval.ProcessResult result = Approval.process(req);
    }
    return true;
}
// Rejects the pending Salesforce approval request.
);

content = content.replace(
    /\/\/ Rejects the pending Salesforce approval request\..*?private static void rejectSalesforceApproval\(Id timesheetId, String rejectionNotes\)\s*\{.*?\}\s*$/s,
    // Rejects the pending Salesforce approval request.
private static Boolean rejectSalesforceApproval(Id timesheetId, String rejectionNotes) {
    List<ProcessInstanceWorkitem> pendingWorkItems = [
        SELECT Id
        FROM ProcessInstanceWorkitem
        WHERE ProcessInstance.TargetObjectId = :timesheetId
        AND ProcessInstance.Status = 'Pending'
    ];
    if (pendingWorkItems.isEmpty()) {
        return false;
    }
    for (ProcessInstanceWorkitem wi : pendingWorkItems) {
        Approval.ProcessWorkitemRequest req = new Approval.ProcessWorkitemRequest();
        req.setComments(rejectionNotes);
        req.setAction('Reject');
        req.setWorkitemId(wi.Id);
        Approval.ProcessResult result = Approval.process(req);
    }
    return true;
}
}
);

fs.writeFileSync('Timesheet/main/default/classes/TimesheetApprovalController.cls', content);
