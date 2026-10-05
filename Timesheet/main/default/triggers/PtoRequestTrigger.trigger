trigger PtoRequestTrigger on PTO_Request__c (before insert, before update, after update) {
    if (Trigger.isBefore) {
        PtoRequestService.beforeRequestSave(Trigger.new, Trigger.oldMap);
    } else {
        PtoRequestService.afterRequestUpdate(Trigger.new, Trigger.oldMap);
    }
}
