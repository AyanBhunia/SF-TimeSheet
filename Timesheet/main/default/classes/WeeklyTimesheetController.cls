public with sharing class WeeklyTimesheetController {

     @AuraEnabled(cacheable=true)
    public static Timesheet__c getTimesheet(Id timesheetId){
        System.debug('begin getTimesheet: '+timesheetId);
        Timesheet__c timesheet = [select Id,
                name,
                Employee__c, 
                Start_Date__c, 
                End_Date__c 
                from Timesheet__c 
                WHERE Id = :timesheetId
                WITH SECURITY_ENFORCED];


        System.debug('after getTimesheet: '+timesheet);
        return timesheet;
    }

    @AuraEnabled(cacheable=true)
    public static List<Timesheet__c> getEmployeeTimesheetItems(String empId, String recordId){
        System.debug('begin getEmployeeTimesheetItems: '+empId);
        List<Timesheet__c> emp = [select Id,
                Name,
                Employee__c, 
                Start_Date__c, 
                End_Date__c 
                from Timesheet__c 
                WHERE Employee__c = :empId
                and id != :recordId
                WITH SECURITY_ENFORCED
                ORDER BY Start_Date__c DESC
                LIMIT 10
                ];

        System.debug('after getEmployeeTimesheetItems: '+emp);
        return emp;
    }
    
    @AuraEnabled(cacheable=true)
    public static List<Project_Employee__c> getProjects(String empId){
        System.debug('begin getProjects: '+empId);
        List<Project_Employee__c> projects = [SELECT Id,
                Name, 
                Project__c, 
                Project__r.Name, 
                Employee__c,
                Hourly_Rate__c,
                Project__r.Billable__c
                FROM Project_Employee__c 
                WHERE Employee__c = :empId
                WITH SECURITY_ENFORCED];
        
                System.debug('after getProjects: '+projects);
                return projects;
    }

    @AuraEnabled(cacheable=true)
    public static List<Project_Activity__c> getProjectActivities(List<Id> projectIds){
        // system.debug('begin getProjectActivities: '+projectIds);
        List<Project_Activity__c> activities = [SELECT id,
                name,
                Project__c 
                FROM Project_Activity__c 
                WHERE Project__c IN :projectIds
                WITH SECURITY_ENFORCED];
        // system.debug('after getProjectActivities: '+activities);

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
            SObjectAccessDecision decision =
            Security.stripInaccessible(
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
            // The weekly grid deletes rows it shows with 0 hours; never delete a row with a running timer.
            // System mode on purpose: this only narrows what gets deleted, and must work without FLS on Timer_Data__c.
            Map<Id, Timesheet_Line_Item__c> runningTimers = new Map<Id, Timesheet_Line_Item__c>([
                SELECT Id FROM Timesheet_Line_Item__c
                WHERE Id IN :lineItemIds AND Timer_Data__c != null
                WITH SYSTEM_MODE
            ]);
            List<Timesheet_Line_Item__c> toDelete = new List<Timesheet_Line_Item__c>();
            for (Timesheet_Line_Item__c item : lineItemIds) {
                if (!runningTimers.containsKey(item.Id)) {
                    toDelete.add(item);
                }
            }
            delete as user toDelete;
        } catch(Exception e) {
            return 'Error: ' + e.getMessage();
        }
        System.debug('after deleteTimesheetLineItems');
        return 'Success';
    }

}