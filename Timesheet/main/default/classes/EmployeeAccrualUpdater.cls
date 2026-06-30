public with sharing class EmployeeAccrualUpdater {
    public static void updateEmployeeAccruals() {
        Set<Id> empIds = new Set<Id>();
        for(Timesheet__c ts : [
            SELECT Employee__c 
            FROM Timesheet__c 
            WHERE Status__c = 'Approved' 
            AND Employee__c != NULL 
            AND Employee__r.Accrual_Start_Date__c != NULL 
            AND Employee__r.Accrual_Divisor__c != NULL
            WITH SECURITY_ENFORCED
        ]) {
            empIds.add(ts.Employee__c);
        }

        if(!empIds.isEmpty()) {
            AccrualCalculationService.recalculateEmployeeTotals(empIds);
        }
    }
}