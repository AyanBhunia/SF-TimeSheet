public with sharing class TimesheetLineItemController {
    
    @AuraEnabled(cacheable=true)
    public static List<Timesheet_Line_Item__c> getTimesheetLineItems(Id processInstanceWorkItemId){
        try{
            ProcessInstanceWorkItem piwi = [SELECT Id, ProcessInstanceId FROM ProcessInstanceWorkItem WHERE Id = : ProcessInstanceWorkItemId WITH SECURITY_ENFORCED];
            ProcessInstance pi = [SELECT Id, TargetObjectId FROM ProcessInstance WHERE Id = : piwi.ProcessInstanceId WITH SECURITY_ENFORCED];
            return [SELECT Id, Name, Type__c, Date__c, Duration__c, Project__c, Project__r.Name, Activity__c FROM Timesheet_Line_Item__c WHERE Timesheet__c = : pi.TargetObjectId WITH SECURITY_ENFORCED ORDER BY Date__c ASC ];
        } catch (Exception e){
            String errorMessage = 'You do not have access, please contact system admin';
            AuraHandledException ae = new AuraHandledException(errorMessage);
            ae.setMessage(errorMessage);
            throw ae;
        }
    }
}