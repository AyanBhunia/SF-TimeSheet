public with sharing class TimesheetApprovalController {
    
    public class TimesheetWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String timesheetId { get; set; }
        @AuraEnabled public String timesheetName { get; set; }
        @AuraEnabled public String employeeName { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public Decimal duration { get; set; }
        @AuraEnabled public String timesheetPeriod { get; set; }
        @AuraEnabled public String timesheetStatus { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public List<Timesheet_Line_Item__c> lineItems { get; set; }
        
        public TimesheetWrapper(String id, String timesheetId, String timesheetName, String employeeName, String projectName, String timesheetPeriod, String timesheetStatus, Date startDate) {
            this.id = id;
            this.timesheetId = timesheetId;
            this.timesheetName = timesheetName;
            this.employeeName = employeeName;
            this.projectName = projectName;
            this.timesheetPeriod = timesheetPeriod;
            this.timesheetStatus = timesheetStatus;
            this.startDate = startDate;
            this.duration = 0;
            this.lineItems = new List<Timesheet_Line_Item__c>();
        }
    }
    
    @AuraEnabled(cacheable=true)
    public static List<TimesheetWrapper> getTimesheetData(String dateRange, Date customStartDate, Date customEndDate) {
        Date startDate;
        Date endDate;
        
        if (dateRange == 'Current Week') {
            startDate = Date.today().toStartOfWeek();
            endDate = startDate.addDays(6);
        } else if (dateRange == 'Last Week') {
            startDate = Date.today().toStartOfWeek().addDays(-7);
            endDate = startDate.addDays(6);
        } else if (dateRange == 'Current Month') {
            startDate = Date.today().toStartOfMonth();
            endDate = startDate.addMonths(1).addDays(-1);
        } else if (dateRange == 'Last Month') {
            startDate = Date.today().toStartOfMonth().addMonths(-1);
            endDate = Date.today().toStartOfMonth().addDays(-1);
        } else if (dateRange == 'Custom') {
            startDate = customStartDate;
            endDate = customEndDate;
        }
        
        String userId = UserInfo.getUserId();
        
        String query = 'SELECT Id, Name, Employee__r.Name, Start_Date__c, End_Date__c, Status__c, ' +
                       '(SELECT Id, Date__c, Duration__c, Project__c, Project__r.Name, Type__c, Description__c, Billable__c, Line_Item_Status__c, Rejection_Notes__c, Activity__c, Absence_Category__c ' +
                       'FROM Timesheets__r ' + 
                       'ORDER BY Date__c ASC) ' +
                       'FROM Timesheet__c ' +
                       'WHERE Manager__c = :userId AND Status__c IN (\'Submitted\', \'Partial\') ';
        
        if (startDate != null && endDate != null) {
            query += 'AND Start_Date__c >= :startDate AND Start_Date__c <= :endDate';
        }
        
        List<Timesheet__c> timesheets = Database.query(query);
        
        Map<String, TimesheetWrapper> wrapperMap = new Map<String, TimesheetWrapper>();
        
        for (Timesheet__c ts : timesheets) {
            String period = (ts.Start_Date__c != null ? ts.Start_Date__c.format() : '') + ' to ' + 
                            (ts.End_Date__c != null ? ts.End_Date__c.format() : '');
                            
            if (ts.Timesheets__r != null && !ts.Timesheets__r.isEmpty()) {
                for (Timesheet_Line_Item__c line : ts.Timesheets__r) {
                    String projName = (line.Project__c != null) ? line.Project__r.Name : line.Type__c; 
                    if (line.Type__c == 'Absence') {
                        projName = 'Absence';
                    }
                    String key = ts.Id + '_' + projName;
                    
                    if (!wrapperMap.containsKey(key)) {
                        wrapperMap.put(key, new TimesheetWrapper(key, ts.Id, ts.Name, ts.Employee__r.Name, projName, period, ts.Status__c, ts.Start_Date__c));
                    }
                    
                    TimesheetWrapper tw = wrapperMap.get(key);
                    tw.duration += (line.Duration__c != null ? line.Duration__c : 0);
                    tw.lineItems.add(line);
                }
            }
        }
        
        return wrapperMap.values();
    }
    
    @AuraEnabled
    public static void approveTimesheets(List<Id> timesheetIds) {
        if (timesheetIds == null || timesheetIds.isEmpty()) return;
        
        Set<Id> uniqueIds = new Set<Id>(timesheetIds);
        
        List<Timesheet__c> toUpdate = new List<Timesheet__c>();
        for (Id tsId : uniqueIds) {
            toUpdate.add(new Timesheet__c(Id = tsId, Status__c = 'Approved'));
        }
        update toUpdate;

        List<Timesheet_Line_Item__c> children = [
            SELECT Id, Line_Item_Status__c
            FROM Timesheet_Line_Item__c
            WHERE Timesheet__c IN :uniqueIds
        ];
        if (!children.isEmpty()) {
            for (Timesheet_Line_Item__c li : children) {
                li.Line_Item_Status__c = 'Approved';
            }
            update children;
        }
    }

    @AuraEnabled
    public static String approveLineItems(List<Id> lineItemIds) {
        if (lineItemIds == null || lineItemIds.isEmpty()) return 'Error: No line items provided.';
        try {
            List<Timesheet_Line_Item__c> items = [
                SELECT Id, Line_Item_Status__c, Timesheet__c
                FROM Timesheet_Line_Item__c
                WHERE Id IN :lineItemIds
                WITH SECURITY_ENFORCED
            ];
            Set<Id> tsIds = new Set<Id>();
            for (Timesheet_Line_Item__c li : items) {
                li.Line_Item_Status__c = 'Partial Approved';
                tsIds.add(li.Timesheet__c);
            }
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, items, true);
            update decision.getRecords();

            updateParentPartialStatus(tsIds);
            return 'Success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }

    @AuraEnabled
    public static String rejectLineItemsWithNotes(List<Id> lineItemIds, String rejectionNotes) {
        if (lineItemIds == null || lineItemIds.isEmpty()) return 'Error: No line items provided.';
        try {
            List<Timesheet_Line_Item__c> items = [
                SELECT Id, Line_Item_Status__c, Rejection_Notes__c, Timesheet__c
                FROM Timesheet_Line_Item__c
                WHERE Id IN :lineItemIds
                WITH SECURITY_ENFORCED
            ];
            Set<Id> tsIds = new Set<Id>();
            for (Timesheet_Line_Item__c li : items) {
                li.Line_Item_Status__c = 'New';
                li.Rejection_Notes__c = rejectionNotes;
                tsIds.add(li.Timesheet__c);
            }
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, items, true);
            update decision.getRecords();

            updateParentPartialStatus(tsIds);
            return 'Success';
        } catch (Exception e) {
            return 'Error: ' + e.getMessage();
        }
    }

    private static void updateParentPartialStatus(Set<Id> tsIds) {
        if (tsIds == null || tsIds.isEmpty()) return;
        List<Timesheet__c> parents = [
            SELECT Id, Status__c,
                   (SELECT Id, Line_Item_Status__c FROM Timesheets__r)
            FROM Timesheet__c
            WHERE Id IN :tsIds
            WITH SECURITY_ENFORCED
        ];
        List<Timesheet__c> toUpdate = new List<Timesheet__c>();
        for (Timesheet__c ts : parents) {
            Boolean allNew = true;
            for (Timesheet_Line_Item__c li : ts.Timesheets__r) {
                if (li.Line_Item_Status__c != 'New') {
                    allNew = false;
                    break;
                }
            }

            if (allNew) {
                // All items are New → revert Timesheet to New
                if (ts.Status__c != 'New') {
                    ts.Status__c = 'New';
                    toUpdate.add(ts);
                }
            } else {
                if (ts.Status__c != 'Partial') {
                    ts.Status__c = 'Partial';
                    toUpdate.add(ts);
                }
            }
        }
        if (!toUpdate.isEmpty()) {
            SObjectAccessDecision decision = Security.stripInaccessible(AccessType.UPDATABLE, toUpdate, true);
            update decision.getRecords();
        }
    }

    @AuraEnabled
    public static void rejectTimesheets(List<Id> timesheetIds) {
        if (timesheetIds == null || timesheetIds.isEmpty()) return;

        Set<Id> uniqueIds = new Set<Id>(timesheetIds);

        // Update Timesheet to New
        List<Timesheet__c> toUpdate = new List<Timesheet__c>();
        for (Id tsId : uniqueIds) {
            toUpdate.add(new Timesheet__c(Id = tsId, Status__c = 'New'));
        }
        update toUpdate;

        // Update all line items to New, EXCEPT Partial Approved
        List<Timesheet_Line_Item__c> children = [
            SELECT Id, Line_Item_Status__c
            FROM Timesheet_Line_Item__c
            WHERE Timesheet__c IN :uniqueIds
            AND Line_Item_Status__c != 'Partial Approved'
        ];
        if (!children.isEmpty()) {
            for (Timesheet_Line_Item__c li : children) {
                li.Line_Item_Status__c = 'New';
            }
            update children;
        }
    }
}