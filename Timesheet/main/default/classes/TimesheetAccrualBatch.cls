global class TimesheetAccrualBatch implements Database.Batchable<sObject> {

    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator([
            SELECT Id, dbt__Status__c, dbt__Employee__c, Accrued_Hours__c 
            FROM dbt__Timesheet__c 
            WHERE dbt__Status__c = 'Approved' 
            AND dbt__Employee__c != NULL
            AND dbt__Employee__r.dbt__Accrual_Start_Date__c != NULL
            AND dbt__Employee__r.Accrual_Divisor__c != NULL
        ]);
    }

    public void execute(Database.BatchableContext BC, List<dbt__Timesheet__c> scope) {
        Set<Id> timesheetIds = new Set<Id>();
        Set<Id> empIdsForDivisor = new Set<Id>();

        for (dbt__Timesheet__c ts : scope) {
            empIdsForDivisor.add(ts.dbt__Employee__c);
            timesheetIds.add(ts.Id);
        }

        Map<Id, Decimal> empDivisorMap = new Map<Id, Decimal>();
        Map<Id, Date> empAccrualStartMap = new Map<Id, Date>();
        Date minAccrualDate;
        
        if (!empIdsForDivisor.isEmpty()) {
            for (dbt__Employee__c emp : [
                SELECT Id, Accrual_Divisor__c, dbt__Accrual_Start_Date__c
                FROM dbt__Employee__c
                WHERE Id IN :empIdsForDivisor
            ]) {
                empDivisorMap.put(emp.Id, emp.Accrual_Divisor__c);
                empAccrualStartMap.put(emp.Id, emp.dbt__Accrual_Start_Date__c);
                if (emp.dbt__Accrual_Start_Date__c != null) {
                    if (minAccrualDate == null || emp.dbt__Accrual_Start_Date__c < minAccrualDate) {
                        minAccrualDate = emp.dbt__Accrual_Start_Date__c;
                    }
                }
            }
        }

        Map<Id, Decimal> timesheetToBillableHours = new Map<Id, Decimal>();
        
        if (!timesheetIds.isEmpty() && minAccrualDate != null) {
            List<dbt__Timesheet_Line_Item__c> lineItems = [
                SELECT dbt__Timesheet__c, dbt__Duration__c, dbt__Date__c, dbt__Employee__c
                FROM dbt__Timesheet_Line_Item__c
                WHERE dbt__Timesheet__c IN :timesheetIds
                AND dbt__Billable__c = 'Yes'
                AND dbt__Type__c = 'Attendance'
                AND dbt__Date__c >= :minAccrualDate
                AND dbt__Employee__c != NULL
                AND dbt__Timesheet__r.dbt__Employee__r.dbt__Accrual_Start_Date__c != NULL
            ];

            for (dbt__Timesheet_Line_Item__c li : lineItems) {
                Date accrualStart = empAccrualStartMap.get(li.dbt__Employee__c);
                
                if (accrualStart != null && li.dbt__Date__c != null && li.dbt__Date__c >= accrualStart) {
                    Decimal duration = (li.dbt__Duration__c == null ? 0 : li.dbt__Duration__c);
                    
                    if (timesheetToBillableHours.containsKey(li.dbt__Timesheet__c)) {
                        timesheetToBillableHours.put(li.dbt__Timesheet__c, timesheetToBillableHours.get(li.dbt__Timesheet__c) + duration);
                    } else {
                        timesheetToBillableHours.put(li.dbt__Timesheet__c, duration);
                    }
                }
            }
        }

        List<dbt__Timesheet__c> timesheetsToUpdate = new List<dbt__Timesheet__c>();

        for (dbt__Timesheet__c ts : scope) {
            Decimal totalBillableHours = timesheetToBillableHours.get(ts.Id);
            Decimal divisor = empDivisorMap.get(ts.dbt__Employee__c);
            Decimal oldVal = ts.Accrued_Hours__c;
            Decimal newVal = 0;

            if (totalBillableHours != null && totalBillableHours > 0 && divisor != null && divisor != 0) {
                newVal = totalBillableHours / divisor;
            }

            if (oldVal != newVal) {
                ts.Accrued_Hours__c = newVal;
                timesheetsToUpdate.add(ts);
            }
        }

        if (!timesheetsToUpdate.isEmpty()) {
            update timesheetsToUpdate;
        }
    }

    public void finish(Database.BatchableContext BC) {
        System.debug('Timesheet Accrual Recalculation Batch Finished');
        EmployeeAccrualUpdater.EmployeeAccrualUpdater();
    }
}


// dbt.TimesheetAccrualBatch batch = new dbt.TimesheetAccrualBatch();
// Database.executeBatch(batch, 200);