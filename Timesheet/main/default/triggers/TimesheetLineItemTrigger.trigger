trigger TimesheetLineItemTrigger on Timesheet_Line_Item__c (before insert, before update, after insert, after update, after delete, after undelete) {
    new TimesheetLineItemTriggerHandler().run();
}