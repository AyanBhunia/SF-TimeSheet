trigger PtoRequestTrigger on PTO_Request__c (before insert, before update, after insert, after update) {
    if (Trigger.isBefore) {
        PtoRequestService.beforeRequestSave(Trigger.new, Trigger.oldMap);
    } else if (Trigger.isInsert) {
        PtoRequestService.afterRequestInsert(Trigger.new);
    } else {
        PtoRequestService.afterRequestUpdate(Trigger.new, Trigger.oldMap);
    }
}
