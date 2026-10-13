public with sharing class TimesheetTriggerHandler extends TriggerHandler {

     private static Set<Id> processedTimesheetIds = new Set<Id>();


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
        syncStatusFromLineItems(newTimesheets, oldMap);
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
        return ts.Status__c == 'Approved';
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

    private static void cascadeStatusToLineItems(
    List<Timesheet__c> newTimesheets,
    Map<Id, Timesheet__c> oldMap
) {
    Map<Id, String> timesheetStatusMap = new Map<Id, String>();

    // Collect Timesheets whose status changed
    for (Timesheet__c ts : newTimesheets) {
        Timesheet__c oldTs = oldMap.get(ts.Id);

        if (
            ts.Status__c != oldTs.Status__c &&
            !processedTimesheetIds.contains(ts.Id)
        ) {
            timesheetStatusMap.put(ts.Id, ts.Status__c);
            processedTimesheetIds.add(ts.Id);
        }
    }

    if (timesheetStatusMap.isEmpty()) {
        return;
    }

    // Query all related line items in one SOQL
    List<Timesheet_Line_Item__c> lineItems = [
        SELECT Id, Timesheet__c, Line_Item_Status__c
        FROM Timesheet_Line_Item__c
        WHERE Timesheet__c IN :timesheetStatusMap.keySet()
    ];

    List<Timesheet_Line_Item__c> lineItemsToUpdate =
        new List<Timesheet_Line_Item__c>();

    for (Timesheet_Line_Item__c li : lineItems) {
        String timesheetStatus = timesheetStatusMap.get(li.Timesheet__c);

        // Timesheet New → all Line Items New
        if (timesheetStatus == 'New') {
            if (li.Line_Item_Status__c != 'New') {
                li.Line_Item_Status__c = 'New';
                lineItemsToUpdate.add(li);
            }
        }

                // Timesheet Submitted -> all except Approved become Submitted
        else if (timesheetStatus == 'Submitted') {
            if (li.Line_Item_Status__c != 'Approved' &&
                li.Line_Item_Status__c != 'Submitted') {
                li.Line_Item_Status__c = 'Submitted';
                lineItemsToUpdate.add(li);
            }
        }

        // Timesheet Approved -> all Line Items Approved
        else if (timesheetStatus == 'Approved') {
            if (li.Line_Item_Status__c != 'Approved') {
                li.Line_Item_Status__c = 'Approved';
                lineItemsToUpdate.add(li);
            }
        }
    }

    // Single bulk update
    if (!lineItemsToUpdate.isEmpty()) {
        update lineItemsToUpdate;
    }

}
    private static void syncStatusFromLineItems(List<Timesheet__c> newTimesheets, Map<Id, Timesheet__c> oldMap) {
        Map<Id, Timesheet__c> timesheetsToSync = new Map<Id, Timesheet__c>();
        
        for (Timesheet__c ts : newTimesheets) {
            Timesheet__c oldTs = oldMap.get(ts.Id);
            // Only sync if the status was not explicitly modified
            if (ts.Status__c == oldTs.Status__c) {
                timesheetsToSync.put(ts.Id, ts);
            }
        }

        if (timesheetsToSync.isEmpty()) return;

        List<Timesheet_Line_Item__c> allItems = [
            SELECT Id, Timesheet__c, Line_Item_Status__c 
            FROM Timesheet_Line_Item__c 
            WHERE Timesheet__c IN :timesheetsToSync.keySet()
        ];

        Map<Id, Integer> totalCount = new Map<Id, Integer>();
        Map<Id, Integer> newCount = new Map<Id, Integer>();
        Map<Id, Integer> approvedCount = new Map<Id, Integer>();

        for (Timesheet_Line_Item__c li : allItems) {
            if (!totalCount.containsKey(li.Timesheet__c)) {
                totalCount.put(li.Timesheet__c, 0);
                newCount.put(li.Timesheet__c, 0);
                approvedCount.put(li.Timesheet__c, 0);
            }
            totalCount.put(li.Timesheet__c, totalCount.get(li.Timesheet__c) + 1);

            if (li.Line_Item_Status__c == 'New') {
                newCount.put(li.Timesheet__c, newCount.get(li.Timesheet__c) + 1);
            } else if (li.Line_Item_Status__c == 'Approved') {
                approvedCount.put(li.Timesheet__c, approvedCount.get(li.Timesheet__c) + 1);
            }
        }

        for (Timesheet__c ts : timesheetsToSync.values()) {
            if (totalCount.containsKey(ts.Id)) {
                Integer total = totalCount.get(ts.Id);
                Integer newItems = newCount.get(ts.Id);
                Integer approved = approvedCount.get(ts.Id);

                if (total == 0) {
                    continue;
                } else if (newItems == total) {
                    ts.Status__c = 'New';
                } else if (approved == total) {
                    ts.Status__c = 'Approved';
                } else {
                    ts.Status__c = 'Submitted';
                }
            }
        }
    }
}