List<Timesheet__c> ts = [SELECT Id FROM Timesheet__c WHERE Start_Date__c = 2026-08-03 LIMIT 1];
List<Project__c> projects = [SELECT Id FROM Project__c LIMIT 1];
Timesheet_Line_Item__c li = new Timesheet_Line_Item__c(
    Timesheet__c = ts[0].Id,
    Type__c = 'Attendance',
    Project__c = projects[0].Id,
    Activity__c = 'Development',
    Date__c = Date.today(),
    Duration__c = 2,
    Description__c = 'Retry from CLI'
);
String result = WeeklyTimesheetController.upsertLineItems(new List<Timesheet_Line_Item__c>{li});
System.debug(result);
