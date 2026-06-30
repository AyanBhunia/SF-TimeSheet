trigger TimesheetLineItemTrigger on Timesheet_Line_Item__c (before insert, before update) {
    new TimesheetLineItemTriggerHandler().run();
}