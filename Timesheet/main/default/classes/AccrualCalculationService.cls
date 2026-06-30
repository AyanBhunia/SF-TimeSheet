public with sharing class AccrualCalculationService {

    public static void calculateTimesheetAccruals(List<Timesheet__c> timesheets) {
        Set<Id> timesheetIds = new Set<Id>();
        Set<Id> empIdsForDivisor = new Set<Id>();
        for (Timesheet__c ts : timesheets) {
            if (ts.Status__c == 'Approved' && ts.Employee__c != null) {
                empIdsForDivisor.add(ts.Employee__c);
                if (ts.Id != null) {
                    timesheetIds.add(ts.Id);
                }
            } else {
                ts.Accrued_Hours__c = 0;
            }
        }

        Map<Id, Decimal> empDivisorMap = new Map<Id, Decimal>();
        Map<Id, Date> empAccrualStartMap = new Map<Id, Date>();
        Date minAccrualDate;
        
        if (!empIdsForDivisor.isEmpty()) {
            for (Employee__c emp : [
                SELECT Id, Accrual_Divisor__c, Accrual_Start_Date__c
                FROM Employee__c
                WHERE Id IN :empIdsForDivisor
                AND Accrual_Start_Date__c != NULL
                WITH SECURITY_ENFORCED
            ]) {
                empDivisorMap.put(emp.Id, emp.Accrual_Divisor__c);
                empAccrualStartMap.put(emp.Id, emp.Accrual_Start_Date__c);
                if (minAccrualDate == null || emp.Accrual_Start_Date__c < minAccrualDate) {
                    minAccrualDate = emp.Accrual_Start_Date__c;
                }
            }
        }

        Map<Id, Decimal> timesheetToBillableHours = new Map<Id, Decimal>();
        if (!timesheetIds.isEmpty() && !empAccrualStartMap.isEmpty()) {
            for (Timesheet_Line_Item__c li : [
                SELECT Timesheet__c, Duration__c, Date__c, Timesheet__r.Employee__c
                FROM Timesheet_Line_Item__c
                WHERE Timesheet__c IN :timesheetIds
                AND Billable__c = 'Yes'
                AND Type__c = 'Attendance'
                AND Date__c >= :minAccrualDate
                AND Timesheet__r.Employee__c != NULL
                AND Timesheet__r.Employee__r.Accrual_Start_Date__c != NULL
                WITH SECURITY_ENFORCED
            ]) {
                Date accrualStart = empAccrualStartMap.get(li.Timesheet__r.Employee__c);
                if (accrualStart != null && li.Date__c != null && li.Date__c >= accrualStart) {
                    Decimal running = timesheetToBillableHours.containsKey(li.Timesheet__c)
                        ? timesheetToBillableHours.get(li.Timesheet__c)
                        : 0;
                    running += (li.Duration__c == null ? 0 : li.Duration__c);
                    timesheetToBillableHours.put(li.Timesheet__c, running);
                }
            }
        }

        for (Timesheet__c ts : timesheets) {
            if (ts.Status__c == 'Approved' && ts.Employee__c != null) {
                Decimal totalBillableHours = timesheetToBillableHours.get(ts.Id);
                Decimal divisor = empDivisorMap.get(ts.Employee__c);

                if (totalBillableHours != null && totalBillableHours > 0 && divisor != null && divisor != 0) {
                    ts.Accrued_Hours__c = totalBillableHours / divisor;
                } else {
                    ts.Accrued_Hours__c = 0;
                }
            }
        }
    }

    public static void recalculateEmployeeTotals(Set<Id> empIds) {
        if (empIds == null || empIds.isEmpty()) return;

        Map<Id, Date> empAccrualStartMap = new Map<Id, Date>();
        Map<Id, Decimal> empExtraAccruedMap = new Map<Id, Decimal>();
        Map<Id, Decimal> empExtraAbsenceMap = new Map<Id, Decimal>();
        Date minAccrualDate;
        
        for (Employee__c emp : [
            SELECT Id, Accrual_Start_Date__c, Extra_Accrued_Hours__c, Extra_Absence_Hours__c 
            FROM Employee__c 
            WHERE Id IN :empIds
            AND Accrual_Start_Date__c != NULL
            WITH SECURITY_ENFORCED
        ]) {
            empAccrualStartMap.put(emp.Id, emp.Accrual_Start_Date__c);
            empExtraAccruedMap.put(emp.Id, emp.Extra_Accrued_Hours__c != null ? emp.Extra_Accrued_Hours__c : 0);
            empExtraAbsenceMap.put(emp.Id, emp.Extra_Absence_Hours__c != null ? emp.Extra_Absence_Hours__c : 0);
            if (minAccrualDate == null || emp.Accrual_Start_Date__c < minAccrualDate) {
                minAccrualDate = emp.Accrual_Start_Date__c;
            }
        }

        if (!empAccrualStartMap.isEmpty()) {
            Map<Id, Decimal> empTotalMap = new Map<Id, Decimal>();
            Map<Id, Decimal> empAbsenceMap = new Map<Id, Decimal>();

            for(Id empId : empAccrualStartMap.keySet()){
                empTotalMap.put(empId, empExtraAccruedMap.get(empId));
                empAbsenceMap.put(empId, empExtraAbsenceMap.get(empId));
            }

            for (Timesheet__c ts : [
                SELECT Employee__c, Accrued_Hours__c, Absence_Hours__c, End_Date__c
                FROM Timesheet__c 
                WHERE Employee__c IN :empIds
                AND Status__c = 'Approved'
                AND End_Date__c >= :minAccrualDate
                AND Employee__r.Accrual_Start_Date__c != NULL
                WITH SECURITY_ENFORCED
            ]) {
                Date accrualStart = empAccrualStartMap.get(ts.Employee__c);
                
                if (accrualStart != null && ts.End_Date__c != null && ts.End_Date__c >= accrualStart) {
                    Decimal accrued = ts.Accrued_Hours__c != null ? ts.Accrued_Hours__c : 0;
                    Decimal absence = ts.Absence_Hours__c != null ? ts.Absence_Hours__c : 0;
                    
                    empTotalMap.put(ts.Employee__c, empTotalMap.get(ts.Employee__c) + accrued);
                    empAbsenceMap.put(ts.Employee__c, empAbsenceMap.get(ts.Employee__c) + absence);
                }
            }

            List<Employee__c> employeesToUpdate = new List<Employee__c>();
            for (Id empId : empTotalMap.keySet()) {
                employeesToUpdate.add(new Employee__c(
                    Id = empId,
                    Total_Accrued_Hours__c = empTotalMap.get(empId),
                    Total_Absence_Hours__c = empAbsenceMap.get(empId)
                ));
            }

            if (!employeesToUpdate.isEmpty()) {
                SObjectAccessDecision securityDecision = Security.stripInaccessible(AccessType.UPDATABLE, employeesToUpdate);
                Database.update(securityDecision.getRecords(), false);
            }
        }
    }
}
