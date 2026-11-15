global with sharing class EmployeeAccrualUpdater {
    global Static Void EmployeeAccrualUpdater() {
        Set<Id> empIds = new Set<Id>();
        for(dbt__Timesheet__c ts : [
            SELECT dbt__Employee__c 
            FROM dbt__Timesheet__c 
            WHERE dbt__Status__c = 'Approved' 
            AND dbt__Employee__c != NULL 
            AND dbt__Employee__r.dbt__Accrual_Start_Date__c != NULL 
            AND dbt__Employee__r.Accrual_Divisor__c != NULL
        ]) {
            empIds.add(ts.dbt__Employee__c);
        }

        if(!empIds.isEmpty()) {
            Map<Id, Date> empAccrualStartMap = new Map<Id, Date>();
            Map<Id, Decimal> empExtraAccruedMap = new Map<Id, Decimal>();
            Map<Id, Decimal> empExtraAbsenceMap = new Map<Id, Decimal>();
            Date minAccrualDate;
            
            for (dbt__Employee__c emp : [
                SELECT Id, dbt__Accrual_Start_Date__c, Extra_Accrued_Hours__c, Extra_Absence_Hours__c
                FROM dbt__Employee__c 
                WHERE Id IN :empIds
                AND dbt__Accrual_Start_Date__c != NULL
            ]) {
                empAccrualStartMap.put(emp.Id, emp.dbt__Accrual_Start_Date__c);
                empExtraAccruedMap.put(emp.Id, emp.Extra_Accrued_Hours__c != null ? emp.Extra_Accrued_Hours__c : 0);
                empExtraAbsenceMap.put(emp.Id, emp.Extra_Absence_Hours__c != null ? emp.Extra_Absence_Hours__c : 0);
                if (minAccrualDate == null || emp.dbt__Accrual_Start_Date__c < minAccrualDate) {
                    minAccrualDate = emp.dbt__Accrual_Start_Date__c;
                }
            }
            
            if (!empAccrualStartMap.isEmpty()) {
                Map<Id, Decimal> empTotalAccruedMap = new Map<Id, Decimal>();
                Map<Id, Decimal> empTotalAbsenceMap = new Map<Id, Decimal>();

                for(Id empId : empAccrualStartMap.keySet()){
                    empTotalAccruedMap.put(empId, empExtraAccruedMap.get(empId));
                    empTotalAbsenceMap.put(empId, empExtraAbsenceMap.get(empId));
                }

                for (dbt__Timesheet__c ts : [
                    SELECT dbt__Employee__c, Accrued_Hours__c, dbt__Absence_Hours__c, dbt__End_Date__c
                    FROM dbt__Timesheet__c 
                    WHERE dbt__Employee__c IN :empAccrualStartMap.keySet() 
                    AND dbt__Status__c = 'Approved'
                    AND dbt__End_Date__c >= :minAccrualDate
                ]) {
                    Date accrualStart = empAccrualStartMap.get(ts.dbt__Employee__c);
                    
                    if (accrualStart != null && ts.dbt__End_Date__c != null && ts.dbt__End_Date__c >= accrualStart) {
                        Decimal accrued = ts.Accrued_Hours__c != null ? ts.Accrued_Hours__c : 0;
                        Decimal absence = ts.dbt__Absence_Hours__c != null ? ts.dbt__Absence_Hours__c : 0;
                        
                        empTotalAccruedMap.put(ts.dbt__Employee__c, empTotalAccruedMap.get(ts.dbt__Employee__c) + accrued);
                        empTotalAbsenceMap.put(ts.dbt__Employee__c, empTotalAbsenceMap.get(ts.dbt__Employee__c) + absence);
                    }
                }

                List<dbt__Employee__c> employeesToUpdate = new List<dbt__Employee__c>();
                for (Id empId : empTotalAccruedMap.keySet()) {
                    employeesToUpdate.add(new dbt__Employee__c(
                        Id = empId,
                        Total_Accrued_Hours__c = empTotalAccruedMap.get(empId),
                        Total_Absence_Hours__c = empTotalAbsenceMap.get(empId)
                    ));
                }

                if (!employeesToUpdate.isEmpty()) {
                    update employeesToUpdate;
                }
            }
        }
        System.debug('Employee Accrual Updated');
    }
}