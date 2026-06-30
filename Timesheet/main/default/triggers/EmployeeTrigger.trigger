trigger EmployeeTrigger on Employee__c (before insert, before update) {
    new EmployeeTriggerHandler().run();
}