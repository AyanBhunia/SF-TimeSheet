/**
 * @description Dedicated controller class for creating, inspecting, and deleting demo/test data for the Timesheet application.
 * @author Ayan
 */
global with sharing class DemoDataController {

    global class DemoRecordDetail {
        @AuraEnabled global Integer stepNumber { get; set; }
        @AuraEnabled global String stepTitle { get; set; }
        @AuraEnabled global String recordId { get; set; }
        @AuraEnabled global String recordName { get; set; }
        @AuraEnabled global String objectType { get; set; }
        @AuraEnabled global String objectLabel { get; set; }
        @AuraEnabled global String recordUrl { get; set; }
        @AuraEnabled global String details { get; set; }
        @AuraEnabled global String summary { get; set; }
        @AuraEnabled global String whatItDoes { get; set; }
        @AuraEnabled global Boolean isTestEmployee1 { get; set; }
        @AuraEnabled global Boolean hasChildEmployees { get; set; }
    }

    global class TimesheetLineItemDetail {
        @AuraEnabled global String id { get; set; }
        @AuraEnabled global String dateStr { get; set; }
        @AuraEnabled global String type { get; set; }
        @AuraEnabled global String project { get; set; }
        @AuraEnabled global Decimal duration { get; set; }
        @AuraEnabled global String description { get; set; }
    }

    global class TimesheetDetail {
        @AuraEnabled global String recordId { get; set; }
        @AuraEnabled global String name { get; set; }
        @AuraEnabled global String periodName { get; set; }
        @AuraEnabled global String dateRange { get; set; }
        @AuraEnabled global String status { get; set; }
        @AuraEnabled global Decimal totalHours { get; set; }
        @AuraEnabled global String recordUrl { get; set; }
        @AuraEnabled global String employeeName { get; set; }
        @AuraEnabled global List<TimesheetLineItemDetail> lineItems { get; set; }
        @AuraEnabled global Boolean isOpen { get; set; }
    }

    global class DemoDataWrapper {
        @AuraEnabled global List<DemoRecordDetail> employees { get; set; }
        @AuraEnabled global List<DemoRecordDetail> projects { get; set; }
        @AuraEnabled global List<DemoRecordDetail> projectEmployees { get; set; }
        @AuraEnabled global List<TimesheetDetail> timesheets { get; set; }
    }



    @AuraEnabled
    global static Map<String, Object> getDemoStatus() {
        Map<String, Object> result = new Map<String, Object>();
        result.put('hasAccess', true);
        
        Id currentUserId = UserInfo.getUserId();
        List<Employee__c> emps = [
            SELECT Id, First_Name__c, Last_Name__c, Name 
            FROM Employee__c 
            WHERE ((Last_Name__c = 'T.' OR Last_Name__c LIKE 'employee %') AND CreatedById = :currentUserId) AND Active__c = true
            WITH SECURITY_ENFORCED
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        if (emps.isEmpty()) {
            result.put('hasEmployee', false);
            result.put('isTestEmployee', false);
            result.put('employeeName', null);
        } else {
            Employee__c emp = emps[0];
            String fullName = (emp.First_Name__c != null ? emp.First_Name__c + ' ' : '') + (emp.Last_Name__c != null ? emp.Last_Name__c : '');
            fullName = fullName.trim();
            result.put('hasEmployee', true);
            result.put('isTestEmployee', true); // always treat it as valid for demo setup
            result.put('employeeName', fullName);
            result.put('employeeId', emp.Id);
        }
        return result;
    }

    @AuraEnabled
    global static String createDemoData() {
        try {
            Id currentUserId = UserInfo.getUserId();
            Id managerUserId = null;
            User currentUser = [SELECT Id, ManagerId FROM User WHERE Id = :currentUserId WITH SECURITY_ENFORCED LIMIT 1];
            if (currentUser != null && currentUser.ManagerId != null) {
                managerUserId = currentUser.ManagerId;
            }

            if (managerUserId == null) {
                AuraHandledException e = new AuraHandledException('Please assign a manager in your User record before creating demo data.');
                e.setMessage('Please assign a manager in your User record before creating demo data.');
                throw e;
            }

            List<Employee__c> existingEmpList = [
                SELECT Id, First_Name__c, Last_Name__c, User__c 
                FROM Employee__c 
                WHERE User__c = :currentUserId OR Last_Name__c IN ('T.', 'E1', 'E2') OR Last_Name__c LIKE 'Child Employee%'
                WITH SECURITY_ENFORCED
            ];
            if (!existingEmpList.isEmpty()) {
                delete existingEmpList;
            }
            
            Employee__c empManager = new Employee__c(
                First_Name__c = 'Test', Last_Name__c = 'T.', User__c = currentUserId, Email__c = UserInfo.getUserEmail(), Manager__c = managerUserId, Employment_Type__c = 'Full Time', Active__c = true, Accrual_Start_Date__c = System.today().addMonths(-1), Accrual_Divisor__c = 8, Extra_Accrued_Hours__c = 30
            );
            insert empManager;

            Employee__c empE1 = new Employee__c(
                First_Name__c = 'Test', Last_Name__c = 'E1', Manager__c = currentUserId, Employment_Type__c = 'Full Time', Active__c = true, Accrual_Start_Date__c = System.today().addMonths(-1), Accrual_Divisor__c = 8, Extra_Accrued_Hours__c = 30
            );
            Employee__c empE2 = new Employee__c(
                First_Name__c = 'Test', Last_Name__c = 'E2', Manager__c = currentUserId, Employment_Type__c = 'Full Time', Active__c = true, Accrual_Start_Date__c = System.today().addMonths(-1), Accrual_Divisor__c = 8, Extra_Accrued_Hours__c = 30
            );
            insert new List<Employee__c>{empE1, empE2};

            Date today = Date.today();
            Integer modDays = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(today), 7);
            if (modDays < 0) {
                modDays += 7;
            }
            Date thisWeekMonday = today.addDays(-modDays);
            Date lastWeekMonday = thisWeekMonday.addDays(-7);
            Date lastLastWeekMonday = thisWeekMonday.addDays(-14);
            Date nextWeekMonday = thisWeekMonday.addDays(7);

            List<Timesheet__c> existingTs = [
                SELECT Id 
                FROM Timesheet__c 
                WHERE Employee__c IN :new List<Id>{empManager.Id, empE1.Id, empE2.Id} 
                WITH SECURITY_ENFORCED
            ];
            if (!existingTs.isEmpty()) {
                delete existingTs;
            }

            List<String> projNames = new List<String>{
                'Demo Project - Billable',
                'Demo Project - Non-Billable',
                'Demo Project - Legacy'
            };
            Map<String, Project__c> projMap = new Map<String, Project__c>();
            for (Project__c p : [
                SELECT Id, Name, Active__c, Billable__c 
                FROM Project__c 
                WHERE Name IN :projNames
                WITH SECURITY_ENFORCED
            ]) {
                projMap.put(p.Name, p);
            }

            Project__c projBillable = projMap.get('Demo Project - Billable');
            if (projBillable == null) {
                projBillable = new Project__c(Name = 'Demo Project - Billable', Active__c = true, Billable__c = 'Yes');
                insert projBillable;
            } else if (!projBillable.Active__c || projBillable.Billable__c != 'Yes') {
                projBillable.Active__c = true;
                projBillable.Billable__c = 'Yes';
                update projBillable;
            }

            Project__c projNonBillable = projMap.get('Demo Project - Non-Billable');
            if (projNonBillable == null) {
                projNonBillable = new Project__c(Name = 'Demo Project - Non-Billable', Active__c = true, Billable__c = 'No');
                insert projNonBillable;
            } else if (!projNonBillable.Active__c || projNonBillable.Billable__c != 'No') {
                projNonBillable.Active__c = true;
                projNonBillable.Billable__c = 'No';
                update projNonBillable;
            }

            Project__c projToInactive = projMap.get('Demo Project - Legacy');
            if (projToInactive == null) {
                projToInactive = new Project__c(Name = 'Demo Project - Legacy', Active__c = true, Billable__c = 'No');
                insert projToInactive;
            } else if (!projToInactive.Active__c || projToInactive.Billable__c != 'No') {
                projToInactive.Active__c = true;
                projToInactive.Billable__c = 'No';
                update projToInactive;
            }

            Set<Id> projIds = new Set<Id>{ projBillable.Id, projNonBillable.Id, projToInactive.Id };
            Set<Id> targetEmpIds = new Set<Id>{ empE1.Id, empE2.Id };
            List<Project_Employee__c> peListToInsert = new List<Project_Employee__c>();
            
            for (Id eId : targetEmpIds) {
                for (Id pId : projIds) {
                    peListToInsert.add(new Project_Employee__c(
                        Employee__c = eId,
                        Project__c = pId,
                        Hourly_Rate__c = 150
                    ));
                }
            }
            if (!peListToInsert.isEmpty()) {
                insert peListToInsert;
            }

            List<Timesheet__c> allTs = new List<Timesheet__c>();
            for (Employee__c emp : new List<Employee__c>{empE1, empE2}) {
                allTs.add(new Timesheet__c(Employee__c = emp.Id, Manager__c = emp.Manager__c, Start_Date__c = lastLastWeekMonday, End_Date__c = lastLastWeekMonday.addDays(6), Status__c = 'New'));
                allTs.add(new Timesheet__c(Employee__c = emp.Id, Manager__c = emp.Manager__c, Start_Date__c = lastWeekMonday, End_Date__c = lastWeekMonday.addDays(6), Status__c = 'New'));
                allTs.add(new Timesheet__c(Employee__c = emp.Id, Manager__c = emp.Manager__c, Start_Date__c = thisWeekMonday, End_Date__c = thisWeekMonday.addDays(6), Status__c = 'New'));
                allTs.add(new Timesheet__c(Employee__c = emp.Id, Manager__c = emp.Manager__c, Start_Date__c = nextWeekMonday, End_Date__c = nextWeekMonday.addDays(6), Status__c = 'New'));
            }
            insert allTs;

            List<Timesheet_Line_Item__c> itemsToInsert = new List<Timesheet_Line_Item__c>();
            List<Timesheet__c> tsThisWeekList = new List<Timesheet__c>();
            List<Timesheet__c> tsToApprove = new List<Timesheet__c>();

            for (Timesheet__c ts : allTs) {
                if (ts.Start_Date__c == lastLastWeekMonday) {
                    for (Integer day = 0; day < 7; day++) {
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projToInactive.Id, Activity__c = 'Development-Coding', Duration__c = 8, Description__c = 'Demo Data - Project work'));
                    }
                    tsToApprove.add(ts);
                } else if (ts.Start_Date__c == lastWeekMonday) {
                    for (Integer day = 0; day < 7; day++) {
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projBillable.Id, Activity__c = 'Development-Coding', Duration__c = 4, Description__c = 'Demo Data - Billable work'));
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projNonBillable.Id, Activity__c = 'Meeting', Duration__c = 4, Description__c = 'Demo Data - Non-billable work'));
                        if (day == 1) { // Tuesday
                            itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Absence', Absence_Category__c = 'Sick Leave', Duration__c = 8, Description__c = 'Demo Data - Sick Leave'));
                        }
                    }
                    tsToApprove.add(ts);
                } else if (ts.Start_Date__c == thisWeekMonday) {
                    for (Integer day = 0; day < 7; day++) {
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projBillable.Id, Activity__c = 'Development-Coding', Duration__c = 2, Description__c = 'Demo Data - Billable work'));
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projNonBillable.Id, Activity__c = 'Meeting', Duration__c = 2, Description__c = 'Demo Data - Non-billable work'));
                        if (day == 1 || day == 2) { // Tuesday, Wednesday
                            itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Absence', Absence_Category__c = 'Sick Leave', Duration__c = 8, Description__c = 'Demo Data - Sick Leave'));
                        }
                    }
                    tsThisWeekList.add(ts);
                }
            }

            if (!itemsToInsert.isEmpty()) {
                insert itemsToInsert;
            }

            // Removed status updates so timesheets remain 'New'

            projToInactive.Active__c = false;
            update projToInactive;

            return 'Success';
        } catch (Exception e) {
            System.debug('CRITICAL_DEMO_DATA_ERROR: ' + e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
            if (Test.isRunningTest()) {
                throw e;
            }
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    global static String createDemoProjects() {
        try {
            Id currentUserId = UserInfo.getUserId();
            Integer empNumber = 1;
            List<Employee__c> currentEmps = [
                SELECT Last_Name__c 
                FROM Employee__c 
                WHERE User__c = :UserInfo.getUserId() 
                AND First_Name__c = 'test' 
                AND Last_Name__c LIKE 'employee %' 
                WITH SECURITY_ENFORCED 
                ORDER BY CreatedDate DESC 
                LIMIT 1
            ];
            if (!currentEmps.isEmpty()) {
                String numStr = currentEmps[0].Last_Name__c.replace('employee ', '').trim();
                if (numStr.isNumeric()) {
                    empNumber = Integer.valueOf(numStr);
                }
            }
            
            String prefix = 'Test Project ' + empNumber + ' - ';
            List<String> projNames = new List<String>{prefix + 'Billable', prefix + 'Non Billable', prefix + 'Legacy'};
            Map<String, Project__c> projMap = new Map<String, Project__c>();
            for (Project__c p : [SELECT Id, Name, Active__c, Billable__c FROM Project__c WHERE Name LIKE 'Test Project%' AND CreatedById = :currentUserId WITH SECURITY_ENFORCED]) {
                projMap.put(p.Name, p);
            }
            
            List<Project__c> toUpsert = new List<Project__c>();
            
            Project__c p1 = projMap.get(projNames[0]);
            if (p1 == null) p1 = new Project__c(Name = projNames[0]);
            p1.Active__c = true; p1.Billable__c = 'Yes';
            toUpsert.add(p1);

            Project__c p2 = projMap.get(projNames[1]);
            if (p2 == null) p2 = new Project__c(Name = projNames[1]);
            p2.Active__c = true; p2.Billable__c = 'No';
            toUpsert.add(p2);

            Project__c p3 = projMap.get(projNames[2]);
            if (p3 == null) p3 = new Project__c(Name = projNames[2]);
            p3.Active__c = true; p3.Billable__c = 'No';
            toUpsert.add(p3);

            upsert toUpsert;
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    global static String createDemoProjectAssignments() {
        try {
            Id currentUserId = UserInfo.getUserId();
            List<Project__c> projs = [SELECT Id FROM Project__c WHERE Name LIKE 'Test Project%' AND CreatedById = :currentUserId WITH SECURITY_ENFORCED];
            List<Employee__c> emps = [SELECT Id FROM Employee__c WHERE ((Last_Name__c IN ('T.', 'E1', 'E2') OR Last_Name__c LIKE 'Child Employee%' OR Last_Name__c LIKE 'employee %') AND CreatedById = :currentUserId) WITH SECURITY_ENFORCED];
            List<Project_Employee__c> toInsert = new List<Project_Employee__c>();
            
            Set<String> existingKeys = new Set<String>();
            for (Project_Employee__c pe : [SELECT Employee__c, Project__c FROM Project_Employee__c WHERE Employee__c IN :emps WITH SECURITY_ENFORCED]) {
                existingKeys.add((String)pe.Employee__c + (String)pe.Project__c);
            }
            
            for (Employee__c emp : emps) {
                for (Project__c p : projs) {
                    if (!existingKeys.contains((String)emp.Id + (String)p.Id)) {
                        toInsert.add(new Project_Employee__c(Employee__c = emp.Id, Project__c = p.Id, Hourly_Rate__c = 150));
                    }
                }
            }
            if (!toInsert.isEmpty()) insert toInsert;
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    global static String createDemoTimesheets() {
        try {
            Id currentUserId = UserInfo.getUserId();
            List<Employee__c> emps = [SELECT Id, Manager__c FROM Employee__c WHERE ((Last_Name__c IN ('T.', 'E1', 'E2') OR Last_Name__c LIKE 'Child Employee%' OR Last_Name__c LIKE 'employee %') AND CreatedById = :currentUserId) WITH SECURITY_ENFORCED];
            Date today = Date.today();
            Integer modDays = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(today), 7);
            if (modDays < 0) modDays += 7;
            Date thisWeekMonday = today.addDays(-modDays);
            Date lastWeekMonday = thisWeekMonday.addDays(-7);
            Date lastLastWeekMonday = thisWeekMonday.addDays(-14);
            Date nextWeekMonday = thisWeekMonday.addDays(7);
            
            Set<String> existingKeys = new Set<String>();
            for (Timesheet__c ts : [SELECT Employee__c, Start_Date__c FROM Timesheet__c WHERE Employee__c IN :emps WITH SECURITY_ENFORCED]) {
                existingKeys.add((String)ts.Employee__c + ts.Start_Date__c);
            }

            List<Timesheet__c> toInsert = new List<Timesheet__c>();
            for (Employee__c emp : emps) {
                List<Date> dts = new List<Date>{lastLastWeekMonday, lastWeekMonday, thisWeekMonday, nextWeekMonday};
                for (Date dt : dts) {
                    if (!existingKeys.contains((String)emp.Id + dt)) {
                        toInsert.add(new Timesheet__c(Employee__c = emp.Id, Manager__c = emp.Manager__c, Start_Date__c = dt, End_Date__c = dt.addDays(6), Status__c = 'New'));
                    }
                }
            }
            if (!toInsert.isEmpty()) {
                insert toInsert;
                
                List<Project__c> projs = [SELECT Id, Name FROM Project__c WHERE Name LIKE 'Test Project%' AND CreatedById = :currentUserId WITH SECURITY_ENFORCED];
                Id projBillable, projNonBillable, projLegacy;
                for (Project__c p : projs) {
                    if (p.Name.contains('Billable') && !p.Name.contains('Non')) projBillable = p.Id;
                    if (p.Name.contains('Non Billable')) projNonBillable = p.Id;
                    if (p.Name.contains('Legacy')) projLegacy = p.Id;
                }
                
                List<Timesheet_Line_Item__c> itemsToInsert = new List<Timesheet_Line_Item__c>();
                for (Timesheet__c ts : toInsert) {
                    if (ts.Start_Date__c == lastLastWeekMonday) {
                        for (Integer day = 0; day < 7; day++) {
                            itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projLegacy, Activity__c = 'Development-Coding', Duration__c = 8, Description__c = 'Demo Data - Project work'));
                        }
                    } else if (ts.Start_Date__c == lastWeekMonday) {
                        for (Integer day = 0; day < 7; day++) {
                            itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projBillable, Activity__c = 'Development-Coding', Duration__c = 4, Description__c = 'Demo Data - Billable work'));
                            itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projNonBillable, Activity__c = 'Meeting', Duration__c = 4, Description__c = 'Demo Data - Non-billable work'));
                            if (day == 1) itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Absence', Absence_Category__c = 'Sick Leave', Duration__c = 8, Description__c = 'Demo Data - Sick Leave'));
                        }
                    } else if (ts.Start_Date__c == thisWeekMonday) {
                        for (Integer day = 0; day < 7; day++) {
                            itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projBillable, Activity__c = 'Development-Coding', Duration__c = 2, Description__c = 'Demo Data - Billable work'));
                            itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projNonBillable, Activity__c = 'Meeting', Duration__c = 2, Description__c = 'Demo Data - Non-billable work'));
                            if (day == 1 || day == 2) itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Absence', Absence_Category__c = 'Sick Leave', Duration__c = 8, Description__c = 'Demo Data - Sick Leave'));
                        }
                    } else {
                        for (Integer day = 0; day < 5; day++) {
                            itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projBillable, Activity__c = 'Development-Coding', Duration__c = 8, Description__c = 'Demo Data - Standard Billable work'));
                        }
                    }
                }
                
                if(!itemsToInsert.isEmpty()) {
                    insert itemsToInsert;
                }
            }
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    global static String createDemoTimesheetLineItems(String timesheetId) {
        try {
            Id currentUserId = UserInfo.getUserId();
            List<Project__c> projs = [SELECT Id, Name FROM Project__c WHERE Name LIKE 'Test Project%' AND CreatedById = :currentUserId WITH SECURITY_ENFORCED];
            Id projBillable, projNonBillable, projLegacy;
            for (Project__c p : projs) {
                if (p.Name.contains('Billable') && !p.Name.contains('Non')) projBillable = p.Id;
                if (p.Name.contains('Non-Billable')) projNonBillable = p.Id;
                if (p.Name.contains('Legacy')) projLegacy = p.Id;
            }
            if (projBillable == null || projNonBillable == null || projLegacy == null) {
                throw new AuraHandledException('Please create projects first before adding line items.');
            }

            Date today = Date.today();
            Integer modDays = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(today), 7);
            if (modDays < 0) modDays += 7;
            Date thisWeekMonday = today.addDays(-modDays);
            Date lastWeekMonday = thisWeekMonday.addDays(-7);
            Date lastLastWeekMonday = thisWeekMonday.addDays(-14);

            List<Timesheet__c> existingTs = [SELECT Id, Start_Date__c, Employee__c, (SELECT Id FROM Timesheets__r) FROM Timesheet__c WHERE Id = :timesheetId WITH SECURITY_ENFORCED];
            List<Timesheet_Line_Item__c> itemsToInsert = new List<Timesheet_Line_Item__c>();

            for (Timesheet__c ts : existingTs) {
                if (ts.Timesheets__r != null && ts.Timesheets__r.size() > 0) continue; // skip if already has items
                
                if (ts.Start_Date__c == lastLastWeekMonday) {
                    for (Integer day = 0; day < 7; day++) {
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projLegacy, Activity__c = 'Development-Coding', Duration__c = 8, Description__c = 'Demo Data - Project work'));
                    }
                } else if (ts.Start_Date__c == lastWeekMonday) {
                    for (Integer day = 0; day < 7; day++) {
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projBillable, Activity__c = 'Development-Coding', Duration__c = 4, Description__c = 'Demo Data - Billable work'));
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projNonBillable, Activity__c = 'Meeting', Duration__c = 4, Description__c = 'Demo Data - Non-billable work'));
                        if (day == 1) itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Absence', Absence_Category__c = 'Sick Leave', Duration__c = 8, Description__c = 'Demo Data - Sick Leave'));
                    }
                } else if (ts.Start_Date__c == thisWeekMonday) {
                    for (Integer day = 0; day < 7; day++) {
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projBillable, Activity__c = 'Development-Coding', Duration__c = 2, Description__c = 'Demo Data - Billable work'));
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projNonBillable, Activity__c = 'Meeting', Duration__c = 2, Description__c = 'Demo Data - Non-billable work'));
                        if (day == 1 || day == 2) itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Absence', Absence_Category__c = 'Sick Leave', Duration__c = 8, Description__c = 'Demo Data - Sick Leave'));
                    }
                } else {
                    for (Integer day = 0; day < 5; day++) {
                        itemsToInsert.add(new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Employee__c = ts.Employee__c, Date__c = ts.Start_Date__c.addDays(day), Type__c = 'Attendance', Project__c = projBillable, Activity__c = 'Development-Coding', Duration__c = 8, Description__c = 'Demo Data - Standard Billable work'));
                    }
                }
            }
            if (!itemsToInsert.isEmpty()) insert itemsToInsert;
            return 'Success';
        } catch (Exception e) {
            System.debug('CRITICAL_DEMO_DATA_ERROR: ' + e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    global static String createSubEmployees(String parentEmployeeId) {
        try {
            Employee__c parentEmp = [SELECT Id, Manager__c, User__c, Last_Name__c FROM Employee__c WHERE Id = :parentEmployeeId WITH SECURITY_ENFORCED LIMIT 1];
            
            String numStr = '';
            if (parentEmp.Last_Name__c != null && parentEmp.Last_Name__c.toLowerCase().startsWith('employee ')) {
                numStr = parentEmp.Last_Name__c.toLowerCase().replace('employee ', '').trim();
            } else {
                numStr = '1';
            }
            
            Employee__c child1 = new Employee__c(
                First_Name__c = 'Test', 
                Last_Name__c = 'Child Employee ' + numStr + 'A', 
                Email__c = UserInfo.getUserEmail(), 
                Manager__c = parentEmp.User__c, 
                Employment_Type__c = 'Full Time', 
                Active__c = true, 
                Accrual_Start_Date__c = System.today().addMonths(-1), 
                Accrual_Divisor__c = 8, 
                Extra_Accrued_Hours__c = 30
            );
            Employee__c child2 = new Employee__c(
                First_Name__c = 'Test', 
                Last_Name__c = 'Child Employee ' + numStr + 'B', 
                Email__c = UserInfo.getUserEmail(), 
                Manager__c = parentEmp.User__c, 
                Employment_Type__c = 'Full Time', 
                Active__c = true, 
                Accrual_Start_Date__c = System.today().addMonths(-1), 
                Accrual_Divisor__c = 8, 
                Extra_Accrued_Hours__c = 30
            );
            
            insert new List<Employee__c>{child1, child2};
            return 'Success';
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    global static String createCurrentUserEmployee() {
        try {
            Id currentUserId = UserInfo.getUserId();
            User currentUser = [SELECT Id, FirstName, LastName, Email, ManagerId FROM User WHERE Id = :currentUserId WITH SECURITY_ENFORCED LIMIT 1];
            Id managerUserId = currentUser.ManagerId;
            if (managerUserId == null) {
                AuraHandledException e = new AuraHandledException('Please assign a manager in your User record before creating an employee.');
                e.setMessage('Please assign a manager in your User record before creating an employee.');
                throw e;
            }
            Integer nextNumber = 1;
            for (Employee__c e : [SELECT Last_Name__c FROM Employee__c WHERE First_Name__c = 'test' AND Last_Name__c LIKE 'employee %' WITH SECURITY_ENFORCED]) {
                String lName = e.Last_Name__c;
                String numStr = lName.replace('employee ', '').trim();
                if (numStr.isNumeric()) {
                    Integer num = Integer.valueOf(numStr);
                    if (num >= nextNumber) {
                        nextNumber = num + 1;
                    }
                }
            }
            Employee__c emp = new Employee__c(
                First_Name__c = 'test', 
                Last_Name__c = 'employee ' + nextNumber, 
                Email__c = currentUser.Email, 
                Manager__c = managerUserId, 
                Employment_Type__c = 'Full Time', 
                Active__c = true, 
                Accrual_Start_Date__c = System.today().addMonths(-1), 
                Accrual_Divisor__c = 8, 
                Extra_Accrued_Hours__c = 30
            );
            insert emp;
            return 'Success';
        } catch (Exception e) {
            System.debug('CRITICAL_DEMO_DATA_ERROR: ' + e.getMessage());
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled
    global static DemoDataWrapper getDemoRecords() {
        DemoDataWrapper wrapper = new DemoDataWrapper();
        wrapper.employees = new List<DemoRecordDetail>();
        wrapper.projects = new List<DemoRecordDetail>();
        wrapper.projectEmployees = new List<DemoRecordDetail>();
        wrapper.timesheets = new List<TimesheetDetail>();

        Id currentUserId = UserInfo.getUserId();
        
        List<Employee__c> emps = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Accrual_Start_Date__c, Accrual_Divisor__c 
            FROM Employee__c 
            WHERE ((Last_Name__c IN ('T.', 'E1', 'E2') OR Last_Name__c LIKE 'Child Employee%' OR Last_Name__c LIKE 'employee %') AND CreatedById = :currentUserId)
            WITH SECURITY_ENFORCED 
            ORDER BY CreatedDate ASC
        ];
        
        if (emps.isEmpty()) return wrapper;

        Boolean childExists = false;
        for (Employee__c e : emps) {
            if (e.Last_Name__c != null && e.Last_Name__c.contains('Child Employee')) {
                childExists = true;
                break;
            }
        }

        Map<Id, String> empNameMap = new Map<Id, String>();
        Integer empStep = 1;
        for(Employee__c emp : emps) {
            String fName = emp.First_Name__c != null ? emp.First_Name__c + ' ' : '';
            String lName = emp.Last_Name__c != null ? emp.Last_Name__c : '';
            empNameMap.put(emp.Id, fName + lName);
            DemoRecordDetail empDetail = new DemoRecordDetail();
            empDetail.stepNumber = empStep++;
            empDetail.stepTitle = fName + lName;
            empDetail.recordId = emp.Id;
            empDetail.recordName = emp.Name;
            empDetail.objectType = 'Employee__c';
            empDetail.objectLabel = 'Employee';
            empDetail.recordUrl = '/lightning/r/Employee__c/' + emp.Id + '/view';
            empDetail.summary = 'Accrual Start Date: 1 Month Ago | Accrual Divisor: ' + emp.Accrual_Divisor__c;
            empDetail.details = 'Configures the employee profile.';
            empDetail.whatItDoes = 'Tracks timesheet absence accruals and links memberships.';
            empDetail.isTestEmployee1 = (fName + lName).toLowerCase().contains('test employee');
            empDetail.hasChildEmployees = childExists;
            wrapper.employees.add(empDetail);
        }

        Integer projStep = 1;
        for (Project__c proj : [SELECT Id, Name, Active__c, Billable__c FROM Project__c WHERE Name LIKE 'Test Project%' AND CreatedById = :currentUserId WITH SECURITY_ENFORCED ORDER BY Name]) {
            DemoRecordDetail projDetail = new DemoRecordDetail();
            projDetail.stepNumber = projStep++;
            projDetail.stepTitle = proj.Name;
            projDetail.recordId = proj.Id;
            projDetail.recordName = proj.Name;
            projDetail.objectType = 'Project__c';
            projDetail.objectLabel = 'Project';
            projDetail.recordUrl = '/lightning/r/Project__c/' + proj.Id + '/view';
            projDetail.summary = 'Status: ' + (proj.Active__c ? 'Active' : 'Inactive') + ' | Billable: ' + proj.Billable__c;
            projDetail.details = 'Sample project record.';
            projDetail.whatItDoes = 'Enables logging hours against this project.';
            wrapper.projects.add(projDetail);
        }

        Integer peStep = 1;
        List<Project_Employee__c> pes = [SELECT Id, Name, Project__r.Name, Employee__c FROM Project_Employee__c WHERE Employee__c IN :emps AND Project__r.Name LIKE 'Test Project%' WITH SECURITY_ENFORCED];
        for(Project_Employee__c pe : pes) {
            DemoRecordDetail peDetail = new DemoRecordDetail();
            peDetail.stepNumber = peStep++;
            peDetail.stepTitle = pe.Project__r.Name + ' for ' + empNameMap.get(pe.Employee__c);
            peDetail.recordId = pe.Id;
            peDetail.recordName = pe.Name;
            peDetail.objectType = 'Project_Employee__c';
            peDetail.objectLabel = 'Project Membership';
            peDetail.recordUrl = '/lightning/r/Project_Employee__c/' + pe.Id + '/view';
            peDetail.summary = 'Assigned project to employee.';
            peDetail.details = 'Junction record linking employee to project.';
            peDetail.whatItDoes = 'Grants the employee access to select this project.';
            wrapper.projectEmployees.add(peDetail);
        }

        Date today = Date.today();
        Integer modDays = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(today), 7);
        if (modDays < 0) modDays += 7;
        Date thisWeekMonday = today.addDays(-modDays);
        Date lastWeekMonday = thisWeekMonday.addDays(-7);
        Date lastLastWeekMonday = thisWeekMonday.addDays(-14);
        Date nextWeekMonday = thisWeekMonday.addDays(7);
        List<Date> demoDates = new List<Date>{lastLastWeekMonday, lastWeekMonday, thisWeekMonday, nextWeekMonday};

        Map<Id, List<TimesheetLineItemDetail>> tliMap = new Map<Id, List<TimesheetLineItemDetail>>();
        for(Timesheet_Line_Item__c tli : [SELECT Id, Date__c, Type__c, Project__r.Name, Duration__c, Description__c, Timesheet__c FROM Timesheet_Line_Item__c WHERE Employee__c IN :emps AND Timesheet__r.Start_Date__c IN :demoDates WITH SECURITY_ENFORCED]) {
            if(!tliMap.containsKey(tli.Timesheet__c)) {
                tliMap.put(tli.Timesheet__c, new List<TimesheetLineItemDetail>());
            }
            TimesheetLineItemDetail d = new TimesheetLineItemDetail();
            d.id = tli.Id;
            d.dateStr = String.valueOf(tli.Date__c);
            d.type = tli.Type__c;
            d.project = tli.Project__r != null ? tli.Project__r.Name : '';
            d.duration = tli.Duration__c;
            d.description = tli.Description__c;
            tliMap.get(tli.Timesheet__c).add(d);
        }

        for (Timesheet__c ts : [SELECT Id, Name, Start_Date__c, End_Date__c, Status__c, Total_Hours__c, Employee__c FROM Timesheet__c WHERE Employee__c IN :emps AND Start_Date__c IN :demoDates WITH SECURITY_ENFORCED ORDER BY Employee__c, Start_Date__c ASC]) {
            TimesheetDetail tsDetail = new TimesheetDetail();
            
            String periodName = 'Weekly Timesheet';
            if (ts.Start_Date__c == lastLastWeekMonday) periodName = 'Last Last Week Timesheet';
            else if (ts.Start_Date__c == lastWeekMonday) periodName = 'Last Week Timesheet';
            else if (ts.Start_Date__c == thisWeekMonday) periodName = 'Current Week Timesheet';
            else if (ts.Start_Date__c == nextWeekMonday) periodName = 'Next Week Timesheet';

            tsDetail.recordId = ts.Id;
            tsDetail.name = ts.Name;
            tsDetail.employeeName = empNameMap.get(ts.Employee__c);
            tsDetail.periodName = periodName;
            tsDetail.dateRange = String.valueOf(ts.Start_Date__c) + ' to ' + String.valueOf(ts.End_Date__c);
            tsDetail.status = ts.Status__c;
            tsDetail.totalHours = ts.Total_Hours__c != null ? ts.Total_Hours__c : 0;
            tsDetail.recordUrl = '/lightning/r/Timesheet__c/' + ts.Id + '/view';
            tsDetail.isOpen = false;
            tsDetail.lineItems = tliMap.containsKey(ts.Id) ? tliMap.get(ts.Id) : new List<TimesheetLineItemDetail>();
            
            wrapper.timesheets.add(tsDetail);
        }

        return wrapper;
    }

    @AuraEnabled
    global static String deleteTestRecords() {
        Id currentUserId = UserInfo.getUserId();
        try {
            List<Employee__c> emps = [
                SELECT Id 
                FROM Employee__c 
                WHERE ((Last_Name__c IN ('T.', 'E1', 'E2') OR Last_Name__c LIKE 'Child Employee%' OR Last_Name__c LIKE 'employee %') AND CreatedById = :currentUserId)
                WITH SECURITY_ENFORCED
            ];
            List<Timesheet__c> tsList = [
                SELECT Id 
                FROM Timesheet__c 
                WHERE Employee__c IN :emps 
                   OR (OwnerId = :currentUserId AND Employee__c = null)
            ];
            if (!tsList.isEmpty()) {
                List<Timesheet_Line_Item__c> tlis = [
                    SELECT Id 
                    FROM Timesheet_Line_Item__c 
                    WHERE Timesheet__c IN :tsList
                ];
                if (!tlis.isEmpty()) {
                    delete tlis;
                }
                delete tsList;
            }

            if (!emps.isEmpty()) {
                List<Project_Employee__c> peList = [
                    SELECT Id 
                    FROM Project_Employee__c 
                    WHERE Employee__c IN :emps
                ];
                if (!peList.isEmpty()) {
                    delete peList;
                }

                List<Project__c> demoProjects = [
                    SELECT Id 
                    FROM Project__c 
                    WHERE Name IN ('Demo Project - Billable', 'Demo Project - Non-Billable', 'Demo Project - Legacy') OR (Name LIKE 'Test Project%' AND CreatedById = :currentUserId)
                ];
                if (!demoProjects.isEmpty()) {
                    delete demoProjects;
                }

                delete emps;
            } else {
                List<Project__c> demoProjects = [
                    SELECT Id 
                    FROM Project__c 
                    WHERE Name IN ('Demo Project - Billable', 'Demo Project - Non-Billable', 'Demo Project - Legacy') OR (Name LIKE 'Test Project%' AND CreatedById = :currentUserId)
                ];
                if (!demoProjects.isEmpty()) {
                    delete demoProjects;
                }
            }
            return 'Success';
        } catch (Exception e) {
            System.debug('DELETE_TEST_DATA_ERROR: ' + e.getMessage() + '\n' + e.getStackTraceString());
            if (Test.isRunningTest()) {
                throw e;
            }
            throw new AuraHandledException(e.getMessage());
        }
    }
}
