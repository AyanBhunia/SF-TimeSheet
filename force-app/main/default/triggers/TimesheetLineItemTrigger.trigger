trigger TimesheetLineItemTrigger on Timesheet_Line_Item__c (before insert, before update) {
    
    if(Trigger.isInsert && Trigger.isBefore){
        
        TimesheetLineItemTriggerHandler.beforeInsert(Trigger.New);
        
    } else if(Trigger.isUpdate && Trigger.isBefore){
        
        TimesheetLineItemTriggerHandler.beforeUpdate(Trigger.New);
    }
}