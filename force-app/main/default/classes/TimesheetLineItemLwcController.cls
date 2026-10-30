public with sharing class TimesheetLineItemLwcController {
    private static string errorMessage = 'You do not have access, please contact System Admin';
    
    @AuraEnabled(cacheable=true)
    public static List<Timesheet_Line_Item__c> getTimesheetLineItems(Id timesheetId){
        List<Timesheet_Line_Item__c> timesheetLineItemList = new List<Timesheet_Line_Item__c>();
        if(Timesheet_Line_Item__c.SObjectType.getDescribe().isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Id.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Type__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Timesheet__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Date__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Project__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Activity__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Absence_Category__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Description__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Duration__c.isAccessible() ){
                timesheetLineItemList = [SELECT Id,
                                            Type__c,
                                            Timesheet__c,
                                            Date__c,
                                            Project__c,
                                            Activity__c,
                                            Absence_Category__c,
                                            Description__c,
                                            Duration__c
                                            FROM Timesheet_Line_Item__c
                                            WHERE Timesheet__c=:timesheetId
                                            with SECURITY_ENFORCED
                                            ORDER BY Date__c ASC];
        } else{
            AuraHandledException ae = new AuraHandledException(errorMessage);
            ae.setMessage(errorMessage);
            throw ae;
        }
        return timesheetLineItemList;
    }
    
    @AuraEnabled
    public static void updateTimesheetLineItems(List<Timesheet_Line_Item__c> timesheetLineItems, String[] idsToDelete){
        if(idsToDelete != null && idsToDelete.size() > 0){
            deleteTimesheetLineItems(idsToDelete);
        }
        if(timesheetLineItems != null && timesheetLineItems.size() >0){
            upsertTimesheetRecords(timesheetLineItems);
        }
    }

    private static void upsertTimesheetRecords(List<Timesheet_Line_Item__c> timesheetLineItems){
        if(Timesheet_Line_Item__c.SObjectType.getDescribe().isCreateable() 
            && Timesheet_Line_Item__c.SObjectType.getDescribe().isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Type__c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Date__c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Project__c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Activity__c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Absence_Category__c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Duration__c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Description__c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Type__c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Timesheet__c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Date__c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Project__c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Activity__c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Absence_Category__c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Duration__c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Description__c.isCreateable()){
                upsert timesheetLineItems;
        } else{
            AuraHandledException ae = new AuraHandledException(errorMessage);
            ae.setMessage(errorMessage);
            throw ae;
        }
    }

    private static void deleteTimesheetLineItems(String[] timesheetIds){
        if(Timesheet_Line_Item__c.SObjectType.getDescribe().isDeletable() 
            && Timesheet_Line_Item__c.SObjectType.getDescribe().isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Id.isAccessible() ){
                List<Timesheet_Line_Item__c> timesheetLineItems = [SELECT Id from Timesheet_Line_Item__c WHERE Id = : timesheetIds WITH SECURITY_ENFORCED];
                delete timesheetLineItems;
        } else{
            AuraHandledException ae = new AuraHandledException(errorMessage);
            ae.setMessage(errorMessage);
            throw ae;
        }
    }
}