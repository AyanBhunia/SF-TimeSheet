trigger LeaveAndHolidayTrigger on Leave_and_Holiday__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        LeaveService.beforeSave(Trigger.new, Trigger.oldMap);
    } else {
        LeaveService.afterSave(Trigger.new, Trigger.oldMap);
    }
}
