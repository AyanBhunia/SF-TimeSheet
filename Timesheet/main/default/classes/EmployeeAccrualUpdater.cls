global with sharing class EmployeeAccrualUpdater {
    global Static Void EmployeeAccrualUpdater() {
        Set<Id> empIds = new Set<Id>();
        for(Timesheet__c ts : [
            SELECT Employee__c 
            FROM Timesheet__c 
            WHERE Status__c = 'Approved' 
            AND Employee__c != NULL 
            AND Employee__r.Accrual_Start_Date__c != NULL 
            AND Employee__r.Accrual_Divisor__c != NULL
        ]) {
            empIds.add(ts.Employee__c);
        }

        if(!empIds.isEmpty()) {
            Map<Id, Date> empAccrualStartMap = new Map<Id, Date>();
            Map<Id, Decimal> empExtraAccruedMap = new Map<Id, Decimal>();
            Map<Id, Decimal> empExtraAbsenceMap = new Map<Id, Decimal>();
            Date minAccrualDate;
            
            for (Employee__c emp : [
                SELECT Id, Accrual_Start_Date__c, Extra_Accrued_Hours__c, Extra_Absence_Hours__c
                FROM Employee__c 
                WHERE Id IN :empIds
                AND Accrual_Start_Date__c != NULL
            ]) {
                empAccrualStartMap.put(emp.Id, emp.Accrual_Start_Date__c);
                empExtraAccruedMap.put(emp.Id, emp.Extra_Accrued_Hours__c != null ? emp.Extra_Accrued_Hours__c : 0);
                empExtraAbsenceMap.put(emp.Id, emp.Extra_Absence_Hours__c != null ? emp.Extra_Absence_Hours__c : 0);
                if (minAccrualDate == null || emp.Accrual_Start_Date__c < minAccrualDate) {
                    minAccrualDate = emp.Accrual_Start_Date__c;
                }
            }
            
            if (!empAccrualStartMap.isEmpty()) {
                Map<Id, Decimal> empTotalAccruedMap = new Map<Id, Decimal>();
                Map<Id, Decimal> empTotalAbsenceMap = new Map<Id, Decimal>();

                for(Id empId : empAccrualStartMap.keySet()){
                    empTotalAccruedMap.put(empId, empExtraAccruedMap.get(empId));
                    empTotalAbsenceMap.put(empId, empExtraAbsenceMap.get(empId));
                }

                for (Timesheet__c ts : [
                    SELECT Employee__c, Accrued_Hours__c, Absence_Hours__c, End_Date__c
                    FROM Timesheet__c 
                    WHERE Employee__c IN :empAccrualStartMap.keySet() 
                    AND Status__c = 'Approved'
                    AND End_Date__c >= :minAccrualDate
                ]) {
                    Date accrualStart = empAccrualStartMap.get(ts.Employee__c);
                    
                    if (accrualStart != null && ts.End_Date__c != null && ts.End_Date__c >= accrualStart) {
                        Decimal accrued = ts.Accrued_Hours__c != null ? ts.Accrued_Hours__c : 0;
                        Decimal absence = ts.Absence_Hours__c != null ? ts.Absence_Hours__c : 0;
                        
                        empTotalAccruedMap.put(ts.Employee__c, empTotalAccruedMap.get(ts.Employee__c) + accrued);
                        empTotalAbsenceMap.put(ts.Employee__c, empTotalAbsenceMap.get(ts.Employee__c) + absence);
                    }
                }

                List<Employee__c> employeesToUpdate = new List<Employee__c>();
                for (Id empId : empTotalAccruedMap.keySet()) {
                    employeesToUpdate.add(new Employee__c(
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