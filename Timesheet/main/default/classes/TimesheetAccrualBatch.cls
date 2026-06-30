public with sharing class TimesheetAccrualBatch implements Database.Batchable<sObject> {

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT Id, Status__c, Employee__c, Accrued_Hours__c 
            FROM Timesheet__c 
            WHERE Status__c = 'Approved' 
            AND Employee__c != NULL
            AND Employee__r.Accrual_Start_Date__c != NULL
            AND Employee__r.Accrual_Divisor__c != NULL
        ]);
    }

    public void execute(Database.BatchableContext BC, List<Timesheet__c> scope) {
        List<Timesheet__c> timesheetsToUpdate = new List<Timesheet__c>();
        Map<Id, Decimal> oldAccruals = new Map<Id, Decimal>();
        for (Timesheet__c ts : scope) {
            oldAccruals.put(ts.Id, ts.Accrued_Hours__c);
        }

        AccrualCalculationService.calculateTimesheetAccruals(scope);

        for (Timesheet__c ts : scope) {
            if (ts.Accrued_Hours__c != oldAccruals.get(ts.Id)) {
                timesheetsToUpdate.add(ts);
            }
        }

        if (!timesheetsToUpdate.isEmpty()) {
            SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.UPDATABLE, timesheetsToUpdate);
            Database.update(securityDecision.getRecords(), false);
        }
    }

    public void finish(Database.BatchableContext BC) {
        EmployeeAccrualUpdater.updateEmployeeAccruals();
    }
}