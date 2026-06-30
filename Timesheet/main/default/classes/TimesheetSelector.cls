public inherited sharing class TimesheetSelector {
    
    public static List<Timesheet__c> getTimesheetsByIds(Set<Id> timesheetIds) {
        return [SELECT Id, Name, Employee__c, Start_Date__c, End_Date__c, Status__c, 
                       Total_Hours__c, Billable_Hours__c, Absence_Hours__c 
                FROM Timesheet__c 
                WHERE Id IN :timesheetIds
                WITH SECURITY_ENFORCED];
    }

    public static List<Timesheet__c> getTimesheetsByEmployeeId(Id employeeId, Integer limitSize) {
        return [SELECT Id, Name, Employee__c, Start_Date__c, End_Date__c, Status__c, Total_Hours__c
                FROM Timesheet__c 
                WHERE Employee__c = :employeeId
                WITH SECURITY_ENFORCED
                ORDER BY Start_Date__c DESC
                LIMIT :limitSize];
    }
    
    public static List<Timesheet_Line_Item__c> getLineItemsByTimesheetId(Id timesheetId) {
        return [SELECT Id, Type__c, Timesheet__c, Date__c, Project__c, Project__r.Name, Activity__c,
                       Absence_Category__c, Description__c, Duration__c, Project__r.Billable__c
                FROM Timesheet_Line_Item__c
                WHERE Timesheet__c = :timesheetId
                WITH SECURITY_ENFORCED
                ORDER BY Date__c ASC];
    }
}
