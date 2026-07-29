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
        cascadeStatusToLineItems(newTimesheets, oldMap);
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

    private static Boolean isAccrualEligible(Timesheet__c ts) {
        if (ts == null) return false;
        return ts.Status__c == 'Approved' || ts.Status__c == 'Partial';
    }

    private static void updateEmployeeTotals(List<Timesheet__c> timesheets, Map<Id, Timesheet__c> oldMap) {
        Set<Id> empIdsToUpdate = new Set<Id>();

        for (Timesheet__c ts : timesheets) {
            boolean isRelevantChange = false;
            
            if (Trigger.isInsert || Trigger.isUndelete) {
                if (isAccrualEligible(ts)) {
                    isRelevantChange = true;
                }
            } else if (Trigger.isUpdate) {
                Timesheet__c oldTs = oldMap.get(ts.Id);
                
                boolean statusChanged = (ts.Status__c != oldTs.Status__c) && 
                                        (isAccrualEligible(ts) || isAccrualEligible(oldTs));
                
                boolean absenceChanged = (ts.Absence_Hours__c != oldTs.Absence_Hours__c) &&
                                         (isAccrualEligible(ts));

                if (statusChanged || absenceChanged) {
                    isRelevantChange = true;
                }
            } else if (Trigger.isDelete) {
                if (isAccrualEligible(ts)) {
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

    /**
     * Cascade Sys Admin status overrides to child line items.
     * Only fires when Status__c actually changed and the new transition
     * matches one of the 6 defined admin overrides in StatusLogic.md.
     */
    private static void cascadeStatusToLineItems(List<Timesheet__c> newTimesheets, Map<Id, Timesheet__c> oldMap) {
        Map<Id, String[]> tsToCascade = new Map<Id, String[]>(); // tsId -> [oldStatus, newStatus]

        for (Timesheet__c ts : newTimesheets) {
            Timesheet__c oldTs = oldMap.get(ts.Id);
            if (ts.Status__c == oldTs.Status__c) continue; // No status change

            String oldS = oldTs.Status__c;
            String newS = ts.Status__c;

            // Only cascade known admin override transitions
            Boolean isAdminOverride =
                (oldS == 'Partial' && newS == 'New') ||
                (oldS == 'Submitted' && newS == 'New') ||
                (oldS == 'Approved' && newS == 'New') ||
                (oldS == 'Approved' && newS == 'Submitted') ||
                (oldS == 'Submitted' && newS == 'Partial') ||
                (oldS == 'Approved' && newS == 'Partial');

            if (isAdminOverride) {
                tsToCascade.put(ts.Id, new String[]{ oldS, newS });
            }
        }

        if (tsToCascade.isEmpty()) return;

        List<Timesheet_Line_Item__c> allChildren = [
            SELECT Id, Line_Item_Status__c, Timesheet__c
            FROM Timesheet_Line_Item__c
            WHERE Timesheet__c IN :tsToCascade.keySet()
        ];

        List<Timesheet_Line_Item__c> toUpdate = new List<Timesheet_Line_Item__c>();

        for (Timesheet_Line_Item__c li : allChildren) {
            String[] transition = tsToCascade.get(li.Timesheet__c);
            String oldStatus = transition[0];
            String newStatus = transition[1];
            String newLiStatus = null;

            if (newStatus == 'New') {
                if (oldStatus == 'Submitted' && li.Line_Item_Status__c == 'Partial Approved') {
                    // Submitted → New: PRESERVE Partial Approved
                    continue;
                }
                // Partial→New, Approved→New: ALL become New
                newLiStatus = 'New';
            }
            else if (oldStatus == 'Approved' && newStatus == 'Submitted') {
                // Approved → Submitted: ALL become Submitted
                newLiStatus = 'Submitted';
            }
            else if (newStatus == 'Partial') {
                if (oldStatus == 'Submitted' && li.Line_Item_Status__c == 'Partial Approved') {
                    // Submitted → Partial: PRESERVE Partial Approved
                    continue;
                }
                // Submitted→Partial (non-PA), Approved→Partial: become Partial Submitted
                newLiStatus = 'Partial Submitted';
            }

            if (newLiStatus != null && li.Line_Item_Status__c != newLiStatus) {
                li.Line_Item_Status__c = newLiStatus;
                toUpdate.add(li);
            }
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}
