public with sharing class TimesheetLineItemController {
    
    @AuraEnabled(cacheable=true)
    public static List<Timesheet_Line_Item__c> getTimesheetLineItems(Id processInstanceWorkItemId){
        List<Timesheet_Line_Item__c> timesheetLineItems = new List<Timesheet_Line_Item__c>();
        if(Timesheet_Line_Item__c.SObjectType.getDescribe().isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Id.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Name.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Type__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Date__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Duration__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Project__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Activity__c.isAccessible()){
                ProcessInstanceWorkItem piwi = [SELECT
                                                Id,
                                                ProcessInstanceId
                                                FROM ProcessInstanceWorkItem 
                                                WHERE Id = : ProcessInstanceWorkItemId 
                                                WITH SECURITY_ENFORCED];
                ProcessInstance pi = [SELECT
                                    Id, 
                                    TargetObjectId 
                                    FROM ProcessInstance 
                                    WHERE Id = : piwi.ProcessInstanceId 
                                    WITH SECURITY_ENFORCED];
                timesheetLineItems = [SELECT
                                    Id, 
                                    Name, 
                                    Type__c, 
                                    Date__c, 
                                    Duration__c, 
                                    Project__c, 
                                    Project__r.Name, 
                                    Activity__c 
                                    FROM Timesheet_Line_Item__c 
                                    WHERE Timesheet__c = : pi.TargetObjectId 
                                    WITH SECURITY_ENFORCED 
                                    ORDER BY Date__c ASC ];
        } else{
            String errorMessage = 'You do not have access, please contact system admin';
            AuraHandledException ae = new AuraHandledException(errorMessage);
            ae.setMessage(errorMessage);
            throw ae;
        }
        return timesheetLineItems;
    }
}