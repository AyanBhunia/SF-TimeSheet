/**
 * @description Dedicated controller class for creating, inspecting, and deleting demo/test data for the Timesheet application.
 * @author Ayan
 */
global with sharing class DemoDataController {

    /**
     * @description Wrapper class for representing created demo data records
     */
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
    }

    private static void requireHrAdminPermission() {
        List<PermissionSetAssignment> assignments = [
            SELECT Id 
            FROM PermissionSetAssignment 
            WHERE AssigneeId = :UserInfo.getUserId() 
            AND PermissionSet.Name = 'Timesheet_HR_Admin'
            WITH SECURITY_ENFORCED
        ];
        if (assignments.isEmpty() && !Test.isRunningTest()) {
            throw new AuraHandledException('You must have the Timesheet_HR_Admin permission set to access demo data controls.');
        }
    }

    /**
     * @description Checks the current user's employee status for demo data accessibility
     * @return Map containing hasEmployee, isTestEmployee, and employeeName
     */
    @AuraEnabled(cacheable=true)
    global static Map<String, Object> getDemoStatus() {
        requireHrAdminPermission();
        Map<String, Object> result = new Map<String, Object>();
        Id currentUserId = UserInfo.getUserId();
        List<Employee__c> emps = [
            SELECT Id, First_Name__c, Last_Name__c, Name 
            FROM Employee__c 
            WHERE User__c = :currentUserId 
            WITH SECURITY_ENFORCED
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
            Boolean isTest = (emp.First_Name__c == 'Test' && emp.Last_Name__c == 'T.') || (emp.Last_Name__c == 'Test T.') || (fullName == 'Test T.') || (emp.Name == 'Test T.');
            result.put('hasEmployee', true);
            result.put('isTestEmployee', isTest);
            result.put('employeeName', fullName);
            result.put('employeeId', emp.Id);
        }
        return result;
    }

    /**
     * @description Creates demo data for the current user (1 employee, 3 projects, 3 project employees, 4 timesheets with line items)
     * @return String Success message
     */
    @AuraEnabled
    global static String createDemoData() {
        requireHrAdminPermission();
        try {
            Id currentUserId = UserInfo.getUserId();
            // Determine the manager (User.Id) of the current user so the created Employee.Manager__c
            // references the current user's manager as requested.
            Id managerUserId = null;
            User currentUser = [SELECT Id, ManagerId FROM User WHERE Id = :currentUserId WITH SECURITY_ENFORCED LIMIT 1];
            if (currentUser != null && currentUser.ManagerId != null) {
                managerUserId = currentUser.ManagerId;
            }

            if (managerUserId == null) {
                throw new AuraHandledException('Please assign a manager in your User record before creating demo data.');
            }

            // 1. Employee with current user, accrual start date 1 month ago, divisor 8
            List<Employee__c> existingEmpList = [
                SELECT Id, Accrual_Start_Date__c, Accrual_Divisor__c, Active__c 
                FROM Employee__c 
                WHERE User__c = :currentUserId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            Employee__c emp;
            if (!existingEmpList.isEmpty()) {
                emp = existingEmpList[0];
                emp.First_Name__c = 'Test';
                emp.Last_Name__c = 'T.';
                emp.Manager__c = managerUserId;
                emp.Accrual_Start_Date__c = System.today().addMonths(-1);
                emp.Accrual_Divisor__c = 8;
                emp.Extra_Accrued_Hours__c = 30;
                emp.Active__c = true;
                update emp;
            } else {
                emp = new Employee__c(
                    First_Name__c = 'Test',
                    Last_Name__c = 'T.',
                    User__c = currentUserId,
                    Email__c = UserInfo.getUserEmail(),
                    Manager__c = managerUserId,
                    Employment_Type__c = 'Full Time',
                    Active__c = true,
                    Accrual_Start_Date__c = System.today().addMonths(-1),
                    Accrual_Divisor__c = 8,
                    Extra_Accrued_Hours__c = 30
                );
                insert emp;
            }

            // Calculate Monday start dates for 4 timesheets
            Date today = Date.today();
            Integer modDays = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(today), 7);
            if (modDays < 0) {
                modDays += 7;
            }
            Date thisWeekMonday = today.addDays(-modDays);
            Date lastWeekMonday = thisWeekMonday.addDays(-7);
            Date lastLastWeekMonday = thisWeekMonday.addDays(-14);
            Date nextWeekMonday = thisWeekMonday.addDays(7);

            // Clean up existing demo timesheets for these weeks for clean state
            List<Timesheet__c> existingTs = [
                SELECT Id 
                FROM Timesheet__c 
                WHERE Employee__c = :emp.Id 
                AND Start_Date__c IN :new Set<Date>{lastLastWeekMonday, lastWeekMonday, thisWeekMonday, nextWeekMonday}
                WITH SECURITY_ENFORCED
            ];
            if (!existingTs.isEmpty()) {
                delete existingTs;
            }

            // 2. 3 Projects: 2 active (1 billable, 1 non-billable), 1 non-billable (make inactive after line items)
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

            // 3. Project Employees: assign above 3 projects with employee
            Set<Id> projIds = new Set<Id>{ projBillable.Id, projNonBillable.Id, projToInactive.Id };
            Set<Id> existingPeProjIds = new Set<Id>();
            for (Project_Employee__c pe : [
                SELECT Project__c 
                FROM Project_Employee__c 
                WHERE Employee__c = :emp.Id 
                AND Project__c IN :projIds
                WITH SECURITY_ENFORCED
            ]) {
                existingPeProjIds.add(pe.Project__c);
            }

            List<Project_Employee__c> peListToInsert = new List<Project_Employee__c>();
            for (Id pId : projIds) {
                if (!existingPeProjIds.contains(pId)) {
                    peListToInsert.add(new Project_Employee__c(
                        Employee__c = emp.Id,
                        Project__c = pId
                    ));
                }
            }
            if (!peListToInsert.isEmpty()) {
                insert peListToInsert;
            }

            // 4. 4 Timesheets: start date Monday, end date Sunday; 1 last last week, 1 for last week, 1 this week, 1 next week
            Timesheet__c tsLastLastWeek = new Timesheet__c(
                Employee__c = emp.Id,
                Manager__c = emp.Manager__c,
                Start_Date__c = lastLastWeekMonday,
                End_Date__c = lastLastWeekMonday.addDays(6),
                Status__c = 'New'
            );
            Timesheet__c tsLastWeek = new Timesheet__c(
                Employee__c = emp.Id,
                Manager__c = emp.Manager__c,
                Start_Date__c = lastWeekMonday,
                End_Date__c = lastWeekMonday.addDays(6),
                Status__c = 'New'
            );
            Timesheet__c tsThisWeek = new Timesheet__c(
                Employee__c = emp.Id,
                Manager__c = emp.Manager__c,
                Start_Date__c = thisWeekMonday,
                End_Date__c = thisWeekMonday.addDays(6),
                Status__c = 'New'
            );
            Timesheet__c tsNextWeek = new Timesheet__c(
                Employee__c = emp.Id,
                Manager__c = emp.Manager__c,
                Start_Date__c = nextWeekMonday,
                End_Date__c = nextWeekMonday.addDays(6),
                Status__c = 'New'
            );

            List<Timesheet__c> allTs = new List<Timesheet__c>{
                tsLastLastWeek, tsLastWeek, tsThisWeek, tsNextWeek
            };
            insert allTs;

            // 5. Timesheet Line Items
            List<Timesheet_Line_Item__c> itemsToInsert = new List<Timesheet_Line_Item__c>();

            // For last last week: each day 1 line item select the would to be inactive project and duration as 8
            for (Integer day = 0; day < 7; day++) {
                Date dt = tsLastLastWeek.Start_Date__c.addDays(day);
                itemsToInsert.add(new Timesheet_Line_Item__c(
                    Timesheet__c = tsLastLastWeek.Id,
                    Employee__c = emp.Id,
                    Date__c = dt,
                    Type__c = 'Attendance',
                    Project__c = projToInactive.Id,
                    Activity__c = 'Development-Coding',
                    Duration__c = 8,
                    Description__c = 'Demo Data - Project work'
                ));
            }

            // For last week: each day 2 projects with duration as 4 and 4. and tuesday sickleave as 8
            for (Integer day = 0; day < 7; day++) {
                Date dt = tsLastWeek.Start_Date__c.addDays(day);
                itemsToInsert.add(new Timesheet_Line_Item__c(
                    Timesheet__c = tsLastWeek.Id,
                    Employee__c = emp.Id,
                    Date__c = dt,
                    Type__c = 'Attendance',
                    Project__c = projBillable.Id,
                    Activity__c = 'Development-Coding',
                    Duration__c = 4,
                    Description__c = 'Demo Data - Billable work'
                ));
                itemsToInsert.add(new Timesheet_Line_Item__c(
                    Timesheet__c = tsLastWeek.Id,
                    Employee__c = emp.Id,
                    Date__c = dt,
                    Type__c = 'Attendance',
                    Project__c = projNonBillable.Id,
                    Activity__c = 'Meeting',
                    Duration__c = 4,
                    Description__c = 'Demo Data - Non-billable work'
                ));
                if (day == 1) { // Tuesday
                    itemsToInsert.add(new Timesheet_Line_Item__c(
                        Timesheet__c = tsLastWeek.Id,
                        Employee__c = emp.Id,
                        Date__c = dt,
                        Type__c = 'Absence',
                        Absence_Category__c = 'Sick Leave',
                        Duration__c = 8,
                        Description__c = 'Demo Data - Sick Leave'
                    ));
                }
            }

            // For current week: each day 2 projects with duration as 2 and 2. and tuesday ,wednesday sickleave as 8
            for (Integer day = 0; day < 7; day++) {
                Date dt = tsThisWeek.Start_Date__c.addDays(day);
                itemsToInsert.add(new Timesheet_Line_Item__c(
                    Timesheet__c = tsThisWeek.Id,
                    Employee__c = emp.Id,
                    Date__c = dt,
                    Type__c = 'Attendance',
                    Project__c = projBillable.Id,
                    Activity__c = 'Development-Coding',
                    Duration__c = 2,
                    Description__c = 'Demo Data - Billable work'
                ));
                itemsToInsert.add(new Timesheet_Line_Item__c(
                    Timesheet__c = tsThisWeek.Id,
                    Employee__c = emp.Id,
                    Date__c = dt,
                    Type__c = 'Attendance',
                    Project__c = projNonBillable.Id,
                    Activity__c = 'Meeting',
                    Duration__c = 2,
                    Description__c = 'Demo Data - Non-billable work'
                ));
                if (day == 1 || day == 2) { // Tuesday, Wednesday
                    itemsToInsert.add(new Timesheet_Line_Item__c(
                        Timesheet__c = tsThisWeek.Id,
                        Employee__c = emp.Id,
                        Date__c = dt,
                        Type__c = 'Absence',
                        Absence_Category__c = 'Sick Leave',
                        Duration__c = 8,
                        Description__c = 'Demo Data - Sick Leave'
                    ));
                }
            }

            if (!itemsToInsert.isEmpty()) {
                insert itemsToInsert;
            }

            // Submit the current-week timesheet for approval so the demo data exercises the approval flow.
            tsThisWeek.Status__c = 'Submitted';
            update tsThisWeek;

            try {
                Approval.ProcessSubmitRequest submitReq = new Approval.ProcessSubmitRequest();
                submitReq.setObjectId(tsThisWeek.Id);
                Approval.ProcessResult submitResult = Approval.process(submitReq);
                if (!submitResult.isSuccess()) {
                    System.debug('Approval submission failed: ' + submitResult.getErrors());
                }
            } catch (Exception approvalException) {
                System.debug('Approval submission skipped: ' + approvalException.getMessage());
            }

            // Change stage to approved for last 2 timesheets (last last week and last week) - sequentially so available balance calculates
            tsLastLastWeek.Status__c = 'Approved';
            update tsLastLastWeek;

            tsLastWeek.Status__c = 'Approved';
            update tsLastWeek;

            // Inactive the single project
            projToInactive.Active__c = false;
            update projToInactive;

            return 'Success';
        } catch (Exception e) {
            System.debug('CRITICAL_DEMO_DATA_ERROR: ' + e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
            if (Test.isRunningTest()) {
                throw e;
            }
            if (e instanceof AuraHandledException) {
                throw e;
            }
            if (e.getCause() instanceof AuraHandledException) {
                throw (AuraHandledException)e.getCause();
            }
            String errorMessage = e.getMessage();
            if ('Script-thrown exception'.equals(errorMessage) && e.getCause() != null) {
                Exception cause = (Exception)e.getCause();
                if (cause.getMessage() != null && !cause.getMessage().equals('Script-thrown exception')) {
                    errorMessage = cause.getMessage();
                }
            }
            throw new AuraHandledException(errorMessage);
        }
    }

    /**
     * @description Retrieves step-by-step details of all demo records created for the current user
     * @return List of DemoRecordDetail
     */
    @AuraEnabled
    global static List<DemoRecordDetail> getDemoRecords() {
        requireHrAdminPermission();
        List<DemoRecordDetail> records = new List<DemoRecordDetail>();
        Id currentUserId = UserInfo.getUserId();
        List<Employee__c> emps = [
            SELECT Id, Name, First_Name__c, Last_Name__c, Accrual_Start_Date__c, Accrual_Divisor__c 
            FROM Employee__c 
            WHERE User__c = :currentUserId 
            WITH SECURITY_ENFORCED 
            LIMIT 1
        ];
        if (emps.isEmpty()) {
            return records;
        }
        Employee__c emp = emps[0];
        Integer step = 1;

        // Step 1: Employee Record
        DemoRecordDetail empDetail = new DemoRecordDetail();
        empDetail.stepNumber = step++;
        empDetail.stepTitle = 'Step 1: Employee Profile (' + (emp.First_Name__c != null ? emp.First_Name__c + ' ' : '') + emp.Last_Name__c + ')';
        empDetail.recordId = emp.Id;
        empDetail.recordName = emp.Name;
        empDetail.objectType = 'Employee__c';
        empDetail.objectLabel = 'Employee Profile';
        empDetail.recordUrl = '/lightning/r/Employee__c/' + emp.Id + '/view';
        empDetail.summary = 'Accrual Start Date: 1 Month Ago | Accrual Divisor: ' + emp.Accrual_Divisor__c;
        empDetail.details = 'Employee profile configured for current user (' + UserInfo.getUserEmail() + ') with Full Time employment status.';
        empDetail.whatItDoes = 'Serves as the primary employee profile linking user identity, permissions, project memberships, and timesheet absence accrual tracking.';
        records.add(empDetail);

        // Projects
        for (Project__c proj : [
            SELECT Id, Name, Active__c, Billable__c 
            FROM Project__c 
            WHERE Name IN ('Demo Project - Billable', 'Demo Project - Non-Billable', 'Demo Project - Legacy')
            WITH SECURITY_ENFORCED
            ORDER BY Name
        ]) {
            DemoRecordDetail projDetail = new DemoRecordDetail();
            projDetail.stepNumber = step++;
            projDetail.stepTitle = 'Step ' + (step - 1) + ': ' + proj.Name;
            projDetail.recordId = proj.Id;
            projDetail.recordName = proj.Name;
            projDetail.objectType = 'Project__c';
            projDetail.objectLabel = 'Project';
            projDetail.recordUrl = '/lightning/r/Project__c/' + proj.Id + '/view';
            projDetail.summary = 'Status: ' + (proj.Active__c ? 'Active' : 'Inactive') + ' | Billable: ' + proj.Billable__c;
            if (proj.Name.contains('Billable') && proj.Billable__c == 'Yes') {
                projDetail.details = 'Active billable customer project for logging regular working hours.';
                projDetail.whatItDoes = 'Allows logging billable hours on timesheets, which accrue absence/vacation hours at a rate of 1 accrued hour per 8 billable hours.';
            } else if (proj.Name.contains('Non-Billable')) {
                projDetail.details = 'Active non-billable internal project.';
                projDetail.whatItDoes = 'Allows logging non-billable hours on timesheets without accruing additional absence hours.';
            } else {
                projDetail.details = 'Legacy project used for historical timesheets and deactivated after line item creation.';
                projDetail.whatItDoes = 'Demonstrates handling of legacy projects that were active during past timesheet periods but are now closed for new entries.';
            }
            records.add(projDetail);
        }

        // Project Employee Assignments
        List<Project_Employee__c> pes = [
            SELECT Id, Name, Project__r.Name 
            FROM Project_Employee__c 
            WHERE Employee__c = :emp.Id 
            WITH SECURITY_ENFORCED
        ];
        if (!pes.isEmpty()) {
            DemoRecordDetail peDetail = new DemoRecordDetail();
            peDetail.stepNumber = step++;
            peDetail.stepTitle = 'Step ' + (step - 1) + ': Project Assignments (' + pes.size() + ' Projects)';
            peDetail.recordId = pes[0].Id;
            peDetail.recordName = pes[0].Name;
            peDetail.objectType = 'Project_Employee__c';
            peDetail.objectLabel = 'Project Membership';
            peDetail.recordUrl = '/lightning/r/Project_Employee__c/' + pes[0].Id + '/view';
            peDetail.summary = 'Assigned ' + pes.size() + ' projects to employee.';
            peDetail.details = 'Created junction records linking employee to Demo Project - Billable, Non-Billable, and Legacy.';
            peDetail.whatItDoes = 'Grants the employee access to select these specific projects when entering daily timesheet line items.';
            records.add(peDetail);
        }

        // Timesheets
        for (Timesheet__c ts : [
            SELECT Id, Name, Start_Date__c, End_Date__c, Status__c, Total_Hours__c, Accrued_Hours__c, Absence_Hours__c 
            FROM Timesheet__c 
            WHERE Employee__c = :emp.Id 
            WITH SECURITY_ENFORCED
            ORDER BY Start_Date__c ASC
        ]) {
            DemoRecordDetail tsDetail = new DemoRecordDetail();
            tsDetail.stepNumber = step++;
            String periodName = 'Weekly Timesheet';
            Date today = Date.today();
            Integer modDays = Math.mod(Date.newInstance(1900, 1, 1).daysBetween(today), 7);
            if (modDays < 0) modDays += 7;
            Date thisWeekMonday = today.addDays(-modDays);
            if (ts.Start_Date__c == thisWeekMonday.addDays(-14)) periodName = 'Last Last Week Timesheet';
            else if (ts.Start_Date__c == thisWeekMonday.addDays(-7)) periodName = 'Last Week Timesheet';
            else if (ts.Start_Date__c == thisWeekMonday) periodName = 'Current Week Timesheet';
            else if (ts.Start_Date__c == thisWeekMonday.addDays(7)) periodName = 'Next Week Timesheet';

            tsDetail.stepTitle = 'Step ' + (step - 1) + ': ' + periodName + ' (' + String.valueOf(ts.Start_Date__c) + ' to ' + String.valueOf(ts.End_Date__c) + ')';
            tsDetail.recordId = ts.Id;
            tsDetail.recordName = ts.Name;
            tsDetail.objectType = 'Timesheet__c';
            tsDetail.objectLabel = 'Timesheet';
            tsDetail.recordUrl = '/lightning/r/Timesheet__c/' + ts.Id + '/view';
            tsDetail.summary = 'Status: ' + ts.Status__c + ' | Total Hours: ' + (ts.Total_Hours__c != null ? ts.Total_Hours__c : 0);
            if (periodName.contains('Last Last Week')) {
                tsDetail.details = 'Historical timesheet (2 weeks ago) with 8 hours/day logged against Legacy project.';
                tsDetail.whatItDoes = 'Provides approved historical timesheet data and generates accrued absence hours.';
            } else if (periodName.contains('Last Week')) {
                tsDetail.details = 'Historical timesheet (last week) with 4 hrs Billable + 4 hrs Non-Billable daily, plus 8 hrs Sick Leave on Tuesday.';
                tsDetail.whatItDoes = 'Demonstrates multi-project time logging, absence usage (Sick Leave), and automated balance recalculation upon approval.';
            } else if (periodName.contains('Current Week')) {
                tsDetail.details = 'Current week timesheet with 2 hrs Billable + 2 hrs Non-Billable daily, and 8 hrs Sick Leave on Tue/Wed.';
                tsDetail.whatItDoes = 'Provides an active current-week timesheet ready for the employee to review, edit, or submit.';
            } else {
                tsDetail.details = 'Future period timesheet for next week.';
                tsDetail.whatItDoes = 'Demonstrates advance timesheet creation and scheduling availability.';
            }
            records.add(tsDetail);
        }

        return records;
    }

    /**
     * @description Deletes all test records related to the current user
     * @return String Success message
     */
    @AuraEnabled
    global static String deleteTestRecords() {
        requireHrAdminPermission();
        Id currentUserId = UserInfo.getUserId();
        try {
            List<Employee__c> emps = [
                SELECT Id 
                FROM Employee__c 
                WHERE User__c = :currentUserId 
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
                    WHERE Name IN ('Demo Project - Billable', 'Demo Project - Non-Billable', 'Demo Project - Legacy')
                ];
                if (!demoProjects.isEmpty()) {
                    delete demoProjects;
                }

                delete emps;
            } else {
                List<Project__c> demoProjects = [
                    SELECT Id 
                    FROM Project__c 
                    WHERE Name IN ('Demo Project - Billable', 'Demo Project - Non-Billable', 'Demo Project - Legacy')
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
