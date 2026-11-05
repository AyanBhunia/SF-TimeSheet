trigger EmployeeTrigger on Employee__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            EmployeeTriggerHandler.checkUserDuplicationForEmployeeBeforeInsert(Trigger.new);
            EmployeeTriggerHandler.populateEmployeeFields(Trigger.new);
            EmployeeTriggerHandler.populateEmployeeName(Trigger.new);
            EmployeeTriggerHandler.populateClientManager(Trigger.new);
        }
        if (Trigger.isUpdate) {
            EmployeeTriggerHandler.checkUserDuplicationForEmployeeBeforeUpdate(Trigger.new);
            EmployeeTriggerHandler.populateEmployeeFields(Trigger.new);
            EmployeeTriggerHandler.populateEmployeeName(Trigger.new);
            EmployeeTriggerHandler.populateClientManager(Trigger.new);
        }
    }
}