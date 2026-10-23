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

    public class SaveResult {
        @AuraEnabled public Boolean success;
        @AuraEnabled public String message;
        @AuraEnabled public Integer keptTimerRows; // rows left in place because a timer runs on them

        SaveResult(Boolean success, String message, Integer keptTimerRows) {
            this.success = success;
            this.message = message;
            this.keptTimerRows = keptTimerRows;
        }
    }

    /**
     * @description Saves the weekly grid in one transaction: the rows removed from the grid are deleted, then the
     *              rest is upserted. Any failure rolls everything back, so a rejected row can never leave the
     *              week half saved. A deleted row must still have the hours the grid loaded (a timer save or a
     *              leave approval changed it otherwise), and a row with a running timer is never deleted.
     * @param deletes rows to delete: Id and the Duration__c the grid loaded
     * @param loadedHours Duration__c the grid loaded for the existing rows it edits (Id => hours). An edit is refused
     *                    when the row has other hours now, so a stale grid never overwrites what a timer saved meanwhile.
     */
    @AuraEnabled
    public static SaveResult saveWeek(List<Timesheet_Line_Item__c> upserts, List<Timesheet_Line_Item__c> deletes, Map<Id, Decimal> loadedHours) {
        upserts = upserts == null ? new List<Timesheet_Line_Item__c>() : upserts;
        deletes = deletes == null ? new List<Timesheet_Line_Item__c>() : deletes;
        if (upserts.isEmpty() && deletes.isEmpty()) {
            return new SaveResult(true, null, 0);
        }

        Savepoint sp = Database.setSavepoint();
        try {
            // System mode on purpose: this only narrows what is deleted, and must work without FLS on Timer_Data__c.
            Map<Id, Timesheet_Line_Item__c> current = new Map<Id, Timesheet_Line_Item__c>();
            Set<Id> timesheetIds = new Set<Id>();
            for (Timesheet_Line_Item__c item : upserts) {
                if (item.Timesheet__c != null) {
                    timesheetIds.add(item.Timesheet__c);
                }
            }
            for (Timesheet_Line_Item__c row : [
                SELECT Id, Duration__c, Timer_Data__c, Timesheet__c, Project__c, Activity__c, Date__c, Project__r.Name
                FROM Timesheet_Line_Item__c
                WHERE (Id IN :deletes OR Id IN :upserts OR (Timesheet__c IN :timesheetIds AND Timer_Data__c != null))
                WITH SYSTEM_MODE
            ]) {
                current.put(row.Id, row);
            }

            // A submitted or approved timesheet is closed: its hours change only after it has been reopened.
            // The timesheet of an existing row is read from the saved row, not from what the client sent.
            Set<Id> sheetIds = new Set<Id>(timesheetIds);
            for (Timesheet_Line_Item__c item : deletes) {
                Timesheet_Line_Item__c row = current.get(item.Id);
                if (row != null && row.Timesheet__c != null) {
                    sheetIds.add(row.Timesheet__c);
                }
            }
            for (Timesheet_Line_Item__c item : upserts) {
                Timesheet_Line_Item__c row = item.Id == null ? null : current.get(item.Id);
                if (row != null && row.Timesheet__c != null) {
                    sheetIds.add(row.Timesheet__c);
                }
            }
            for (Timesheet__c sheet : [
                SELECT Id, Status__c FROM Timesheet__c
                WHERE Id IN :sheetIds AND Status__c IN ('Submitted', 'Approved')
                WITH SYSTEM_MODE
            ]) {
                return failed(sp, 'This timesheet is already ' + sheet.Status__c.toLowerCase()
                    + ', so its hours cannot be changed here. Ask your manager or HR to reopen it first. Nothing was saved.');
            }

            // A new row for a project + activity + day that already has a running timer would be a duplicate.
            for (Timesheet_Line_Item__c item : upserts) {
                for (Timesheet_Line_Item__c row : current.values()) {
                    if (row.Timer_Data__c != null && item.Id != row.Id && item.Timesheet__c == row.Timesheet__c
                        && item.Project__c == row.Project__c && item.Activity__c == row.Activity__c
                        && item.Date__c == row.Date__c) {
                        return failed(sp, 'A timer is running on ' + row.Project__r.Name + ' / ' + row.Activity__c + ' for '
                            + row.Date__c.format() + '. Save or discard the timer first, then save the timesheet again. Nothing was saved.');
                    }
                }
            }

            if (loadedHours != null) {
                for (Timesheet_Line_Item__c item : upserts) {
                    Timesheet_Line_Item__c row = item.Id == null ? null : current.get(item.Id);
                    if (row != null && loadedHours.containsKey(item.Id)) {
                        Decimal loaded = loadedHours.get(item.Id) == null ? 0 : loadedHours.get(item.Id);
                        if ((row.Duration__c == null ? 0 : row.Duration__c) != loaded) {
                            return failed(sp, 'A row was changed elsewhere after you opened the timesheet (for example by the timer or an approved leave). Reload the timesheet and try again. Nothing was saved.');
                        }
                    }
                }
            }

            List<Timesheet_Line_Item__c> toDelete = new List<Timesheet_Line_Item__c>();
            Integer kept = 0;
            for (Timesheet_Line_Item__c item : deletes) {
                Timesheet_Line_Item__c row = current.get(item.Id);
                if (row == null) {
                    continue; // already gone
                }
                if (row.Timer_Data__c != null) {
                    kept++;
                    continue;
                }
                Decimal now = row.Duration__c == null ? 0 : row.Duration__c;
                Decimal loaded = item.Duration__c == null ? 0 : item.Duration__c;
                if (now != loaded) {
                    return failed(sp, 'A row was changed elsewhere after you opened the timesheet (for example by the timer or an approved leave). Reload the timesheet and try again. Nothing was saved.');
                }
                toDelete.add(row);
            }
            if (!toDelete.isEmpty()) {
                delete as user toDelete;
            }
            if (!upserts.isEmpty()) {
                SObjectAccessDecision decision = Security.stripInaccessible(AccessType.CREATABLE, upserts, true);
                upsert decision.getRecords();
            }
            return new SaveResult(true, null, kept);
        } catch (Exception e) {
            return failed(sp, (e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage()) + ' Nothing was saved.');
        }
    }

    private static SaveResult failed(Savepoint sp, String message) {
        Database.rollback(sp);
        return new SaveResult(false, message, 0);
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