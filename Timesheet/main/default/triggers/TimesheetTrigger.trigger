trigger TimesheetTrigger on dbt__Timesheet__c (before insert, before update, after insert, after update, after delete, after undelete) {

    if (Trigger.isBefore) {

        // A running timer's time is only added to its row when the timer is saved, and a submitted or
        // approved timesheet can no longer take it. So the week cannot be closed while a timer runs.
        if (Trigger.isUpdate) {
            Set<Id> closing = new Set<Id>();
            for (dbt__Timesheet__c ts : Trigger.new) {
                String status = ts.dbt__Status__c;
                if (status != Trigger.oldMap.get(ts.Id).dbt__Status__c && (status == 'Submitted' || status == 'Approved')) {
                    closing.add(ts.Id);
                }
            }
            if (!closing.isEmpty()) {
                for (AggregateResult running : [
                    SELECT dbt__Timesheet__c timesheetId
                    FROM dbt__Timesheet_Line_Item__c
                    WHERE dbt__Timesheet__c IN :closing AND dbt__Timer_Data__c != NULL
                    GROUP BY dbt__Timesheet__c
                ]) {
                    Trigger.newMap.get((Id) running.get('timesheetId')).addError(
                        'A timer is still running on this timesheet. Save or discard it in the timer first, then submit or approve the timesheet.');
                }
            }
        }

        Set<Id> timesheetIds = new Set<Id>();
        Set<Id> empIdsForDivisor = new Set<Id>();
        for (dbt__Timesheet__c ts : Trigger.new) {
            if (ts.dbt__Status__c == 'Approved' && ts.dbt__Employee__c != null) {
                empIdsForDivisor.add(ts.dbt__Employee__c);
                timesheetIds.add(ts.Id);
            } else {
                ts.Accrued_Hours__c = 0;
            }
        }

        Map<Id, Decimal> empDivisorMap = new Map<Id, Decimal>();
        Map<Id, Date> empAccrualStartMap = new Map<Id, Date>();
        Date minAccrualDate;
        if (!empIdsForDivisor.isEmpty()) {
            for (dbt__Employee__c emp : [
                SELECT Id, Accrual_Divisor__c, dbt__Accrual_Start_Date__c
                FROM dbt__Employee__c
                WHERE Id IN :empIdsForDivisor
                AND dbt__Accrual_Start_Date__c != NULL
            ]) {
                empDivisorMap.put(emp.Id, emp.Accrual_Divisor__c);
                empAccrualStartMap.put(emp.Id, emp.dbt__Accrual_Start_Date__c);
                if (minAccrualDate == null || emp.dbt__Accrual_Start_Date__c < minAccrualDate) {
                    minAccrualDate = emp.dbt__Accrual_Start_Date__c;
                }
            }
        }

        Map<Id, Decimal> timesheetToBillableHours = new Map<Id, Decimal>();
        if (!timesheetIds.isEmpty() && !empAccrualStartMap.isEmpty()) {
            for (dbt__Timesheet_Line_Item__c li : [
                SELECT dbt__Timesheet__c, dbt__Duration__c, dbt__Date__c, dbt__Billable__c, dbt__Type__c, dbt__Employee__c
                FROM dbt__Timesheet_Line_Item__c
                WHERE dbt__Timesheet__c IN :timesheetIds
                AND dbt__Billable__c = 'Yes'
                AND dbt__Type__c = 'Attendance'
                AND dbt__Date__c >= :minAccrualDate
                AND dbt__Employee__c != NULL
                AND dbt__Timesheet__r.dbt__Employee__r.dbt__Accrual_Start_Date__c != NULL
            ]) {
                Date accrualStart = empAccrualStartMap.get(li.dbt__Employee__c);
                if (accrualStart != null && li.dbt__Date__c != null && li.dbt__Date__c >= accrualStart) {
                    Decimal running = timesheetToBillableHours.containsKey(li.dbt__Timesheet__c)
                        ? timesheetToBillableHours.get(li.dbt__Timesheet__c)
                        : 0;
                    running += (li.dbt__Duration__c == null ? 0 : li.dbt__Duration__c);
                    //Decimal running = (timesheetToBillableHours.get(li.dbt__Timesheet__c) ?? 0) + (li.dbt__Duration__c ?? 0);
                    timesheetToBillableHours.put(li.dbt__Timesheet__c, running);
                }
            }
        }

        for (dbt__Timesheet__c ts : Trigger.new) {
            if (ts.dbt__Status__c == 'Approved' && ts.dbt__Employee__c != null) {
                Decimal totalBillableHours = timesheetToBillableHours.get(ts.Id);
                Decimal divisor = empDivisorMap.get(ts.dbt__Employee__c);

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
            for (dbt__Timesheet__c ts : Trigger.new) {
                boolean isRelevantChange = false;
                
                if (Trigger.isInsert && ts.dbt__Status__c == 'Approved') {
                    isRelevantChange = true;
                }
                else if (Trigger.isUpdate) {
                    dbt__Timesheet__c oldTs = Trigger.oldMap.get(ts.Id);
                    
                    boolean statusChanged = (ts.dbt__Status__c != oldTs.dbt__Status__c) && 
                                            (ts.dbt__Status__c == 'Approved' || oldTs.dbt__Status__c == 'Approved');
                    
                    boolean absenceChanged = (ts.dbt__Absence_Hours__c != oldTs.dbt__Absence_Hours__c) &&
                                             (ts.dbt__Status__c == 'Approved');

                    if (statusChanged || absenceChanged) {
                        isRelevantChange = true;
                    }
                }
                
                if (isRelevantChange && ts.dbt__Employee__c != null) {
                    empIdsToUpdate.add(ts.dbt__Employee__c);
                }
            }
        }

        if (Trigger.isDelete) {
            for (dbt__Timesheet__c ts : Trigger.old) {
                if (ts.dbt__Status__c == 'Approved' && ts.dbt__Employee__c != null) {
                    empIdsToUpdate.add(ts.dbt__Employee__c);
                }
            }
        }

        if (!empIdsToUpdate.isEmpty()) {
            Map<Id, Date> empAccrualStartMap = new Map<Id, Date>();
            Map<Id, Decimal> empExtraAccruedMap = new Map<Id, Decimal>();
            Map<Id, Decimal> empExtraAbsenceMap = new Map<Id, Decimal>();
            Date minAccrualDate;
            for (dbt__Employee__c emp : [
                SELECT Id, dbt__Accrual_Start_Date__c, Extra_Accrued_Hours__c, Extra_Absence_Hours__c 
                FROM dbt__Employee__c 
                WHERE Id IN :empIdsToUpdate
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
                Map<Id, Decimal> empTotalMap = new Map<Id, Decimal>();
                Map<Id, Decimal> empAbsenceMap = new Map<Id, Decimal>();

                for(Id empId : empAccrualStartMap.keySet()){
                    empTotalMap.put(empId, empExtraAccruedMap.get(empId));
                    empAbsenceMap.put(empId, empExtraAbsenceMap.get(empId));
                }

                for (dbt__Timesheet__c ts : [
                    SELECT dbt__Employee__c, Accrued_Hours__c, dbt__Absence_Hours__c, dbt__End_Date__c
                    FROM dbt__Timesheet__c 
                    WHERE dbt__Employee__c IN :empIdsToUpdate
                    AND dbt__Status__c = 'Approved'
                    AND dbt__End_Date__c >= :minAccrualDate
                    AND dbt__Employee__r.dbt__Accrual_Start_Date__c != NULL
                ]) {
                    Date accrualStart = empAccrualStartMap.get(ts.dbt__Employee__c);
                    
                    if (accrualStart != null && ts.dbt__End_Date__c != null && ts.dbt__End_Date__c >= accrualStart) {
                        Decimal accrued = ts.Accrued_Hours__c != null ? ts.Accrued_Hours__c : 0;
                        Decimal absence = ts.dbt__Absence_Hours__c != null ? ts.dbt__Absence_Hours__c : 0;
                        
                        empTotalMap.put(ts.dbt__Employee__c, empTotalMap.get(ts.dbt__Employee__c) + accrued);
                        empAbsenceMap.put(ts.dbt__Employee__c, empAbsenceMap.get(ts.dbt__Employee__c) + absence);
                    }
                }

                List<dbt__Employee__c> employeesToUpdate = new List<dbt__Employee__c>();
                for (Id empId : empTotalMap.keySet()) {
                    employeesToUpdate.add(new dbt__Employee__c(
                        Id = empId,
                        Total_Accrued_Hours__c = empTotalMap.get(empId),
                        Total_Absence_Hours__c = empAbsenceMap.get(empId)
                    ));
                }

                if (!employeesToUpdate.isEmpty()) {
                    update employeesToUpdate;
                }
            }
        }
    }
}