public with sharing class WeeklyTimesheetController {

    @AuraEnabled(cacheable=true)
    public static Timesheet__c getTimesheet(Id timesheetId){
        System.debug('begin getTimesheet: '+timesheetId);
        Timesheet__c timesheet = [SELECT Id,
                Name,
                Employee__c, 
                Start_Date__c, 
                End_Date__c 
                FROM Timesheet__c 
                WHERE Id = :timesheetId
                WITH SECURITY_ENFORCED];
        System.debug('after getTimesheet: '+timesheet);
        return timesheet;
    }

    @AuraEnabled(cacheable=true)
    public static List<Timesheet__c> getEmployeeTimesheetItems(String empId, String recordId){
        System.debug('begin getEmployeeTimesheetItems: '+empId);
        List<Timesheet__c> emp = [SELECT Id,
                Name,
                Employee__c, 
                Start_Date__c, 
                End_Date__c 
                FROM Timesheet__c 
                WHERE Employee__c = :empId
                AND Id != :recordId
                WITH SECURITY_ENFORCED
                ORDER BY Start_Date__c DESC
                LIMIT 10];
        System.debug('after getEmployeeTimesheetItems: '+emp);
        return emp;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Project_Employee__c> getProjects(String empId, String existingProjectIds){
        System.debug('begin getProjects: '+empId);
        
        List<String> existingIds = new List<String>();
        if(existingProjectIds != null && existingProjectIds != ''){
            existingIds = existingProjectIds.split(',');
        }
        
        List<Project_Employee__c> projects = [SELECT Id,
                Name, 
                Project__c, 
                Project__r.Name,
                Project__r.Billable__c,
                Project__r.Active__c,        
                Employee__c,
                Hourly_Rate__c
                FROM Project_Employee__c 
                WHERE Employee__c = :empId
                AND (Project__r.Active__c = true OR Project__c IN :existingIds)
                WITH SECURITY_ENFORCED];
        
        System.debug('after getProjects: '+projects);
        return projects;
    }

    @AuraEnabled(cacheable=true)
    public static List<Project_Activity__c> getProjectActivities(List<Id> projectIds){
        List<Project_Activity__c> activities = [SELECT Id,
                Name,
                Project__c 
                FROM Project_Activity__c 
                WHERE Project__c IN :projectIds
                WITH SECURITY_ENFORCED];
        return activities;
    }
    
    @AuraEnabled
    public static List<Timesheet_Line_Item__c> getWeeklyTimesheetItems(Id timesheetId){
        System.debug('begin getWeeklyTimesheetItems: '+timesheetId);
        List<Timesheet_Line_Item__c> week = [SELECT Id,
                Type__c, 
                Timesheet__c,
                Date__c,
                Project__c,
                Activity__c,
                Absence_Category__c,
                Description__c,
                Duration__c,
                Project__r.Billable__c
                FROM Timesheet_Line_Item__c
                WHERE Timesheet__c = :timesheetId
                WITH SECURITY_ENFORCED
                ORDER BY Date__c ASC];
        System.debug('after getWeeklyTimesheetItems: '+week);
        return week;
    }
    
    @AuraEnabled
    public static String upsertLineItems(List<Timesheet_Line_Item__c> lineItems) {
        System.debug('begin upsertLineItems: '+lineItems);
        
        if(lineItems == null || lineItems.isEmpty()){
            return 'Error: No Timesheet Line Items provided.';
        }
        
        String result = 'Success';
        try {
            SObjectAccessDecision decision = Security.stripInaccessible(
                AccessType.CREATABLE,
                lineItems,
                true
            );
            upsert decision.getRecords();
        } catch(Exception e) {
            result = 'Error: ' + e.getMessage();
        }
        System.debug('after upsertLineItems: '+result);
        return result;
    }

    @AuraEnabled
    public static String deleteTimesheetLineItems(List<Timesheet_Line_Item__c> lineItemIds) {
        System.debug('begin deleteTimesheetLineItems: '+lineItemIds);

        if(lineItemIds == null || lineItemIds.isEmpty()){
            return 'Error: No Timesheet Line Items provided.';
        }

        try {
            delete as user lineItemIds;
        } catch(Exception e) {
            return 'Error: ' + e.getMessage();
        }
        System.debug('after deleteTimesheetLineItems');
        return 'Success';
    }
}