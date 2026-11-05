trigger TimesheetTrigger on Timesheet__c (before insert, before update, after insert, after update, after delete, after undelete) {

    if (Trigger.isBefore) {

        // A running timer's time is only added to its row when the timer is saved, and a submitted or
        // approved timesheet can no longer take it. So the week cannot be closed while a timer runs: it is checked
        // when the week is submitted (or approved without having been submitted). Approving a submitted week is
        // never blocked, because only the owner of a timer can save or discard it, and the approver cannot.
        if (Trigger.isUpdate) {
            Set<Id> closing = new Set<Id>();
            for (Timesheet__c ts : Trigger.new) {
                String status = ts.Status__c;
                String oldStatus = Trigger.oldMap.get(ts.Id).Status__c;
                if (status != oldStatus && (status == 'Submitted' || (status == 'Approved' && oldStatus != 'Submitted'))) {
                    closing.add(ts.Id);
                }
            }
            if (!closing.isEmpty()) {
                for (AggregateResult running : [
                    SELECT Timesheet__c timesheetId
                    FROM Timesheet_Line_Item__c
                    WHERE Timesheet__c IN :closing AND Timer_Data__c != NULL
                    GROUP BY Timesheet__c
                ]) {
                    Trigger.newMap.get((Id) running.get('timesheetId')).addError(
                        'A timer is still running on this timesheet. Save or discard it in the timer first, then submit or approve the timesheet.');
                }
            }
        }

        Set<Id> timesheetIds = new Set<Id>();
        Set<Id> empIdsForDivisor = new Set<Id>();
        for (Timesheet__c ts : Trigger.new) {
            if (ts.Status__c == 'Approved' && ts.Employee__c != null) {
                empIdsForDivisor.add(ts.Employee__c);
                timesheetIds.add(ts.Id);
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
                SELECT Timesheet__c, Duration__c, Date__c, Billable__c, Type__c, Employee__c
                FROM Timesheet_Line_Item__c
                WHERE Timesheet__c IN :timesheetIds
                AND Billable__c = 'Yes'
                AND Type__c = 'Attendance'
                AND Date__c >= :minAccrualDate
                AND Employee__c != NULL
                AND Timesheet__r.Employee__r.Accrual_Start_Date__c != NULL
            ]) {
                Date accrualStart = empAccrualStartMap.get(li.Employee__c);
                if (accrualStart != null && li.Date__c != null && li.Date__c >= accrualStart) {
                    Decimal running = timesheetToBillableHours.containsKey(li.Timesheet__c)
                        ? timesheetToBillableHours.get(li.Timesheet__c)
                        : 0;
                    running += (li.Duration__c == null ? 0 : li.Duration__c);
                    timesheetToBillableHours.put(li.Timesheet__c, running);
                }
            }
        }

        for (Timesheet__c ts : Trigger.new) {
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

    if (Trigger.isAfter) {
        if (Trigger.isInsert) {
            // Approved leave in the new week becomes absence line items.
            LeaveToLineItem.forTimesheets(Trigger.new);
        }

        Set<Id> empIdsToUpdate = new Set<Id>();

        if (Trigger.isInsert || Trigger.isUpdate || Trigger.isUndelete) {
            for (Timesheet__c ts : Trigger.new) {
                boolean isRelevantChange = false;
                
                if (Trigger.isInsert && ts.Status__c == 'Approved') {
                    isRelevantChange = true;
                }
                else if (Trigger.isUpdate) {
                    Timesheet__c oldTs = Trigger.oldMap.get(ts.Id);
                    
                    boolean statusChanged = (ts.Status__c != oldTs.Status__c) && 
                                            (ts.Status__c == 'Approved' || oldTs.Status__c == 'Approved');
                    
                    boolean absenceChanged = (ts.Absence_Hours__c != oldTs.Absence_Hours__c) &&
                                             (ts.Status__c == 'Approved');

                    if (statusChanged || absenceChanged) {
                        isRelevantChange = true;
                    }
                }
                
                if (isRelevantChange && ts.Employee__c != null) {
                    empIdsToUpdate.add(ts.Employee__c);
                }
            }
        }

        if (Trigger.isDelete) {
            for (Timesheet__c ts : Trigger.old) {
                if (ts.Status__c == 'Approved' && ts.Employee__c != null) {
                    empIdsToUpdate.add(ts.Employee__c);
                }
            }
        }

        if (!empIdsToUpdate.isEmpty()) {
            Map<Id, Date> empAccrualStartMap = new Map<Id, Date>();
            Map<Id, Decimal> empExtraAccruedMap = new Map<Id, Decimal>();
            Map<Id, Decimal> empExtraAbsenceMap = new Map<Id, Decimal>();
            Date minAccrualDate;
            for (Employee__c emp : [
                SELECT Id, Accrual_Start_Date__c, Extra_Accrued_Hours__c, Extra_Absence_Hours__c 
                FROM Employee__c 
                WHERE Id IN :empIdsToUpdate
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
                Map<Id, Decimal> empTotalMap = new Map<Id, Decimal>();
                Map<Id, Decimal> empAbsenceMap = new Map<Id, Decimal>();

                for(Id empId : empAccrualStartMap.keySet()){
                    empTotalMap.put(empId, empExtraAccruedMap.get(empId));
                    empAbsenceMap.put(empId, empExtraAbsenceMap.get(empId));
                }

                for (Timesheet__c ts : [
                    SELECT Employee__c, Accrued_Hours__c, Absence_Hours__c, End_Date__c
                    FROM Timesheet__c 
                    WHERE Employee__c IN :empIdsToUpdate
                    AND Status__c = 'Approved'
                    AND End_Date__c >= :minAccrualDate
                    AND Employee__r.Accrual_Start_Date__c != NULL
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
                    try {
                        EmployeeTriggerHandler.bypassEmployeePermissionCheck = true;
                        Database.update(employeesToUpdate, AccessLevel.SYSTEM_MODE);
                    } finally {
                        EmployeeTriggerHandler.bypassEmployeePermissionCheck = false;
                    }
                }
            }
        }
    }
}
