public inherited sharing class TimesheetService {
    
    public static void upsertLineItems(List<Timesheet_Line_Item__c> lineItems) {
        if(lineItems == null || lineItems.isEmpty()) return;
        
        SObjectAccessDecision decision = Security.stripInaccessible(
            AccessType.UPSERTABLE,
            lineItems,
            true
        );
        upsert decision.getRecords();
    }

    public static void deleteLineItems(List<Timesheet_Line_Item__c> lineItems) {
        if(lineItems == null || lineItems.isEmpty()) return;
        
        // Ensure user has delete access
        if(Timesheet_Line_Item__c.sObjectType.getDescribe().isDeletable()) {
            delete lineItems;
        } else {
            throw new AuraHandledException('You do not have permission to delete Timesheet Line Items.');
        }
    }
}
