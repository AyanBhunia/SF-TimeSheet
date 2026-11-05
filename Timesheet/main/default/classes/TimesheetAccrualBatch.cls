global class TimesheetAccrualBatch implements Database.Batchable<sObject> {

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
        Set<Id> timesheetIds = new Set<Id>();
        Set<Id> empIdsForDivisor = new Set<Id>();

        for (Timesheet__c ts : scope) {
            empIdsForDivisor.add(ts.Employee__c);
            timesheetIds.add(ts.Id);
        }

        Map<Id, Decimal> empDivisorMap = new Map<Id, Decimal>();
        Map<Id, Date> empAccrualStartMap = new Map<Id, Date>();
        Date minAccrualDate;
        
        if (!empIdsForDivisor.isEmpty()) {
            for (Employee__c emp : [
                SELECT Id, Accrual_Divisor__c, Accrual_Start_Date__c
                FROM Employee__c
                WHERE Id IN :empIdsForDivisor
            ]) {
                empDivisorMap.put(emp.Id, emp.Accrual_Divisor__c);
                empAccrualStartMap.put(emp.Id, emp.Accrual_Start_Date__c);
                if (emp.Accrual_Start_Date__c != null) {
                    if (minAccrualDate == null || emp.Accrual_Start_Date__c < minAccrualDate) {
                        minAccrualDate = emp.Accrual_Start_Date__c;
                    }
                }
            }
        }

        Map<Id, Decimal> timesheetToBillableHours = new Map<Id, Decimal>();
        
        if (!timesheetIds.isEmpty() && minAccrualDate != null) {
            List<Timesheet_Line_Item__c> lineItems = [
                SELECT Timesheet__c, Duration__c, Date__c, Employee__c
                FROM Timesheet_Line_Item__c
                WHERE Timesheet__c IN :timesheetIds
                AND Billable__c = 'Yes'
                AND Type__c = 'Attendance'
                AND Date__c >= :minAccrualDate
                AND Employee__c != NULL
                AND Timesheet__r.Employee__r.Accrual_Start_Date__c != NULL
            ];

            for (Timesheet_Line_Item__c li : lineItems) {
                Date accrualStart = empAccrualStartMap.get(li.Employee__c);
                
                if (accrualStart != null && li.Date__c != null && li.Date__c >= accrualStart) {
                    Decimal duration = (li.Duration__c == null ? 0 : li.Duration__c);
                    
                    if (timesheetToBillableHours.containsKey(li.Timesheet__c)) {
                        timesheetToBillableHours.put(li.Timesheet__c, timesheetToBillableHours.get(li.Timesheet__c) + duration);
                    } else {
                        timesheetToBillableHours.put(li.Timesheet__c, duration);
                    }
                }
            }
        }

        List<Timesheet__c> timesheetsToUpdate = new List<Timesheet__c>();

        for (Timesheet__c ts : scope) {
            Decimal totalBillableHours = timesheetToBillableHours.get(ts.Id);
            Decimal divisor = empDivisorMap.get(ts.Employee__c);
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