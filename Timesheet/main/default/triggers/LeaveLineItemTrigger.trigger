trigger LeaveLineItemTrigger on Leave_Line_Item__c (before insert, before update, before delete) {
    if (Trigger.isInsert) {
        PtoRequestService.beforeLineInsert(Trigger.new);
    } else if (Trigger.isUpdate) {
        PtoRequestService.beforeLineUpdate(Trigger.new, Trigger.oldMap);
    } else {
        PtoRequestService.beforeLineDelete(Trigger.old);
    }
}
