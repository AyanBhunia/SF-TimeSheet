public with sharing class TimesheetLineItemTriggerHandler extends TriggerHandler {

    private static String errorMessage = 'You do not have access, Please contact system admin';

    protected override void beforeInsert() {
        beforeInsert((List<Timesheet_Line_Item__c>)Trigger.new);
    }

    protected override void beforeUpdate() {
        beforeUpdate((List<Timesheet_Line_Item__c>)Trigger.new);
    }

    protected override void afterInsert() {
        updateTimesheetAccruals((List<Timesheet_Line_Item__c>)Trigger.new);
        touchParentTimesheetIfStatusChanged(
            (List<Timesheet_Line_Item__c>)Trigger.new,
            null
        );
    }

    protected override void afterUpdate() {
        updateTimesheetAccruals((List<Timesheet_Line_Item__c>)Trigger.new);
        touchParentTimesheetIfStatusChanged(
            (List<Timesheet_Line_Item__c>)Trigger.new,
            (Map<Id, Timesheet_Line_Item__c>)Trigger.oldMap
        );
    }

    protected override void afterDelete() {
        updateTimesheetAccruals((List<Timesheet_Line_Item__c>)Trigger.old);
    }

    protected override void afterUndelete() {
        updateTimesheetAccruals((List<Timesheet_Line_Item__c>)Trigger.new);
    }

    public static void beforeInsert(
        List<Timesheet_Line_Item__c> timesheetLineItems
    ) {
        checkForDuplicateTimesheetLineItem(timesheetLineItems);
        updateEmployeeId(timesheetLineItems);
        updateBillableField(timesheetLineItems);
    }

    public static void beforeUpdate(
        List<Timesheet_Line_Item__c> timesheetLineItems
    ) {
        checkForDuplicateTimesheetLineItem(timesheetLineItems);
        updateBillableField(timesheetLineItems);
    }

    public static void updateTimesheetAccruals(
        List<Timesheet_Line_Item__c> lineItems
    ) {
        if (lineItems == null || lineItems.isEmpty()) {
            return;
        }

        Set<Id> tsIds = new Set<Id>();

        for (Timesheet_Line_Item__c li : lineItems) {
            if (li.Timesheet__c != null) {
                tsIds.add(li.Timesheet__c);
            }
        }

        if (tsIds.isEmpty()) {
            return;
        }

        List<Timesheet__c> timesheets = [
            SELECT Id,
                   Status__c,
                   Employee__c,
                   Accrued_Hours__c
            FROM Timesheet__c
            WHERE Id IN :tsIds
            WITH SECURITY_ENFORCED
        ];

        List<Timesheet__c> eligible = new List<Timesheet__c>();
        Set<Id> empIds = new Set<Id>();

        for (Timesheet__c ts : timesheets) {
            if (AccrualCalculationService.isAccrualEligible(ts)) {
                eligible.add(ts);

                if (ts.Employee__c != null) {
                    empIds.add(ts.Employee__c);
                }
            }
        }

        if (!eligible.isEmpty()) {
            AccrualCalculationService.calculateTimesheetAccruals(eligible);

            SObjectAccessDecision securityDecision =
                Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    eligible
                );

            Database.update(securityDecision.getRecords(), false);

            if (!empIds.isEmpty()) {
                AccrualCalculationService.recalculateEmployeeTotals(empIds);
            }
        }
    }

    public static void updateEmployeeId(
        List<Timesheet_Line_Item__c> timesheetLineItems
    ) {
        if (
            Timesheet__c.SObjectType.getDescribe().isAccessible()
            && Schema.SObjectType.Timesheet__c.fields.Employee__c.isAccessible()
            && Timesheet_Line_Item__c.SObjectType.getDescribe().isCreateable()
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Employee__c.isCreateable()
        ) {
            Set<Id> masterIds = new Set<Id>();

            for (Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems) {
                if (timesheetLineItem.Timesheet__c != null) {
                    masterIds.add(timesheetLineItem.Timesheet__c);
                }
            }

            if (masterIds.isEmpty()) {
                return;
            }

            Map<Id, Timesheet__c> timesheetMap =
                new Map<Id, Timesheet__c>([
                    SELECT Id,
                           Employee__c
                    FROM Timesheet__c
                    WHERE Id IN :masterIds
                    WITH SECURITY_ENFORCED
                ]);

            if (timesheetMap.size() > 0) {
                for (Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems) {
                    if (timesheetMap.containsKey(timesheetLineItem.Timesheet__c)) {
                        timesheetLineItem.Employee__c =
                            timesheetMap.get(
                                timesheetLineItem.Timesheet__c
                            ).Employee__c;
                    }
                }
            }
        } else {
            for (Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems) {
                timesheetLineItem.addError(errorMessage);
            }
        }
    }

    public static void updateBillableField(
        List<Timesheet_Line_Item__c> timesheetLineItems
    ) {
        if (
            Project__c.SObjectType.getDescribe().isAccessible()
            && Schema.SObjectType.Project__c.fields.Id.isAccessible()
            && Schema.SObjectType.Project__c.fields.Billable__c.isAccessible()
            && Timesheet_Line_Item__c.SObjectType.getDescribe().isCreateable()
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Billable__c.isCreateable()
        ) {
            assignBillableField(timesheetLineItems);
        } else {
            for (Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems) {
                timesheetLineItem.addError(errorMessage);
            }
        }
    }

    public static void checkForDuplicateTimesheetLineItem(
        List<Timesheet_Line_Item__c> timesheetLineItems
    ) {
        if (
            Timesheet_Line_Item__c.SObjectType.getDescribe().isAccessible()
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Id.isAccessible()
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Project__c.isAccessible()
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Date__c.isAccessible()
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Activity__c.isAccessible()
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Timesheet__c.isAccessible()
        ) {
            validateDuplicationforTimesheetLineItem(timesheetLineItems);
        } else {
            for (Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems) {
                timesheetLineItem.addError(errorMessage);
            }
        }
    }

    private static void assignBillableField(
        List<Timesheet_Line_Item__c> timesheetLineItems
    ) {
        List<Timesheet_Line_Item__c> newTimesheetLineItems =
            new List<Timesheet_Line_Item__c>();

        Set<Id> projectIds = new Set<Id>();

        for (Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems) {
            if (timesheetLineItem.Project__c != null) {
                newTimesheetLineItems.add(timesheetLineItem);
                projectIds.add(timesheetLineItem.Project__c);
            }
        }

        if (projectIds.isEmpty()) {
            return;
        }

        Map<Id, Project__c> projectMap =
            new Map<Id, Project__c>([
                SELECT Id,
                       Billable__c
                FROM Project__c
                WHERE Id IN :projectIds
                WITH SECURITY_ENFORCED
            ]);

        if (projectMap.size() > 0) {
            for (Timesheet_Line_Item__c timesheetLineItem : newTimesheetLineItems) {
                if (projectMap.containsKey(timesheetLineItem.Project__c)) {
                    timesheetLineItem.Billable__c =
                        projectMap.get(timesheetLineItem.Project__c).Billable__c;
                }
            }
        }
    }

    private static void validateDuplicationforTimesheetLineItem(
        List<Timesheet_Line_Item__c> timesheetLineItems
    ) {
        Set<Id> projectIds = new Set<Id>();
        Set<Date> dates = new Set<Date>();
        Set<Id> timesheetIds = new Set<Id>();

        for (Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems) {
            if (timesheetLineItem.Project__c != null) {
                projectIds.add(timesheetLineItem.Project__c);
            }

            if (timesheetLineItem.Date__c != null) {
                dates.add(timesheetLineItem.Date__c);
            }

            if (timesheetLineItem.Timesheet__c != null) {
                timesheetIds.add(timesheetLineItem.Timesheet__c);
            }
        }

        if (
            projectIds.isEmpty()
            || dates.isEmpty()
            || timesheetIds.isEmpty()
        ) {
            return;
        }

        List<Timesheet_Line_Item__c> existingItems = [
            SELECT Id,
                   Project__c,
                   Date__c,
                   Activity__c,
                   Absence_Category__c,
                   Timesheet__c
            FROM Timesheet_Line_Item__c
            WHERE Project__c IN :projectIds
            AND Date__c IN :dates
            AND Timesheet__c IN :timesheetIds
            WITH SECURITY_ENFORCED
        ];

        for (Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems) {
            for (Timesheet_Line_Item__c existingItem : existingItems) {

                if (
                    timesheetLineItem.Id != existingItem.Id
                    && timesheetLineItem.Date__c == existingItem.Date__c
                    && timesheetLineItem.Project__c == existingItem.Project__c
                    && timesheetLineItem.Timesheet__c == existingItem.Timesheet__c
                    && timesheetLineItem.Activity__c == existingItem.Activity__c
                    && timesheetLineItem.Absence_Category__c == existingItem.Absence_Category__c
                ) {
                    timesheetLineItem.addError(
                        'LineItem with the same project and activity or same absense category already exists for the same date, please update the existing record'
                    );
                }
            }
        }
    }

    public static void touchParentTimesheetIfStatusChanged(
        List<Timesheet_Line_Item__c> newItems,
        Map<Id, Timesheet_Line_Item__c> oldMap
    ) {
        Set<Id> tsIds = new Set<Id>();

        for (Timesheet_Line_Item__c li : newItems) {
            if (li.Timesheet__c == null) {
                continue;
            }

            if (oldMap == null) {
                tsIds.add(li.Timesheet__c);
            } else {
                Timesheet_Line_Item__c oldLi = oldMap.get(li.Id);

                if (
                    oldLi != null
                    && oldLi.Line_Item_Status__c != li.Line_Item_Status__c
                ) {
                    tsIds.add(li.Timesheet__c);
                }
            }
        }

        if (tsIds.isEmpty()) {
            return;
        }

        List<Timesheet__c> parents = [
            SELECT Id,
                   Status__c,
                   Start_Date__c,
                   End_Date__c,
                   Is_Partial_Allowed__c,
                   Met_Weekly_Hours__c
            FROM Timesheet__c
            WHERE Id IN :tsIds
            WITH SECURITY_ENFORCED
        ];

        List<Timesheet_Line_Item__c> allItems = [
            SELECT Id,
                   Timesheet__c,
                   Date__c,
                   Line_Item_Status__c
            FROM Timesheet_Line_Item__c
            WHERE Timesheet__c IN :tsIds
            WITH SECURITY_ENFORCED
        ];

        Map<Id, List<Timesheet_Line_Item__c>> itemsByTimesheet =
            new Map<Id, List<Timesheet_Line_Item__c>>();

        for (Timesheet_Line_Item__c li : allItems) {
            if (!itemsByTimesheet.containsKey(li.Timesheet__c)) {
                itemsByTimesheet.put(
                    li.Timesheet__c,
                    new List<Timesheet_Line_Item__c>()
                );
            }

            itemsByTimesheet.get(li.Timesheet__c).add(li);
        }

        List<Timesheet__c> parentsToUpdate =
            new List<Timesheet__c>();

        for (Timesheet__c parent : parents) {

            // Preserve existing behaviour for non-partial Timesheets.
            if (parent.Is_Partial_Allowed__c == false) {
                continue;
            }

            List<Timesheet_Line_Item__c> items =
                itemsByTimesheet.get(parent.Id);

            if (items == null || items.isEmpty()) {
                continue;
            }

            // Check only existing line items.
            // No requirement for all seven days to contain entries.
            Boolean allLineItemsApproved = true;

            for (Timesheet_Line_Item__c li : items) {
                if (li.Line_Item_Status__c != 'Approved') {
                    allLineItemsApproved = false;
                    break;
                }
            }

            // Approve parent only when weekly hours are met
            // and all existing line items are Approved.
            String newStatus =
                (
                    parent.Met_Weekly_Hours__c == true
                    && allLineItemsApproved
                )
                ? 'Approved'
                : 'Submitted';

            if (parent.Status__c != newStatus) {
                parentsToUpdate.add(
                    new Timesheet__c(
                        Id = parent.Id,
                        Status__c = newStatus
                    )
                );
            }
        }

        if (!parentsToUpdate.isEmpty()) {
            SObjectAccessDecision securityDecision =
                Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    parentsToUpdate
                );

            Database.update(
                securityDecision.getRecords(),
                false
            );
        }
    }
}