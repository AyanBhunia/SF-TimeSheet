public with sharing class TimesheetLineItemTriggerHandler {
    private static String errorMessage = 'You do not have access, Please contact system admin';
    
    public static void beforeInsert(List<Timesheet_Line_Item__c> timesheetLineItems){
        checkForDuplicateTimesheetLineItem(timesheetLineItems);
        updateEmployeeId(timesheetLineItems);
        updateBillableField(timesheetLineItems);
        LeaveValidator.checkLineItems(timesheetLineItems);
        checkDayTotals(timesheetLineItems);
    }

    public static void beforeUpdate(List<Timesheet_Line_Item__c> timesheetLineItems){
        checkForDuplicateTimesheetLineItem(timesheetLineItems);
        updateBillableField(timesheetLineItems);
        LeaveValidator.checkLineItems(timesheetLineItems);
        checkDayTotals(timesheetLineItems);
    }

    /**
     * @description The Duration_Limit_RTF flow only sees rows already saved, so several rows of one employee and day
     *              saved together (the weekly grid saves a whole week at once) can pass one by one and still exceed
     *              the daily maximum. For days with two or more rows in this save, the rows of the save plus the
     *              rows already saved are added up; above the maximum every row of that day is flagged, and the
     *              Duration_Validation rule shows its usual message. A single row per day is left to the flow.
     */
    public static void checkDayTotals(List<Timesheet_Line_Item__c> timesheetLineItems){
        Map<String, List<Timesheet_Line_Item__c>> byDay = new Map<String, List<Timesheet_Line_Item__c>>();
        for(Timesheet_Line_Item__c item : timesheetLineItems){
            if(item.Employee__c == null || item.Date__c == null){
                continue;
            }
            String key = dayKey(item.Employee__c, item.Date__c);
            if(!byDay.containsKey(key)){
                byDay.put(key, new List<Timesheet_Line_Item__c>());
            }
            byDay.get(key).add(item);
        }
        Set<Id> employeeIds = new Set<Id>();
        Set<Date> dates = new Set<Date>();
        for(List<Timesheet_Line_Item__c> rows : byDay.values()){
            if(rows.size() > 1){
                employeeIds.add(rows[0].Employee__c);
                dates.add(rows[0].Date__c);
            }
        }
        if(employeeIds.isEmpty()){
            return;
        }

        Set<Id> savingIds = new Set<Id>();
        for(Timesheet_Line_Item__c item : timesheetLineItems){
            if(item.Id != null){
                savingIds.add(item.Id);
            }
        }
        Map<String, Decimal> saved = new Map<String, Decimal>();
        for(AggregateResult ar : [SELECT Employee__c employeeId, Date__c day, SUM(Duration__c) hours
                                  FROM Timesheet_Line_Item__c
                                  WHERE Employee__c IN :employeeIds AND Date__c IN :dates AND Id NOT IN :savingIds
                                  GROUP BY Employee__c, Date__c]){
            saved.put(dayKey((Id) ar.get('employeeId'), (Date) ar.get('day')), (Decimal) ar.get('hours'));
        }
        Decimal max = LeaveValidator.dailyMax();
        for(String key : byDay.keySet()){
            List<Timesheet_Line_Item__c> rows = byDay.get(key);
            if(rows.size() < 2){
                continue;
            }
            Decimal total = saved.get(key) == null ? 0 : saved.get(key);
            for(Timesheet_Line_Item__c row : rows){
                total += row.Duration__c == null ? 0 : row.Duration__c;
            }
            if(total > max){
                for(Timesheet_Line_Item__c row : rows){
                    row.Hours_Limit_Exceeded__c = true;
                }
            }
        }
    }

    private static String dayKey(Id employeeId, Date day){
        return employeeId + '|' + String.valueOf(day);
    }
    
    public static void updateEmployeeId(List<Timesheet_Line_Item__c> timesheetLineItems){
        if(Timesheet__c.SObjectType.getDescribe().isAccessible() 
            && Schema.SObjectType.Timesheet__c.fields.Employee__c.isAccessible()
            && Timesheet_Line_Item__c.SObjectType.getDescribe().isCreateable()
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Employee__c.isCreateable()) {
                Set<Id> masterIds = new Set<Id>();
                for(Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems){
                    masterIds.add(timesheetLineItem.Timesheet__c);
                }
                Map<Id, Timesheet__c> timesheetMap = new Map<Id, Timesheet__c>([SELECT
                                                                Id,
                                                                Employee__c 
                                                                FROM Timesheet__c
                                                                WHERE Id = :masterIds 
                                                                WITH SECURITY_ENFORCED]);
                if(timesheetMap.size() > 0 ){
                    for(Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems){
                        timesheetLineItem.Employee__c = timesheetMap.get(timesheetLineItem.Timesheet__c).Employee__c;
                    }
                }
        } else {
            for(Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems){
                timesheetLineItem.addError(errorMessage);
            }
        }
    }
    
    public static void updateBillableField(List<Timesheet_Line_Item__c> timesheetLineItems){
        System.debug('Entering into updateBillableField method');
        if(Project__c.SObjectType.getDescribe().isAccessible() 
            && Schema.SObjectType.Project__c.fields.Id.isAccessible() 
            && Schema.SObjectType.Project__c.fields.Billable__c.isAccessible()
            && Timesheet_Line_Item__c.SObjectType.getDescribe().isCreateable()
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Billable__c.isCreateable()) {
                assignBillableField(timesheetLineItems);
        } else{
            for(Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems){
                timesheetLineItem.addError(errorMessage);
            }
        }
    }
    
    public static void checkForDuplicateTimesheetLineItem(List<Timesheet_Line_Item__c> timesheetLineItems){
        if(Timesheet_Line_Item__c.SObjectType.getDescribe().isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Id.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Project__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Date__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Activity__c.isAccessible() 
            && Schema.SObjectType.Timesheet_Line_Item__c.fields.Timesheet__c.isAccessible()) {
                validateDuplicationforTimesheetLineItem(timesheetLineItems);
        } else{
            for(Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems){
                timesheetLineItem.addError(errorMessage);
        	}
        }
    }

    private static void assignBillableField(List<Timesheet_Line_Item__c> timesheetLineItems){
        System.debug('Entering into assignBillableField method');
        List<Timesheet_Line_Item__c> newTimesheetLineItems = new List<Timesheet_Line_Item__c>();
        Set<Id> projectIds = new Set<Id>();
        for(Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems){
            if(timesheetLineItem.Project__c != null){
                newTimesheetLineItems.add(timesheetLineItem);
                projectIds.add(timesheetLineItem.Project__c);
            }
        }
        Map<Id, Project__c> projectMap = new Map<Id, Project__c>([SELECT
                                                Id,
                                                Billable__c
                                                FROM Project__c
                                                WHERE Id = : projectIds
                                                WITH SECURITY_ENFORCED]);
        if(projectMap.size() > 0){
            for(Timesheet_Line_Item__c timesheetLineItem : newTimesheetLineItems){
                timesheetLineItem.Billable__c = projectMap.get(timesheetLineItem.Project__c).Billable__c;
            }
        }
    }

    private static void validateDuplicationforTimesheetLineItem(List<Timesheet_Line_Item__c> timesheetLineItems){
        Set<Id> projectIds = new Set<Id>();
        Set<Date> dates = new Set<Date>();
        Set<Id> timesheetIds = new Set<Id>();
        for(Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems){
            projectIds.add(timesheetLineItem.Project__c);
            dates.add(timesheetLineItem.Date__c);
            timesheetIds.add(timesheetLineItem.Timesheet__c);
        }
        Map<Id, Timesheet_Line_Item__c> timesheetLineItemMap = new Map<Id, Timesheet_Line_Item__c>([SELECT
                                                                    Id,
                                                                    Project__c,
                                                                    Date__c,
                                                                    Activity__c,
                                                                    Absence_Category__c,
                                                                    Timesheet__c
                                                                    FROM Timesheet_Line_Item__c
                                                                    WHERE Project__c = : projectIds
                                                                    AND Date__c = : dates
                                                                    AND Timesheet__c = : timesheetIds
                                                                    WITH SECURITY_ENFORCED]);
        for(Timesheet_Line_Item__c timesheetLineItem : timesheetLineItems){
            for(Id id : timesheetLineItemMap.keySet()){
                if(timesheetLineItem.Id != timesheetLineItemMap.get(id).Id 
                    &&  timesheetLineItem.Date__c == timesheetLineItemMap.get(id).Date__c  
                    && timesheetLineItem.Project__c == timesheetLineItemMap.get(id).Project__c 
                    && timesheetLineItem.Timesheet__c == timesheetLineItemMap.get(id).Timesheet__c 
                    && timesheetLineItem.Activity__c == timesheetLineItemMap.get(id).Activity__c 
                    && timesheetLineItem.Absence_Category__c == timesheetLineItemMap.get(id).Absence_Category__c){
                        timesheetLineItem.addError('LineItem with the same project and activity or same absense category already exists for the same date, please update the existing record');
                }
            }
        }
    }
}