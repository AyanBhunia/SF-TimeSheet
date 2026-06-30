public with sharing class TimesheetTriggerHandler extends TriggerHandler {

    protected override void beforeInsert() {
        beforeInsert((List<Timesheet__c>)Trigger.new);
    }
    protected override void beforeUpdate() {
        beforeUpdate((List<Timesheet__c>)Trigger.new, (Map<Id, Timesheet__c>)Trigger.oldMap);
    }
    protected override void afterInsert() {
        afterInsert((List<Timesheet__c>)Trigger.new);
    }
    protected override void afterUpdate() {
        afterUpdate((List<Timesheet__c>)Trigger.new, (Map<Id, Timesheet__c>)Trigger.oldMap);
    }
    protected override void afterDelete() {
        afterDelete((List<Timesheet__c>)Trigger.old);
    }
    protected override void afterUndelete() {
        afterUndelete((List<Timesheet__c>)Trigger.new);
    }

    public static void beforeInsert(List<Timesheet__c> newTimesheets) {
        calculateAccruedHours(newTimesheets, null);
    }

    public static void beforeUpdate(List<Timesheet__c> newTimesheets, Map<Id, Timesheet__c> oldMap) {
        calculateAccruedHours(newTimesheets, oldMap);
    }

    public static void afterInsert(List<Timesheet__c> newTimesheets) {
        updateEmployeeTotals(newTimesheets, null);
    }

    public static void afterUpdate(List<Timesheet__c> newTimesheets, Map<Id, Timesheet__c> oldMap) {
        updateEmployeeTotals(newTimesheets, oldMap);
    }

    public static void afterDelete(List<Timesheet__c> oldTimesheets) {
        updateEmployeeTotals(oldTimesheets, null);
    }

    public static void afterUndelete(List<Timesheet__c> newTimesheets) {
        updateEmployeeTotals(newTimesheets, null);
    }

    private static void calculateAccruedHours(List<Timesheet__c> newTimesheets, Map<Id, Timesheet__c> oldMap) {
        AccrualCalculationService.calculateTimesheetAccruals(newTimesheets);
    }

    private static void updateEmployeeTotals(List<Timesheet__c> timesheets, Map<Id, Timesheet__c> oldMap) {
        Set<Id> empIdsToUpdate = new Set<Id>();

        for (Timesheet__c ts : timesheets) {
            boolean isRelevantChange = false;
            
            if (Trigger.isInsert || Trigger.isUndelete) {
                if (ts.Status__c == 'Approved') {
                    isRelevantChange = true;
                }
            } else if (Trigger.isUpdate) {
                Timesheet__c oldTs = oldMap.get(ts.Id);
                
                boolean statusChanged = (ts.Status__c != oldTs.Status__c) && 
                                        (ts.Status__c == 'Approved' || oldTs.Status__c == 'Approved');
                
                boolean absenceChanged = (ts.Absence_Hours__c != oldTs.Absence_Hours__c) &&
                                         (ts.Status__c == 'Approved');

                if (statusChanged || absenceChanged) {
                    isRelevantChange = true;
                }
            } else if (Trigger.isDelete) {
                if (ts.Status__c == 'Approved') {
                    isRelevantChange = true;
                }
            }
            
            if (isRelevantChange && ts.Employee__c != null) {
                empIdsToUpdate.add(ts.Employee__c);
            }
        }

        if (!empIdsToUpdate.isEmpty()) {
            AccrualCalculationService.recalculateEmployeeTotals(empIdsToUpdate);
        }
    }
}
