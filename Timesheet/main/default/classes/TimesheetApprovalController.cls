public with sharing class TimesheetApprovalController {
    
    public class TimesheetWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String timesheetId { get; set; }
        @AuraEnabled public String timesheetName { get; set; }
        @AuraEnabled public String employeeName { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public Decimal duration { get; set; }
        @AuraEnabled public String timesheetPeriod { get; set; }
        @AuraEnabled public List<Timesheet_Line_Item__c> lineItems { get; set; }
        
        public TimesheetWrapper(String id, String timesheetId, String timesheetName, String employeeName, String projectName, String timesheetPeriod) {
            this.id = id;
            this.timesheetId = timesheetId;
            this.timesheetName = timesheetName;
            this.employeeName = employeeName;
            this.projectName = projectName;
            this.timesheetPeriod = timesheetPeriod;
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
                       '(SELECT Id, Date__c, Duration__c, Project__c, Project__r.Name, Type__c, Description__c, Billable__c ' +
                       'FROM Timesheets__r ' + 
                       'ORDER BY Date__c ASC) ' +
                       'FROM Timesheet__c ' +
                       'WHERE Manager__c = :userId AND Status__c = \'Submitted\' ';
        
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
                        wrapperMap.put(key, new TimesheetWrapper(key, ts.Id, ts.Name, ts.Employee__r.Name, projName, period));
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
    }
}