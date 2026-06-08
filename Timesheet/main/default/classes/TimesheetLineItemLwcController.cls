public with sharing class TimesheetLineItemLwcController {
    private static string errorMessage = 'You do not have access, please contact System Admin';
    
    @AuraEnabled(cacheable=true)
    public static List<Timesheet_Line_Item__c> getTimesheetLineItems(Id timesheetId){
        List<Timesheet_Line_Item_c> timesheetLineItemList = new List<Timesheet_Line_Item_c>();
        if(Timesheet_Line_Item__c.SObjectType.getDescribe().isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Id.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Type_c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Timesheet_c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Date_c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Project_c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Activity_c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Absence_Category_c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Description_c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Duration_c.isAccessible() ){
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
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Type_c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Date_c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Project_c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Activity_c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Absence_Category_c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Duration_c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Description_c.isUpdateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Type_c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Timesheet_c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Date_c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Project_c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Activity_c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Absence_Category_c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Duration_c.isCreateable() 
            && Schema.SObjectType.Timesheet_Line_Item_c.fields.Description_c.isCreateable()){
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
                List<Timesheet_Line_Item_c> timesheetLineItems = [SELECT Id from Timesheet_Line_Item_c WHERE Id = : timesheetIds WITH SECURITY_ENFORCED];
                delete timesheetLineItems;
        } else{
            AuraHandledException ae = new AuraHandledException(errorMessage);
            ae.setMessage(errorMessage);
            throw ae;
        }
    }
}