public with sharing class TimesheetLineItemLwcController {
    private static string errorMessage = 'You do not have access, please contact System Admin';
    
    @AuraEnabled(cacheable=true)
    public static List<Timesheet_Line_Item__c> getTimesheetLineItems(Id timesheetId){
        try{
            return [SELECT Id, Type__c, Timesheet__c, Date__c, Project__c, Activity__c, Absence_Category__c, Description__c, Duration__c FROM Timesheet_Line_Item__c WHERE Timesheet__c=:timesheetId WITH SECURITY_ENFORCED ORDER BY Date__c ASC];
        } catch (Exception e){
            AuraHandledException ae = new AuraHandledException(errorMessage);
            ae.setMessage(errorMessage);
            throw ae;
        }
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
        try{
            SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.UPSERTABLE, timesheetLineItems);
            upsert securityDecision.getRecords();
        } catch (Exception e){
            AuraHandledException ae = new AuraHandledException(errorMessage);
            ae.setMessage(errorMessage);
            throw ae;
        }
    }

    private static void deleteTimesheetLineItems(String[] timesheetIds){
        try{
            List<Timesheet_Line_Item__c> timesheetLineItems = [SELECT Id from Timesheet_Line_Item__c WHERE Id IN : timesheetIds WITH SECURITY_ENFORCED];
            if(Timesheet_Line_Item__c.SObjectType.getDescribe().isDeletable()){
                delete timesheetLineItems;
            } else {
                throw new AuraHandledException(errorMessage);
            }
        } catch (Exception e){
            AuraHandledException ae = new AuraHandledException(errorMessage);
            ae.setMessage(errorMessage);
            throw ae;
        }
    }
}