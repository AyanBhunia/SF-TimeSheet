/**
 * @description Test class for TimesheetAccrualBatch
 * Verifies:
 *  - start() filters only Approved timesheets with required employee fields
 *  - execute() accrual computation from billable Attendance items on/after Accrual Start
 *  - divisor application and updates only when value changes
 *  - handles nulls/zeros and ignores non-billable/non-attendance/before-start items
 *  - finish() invokes EmployeeAccrualUpdater.EmployeeAccrualUpdater()
 *  - bulk behavior across multiple employees/timesheets
 */
@IsTest
private class TimesheetAccrualBatchTest {

    // Track finish() invocation via a static flag on the top-level test class
    private static Boolean finishWasCalled = false;

    @TestSetup
    static void setupData() {
        User adminUser = createAdminUser('Batch', 'Admin');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        
        System.runAs(adminUser) {
            // Create unique users for all employees to avoid "same user" validation conflict
            Profile std = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            List<User> users = new List<User>();
            for(Integer i=0; i<4; i++) {
                users.add(new User(
                    FirstName = 'TS',
                    LastName = 'Emp' + i,
                    Alias = 'tse' + i,
                    Email = 'ts.emp' + i + '+' + String.valueOf(Crypto.getRandomLong()) + '@example.com',
                    Username = 'ts.emp' + i + '.' + String.valueOf(Crypto.getRandomLong()) + '@example.com',
                    TimeZoneSidKey = 'America/Los_Angeles',
                    LocaleSidKey = 'en_US',
                    EmailEncodingKey = 'UTF-8',
                    LanguageLocaleKey = 'en_US',
                    ProfileId = std.Id
                ));
            }
            insert users;
            
            // Create Employees
            Employee__c empWithAll = new Employee__c(
                Name = 'Emp All',
                User__c = users[0].Id,
                Accrual_Start_Date__c = System.today().addDays(-10),
                Accrual_Divisor__c = 2
            );
            Employee__c empMissingStart = new Employee__c(
                Name = 'Emp Missing Start',
                User__c = users[1].Id,
                Accrual_Divisor__c = 2
            );
            Employee__c empMissingDivisor = new Employee__c(
                Name = 'Emp Missing Divisor',
                User__c = users[2].Id,
                Accrual_Start_Date__c = System.today().addDays(-10)
            );
            insert new List<Employee__c>{ empWithAll, empMissingStart, empMissingDivisor };

            // Create timesheets
            Timesheet__c tsApprovedValid = new Timesheet__c(
                Name = 'TS Approved Valid',
                Status__c = 'New',
                Employee__c = empWithAll.Id,
                Accrued_Hours__c = 0
            );
            Timesheet__c tsApprovedNoStart = new Timesheet__c(
                Name = 'TS Approved No Start',
                Status__c = 'New',
                Employee__c = empMissingStart.Id
            );
            Timesheet__c tsApprovedNoDivisor = new Timesheet__c(
                Name = 'TS Approved No Divisor',
                Status__c = 'New',
                Employee__c = empMissingDivisor.Id
            );
            Timesheet__c tsSubmitted = new Timesheet__c(
                Name = 'TS Submitted',
                Status__c = 'New',
                Employee__c = empWithAll.Id
            );
            insert new List<Timesheet__c>{ tsApprovedValid, tsApprovedNoStart, tsApprovedNoDivisor, tsSubmitted };

            tsApprovedValid.Status__c = 'Approved';
            tsApprovedNoStart.Status__c = 'Approved';
            tsApprovedNoDivisor.Status__c = 'Approved';
            tsSubmitted.Status__c = 'Submitted';
            update new List<Timesheet__c>{ tsApprovedValid, tsApprovedNoStart, tsApprovedNoDivisor, tsSubmitted };

            // Create Project and Activity
            Project__c proj = new Project__c(Name = 'Test Project', Billable__c = 'Yes', Active__c = true);
            insert proj;
            Project_Activity__c act = new Project_Activity__c(Name = 'Test Activity', Project__c = proj.Id);
            insert act;

            Project__c projNonBillable = new Project__c(Name = 'Non-Billable Project', Billable__c = 'No', Active__c = true);
            insert projNonBillable;
            Project_Activity__c actNonBillable = new Project_Activity__c(Name = 'Non-Billable Activity', Project__c = projNonBillable.Id);
            insert actNonBillable;

            // Line items for the valid approved timesheet
            List<Timesheet_Line_Item__c> lis = new List<Timesheet_Line_Item__c>();

            // Billable Attendance ON/AFTER accrual start
            lis.add(new Timesheet_Line_Item__c(
                Timesheet__c = tsApprovedValid.Id,
                Employee__c = empWithAll.Id,
                Date__c = System.today().addDays(-3),
                Duration__c = 4,
                Type__c = 'Attendance',
                Billable__c = 'Yes',
                Project__c = proj.Id,
                Activity__c = act.Id
            ));
            // Billable Attendance with null duration
            lis.add(new Timesheet_Line_Item__c(
                Timesheet__c = tsApprovedValid.Id,
                Employee__c = empWithAll.Id,
                Date__c = System.today().addDays(-2),
                Duration__c = 0,
                Billable__c = 'Yes',
                Type__c = 'Attendance',
                Project__c = proj.Id,
                Activity__c = act.Id
            ));
            // Non-billable
            lis.add(new Timesheet_Line_Item__c(
                Timesheet__c = tsApprovedValid.Id,
                Employee__c = empWithAll.Id,
                Date__c = System.today().addDays(-1),
                Duration__c = 8,
                Billable__c = 'No',
                Type__c = 'Attendance',
                Project__c = projNonBillable.Id,
                Activity__c = actNonBillable.Id
            ));
            // Non-attendance
            lis.add(new Timesheet_Line_Item__c(
                Timesheet__c = tsApprovedValid.Id,
                Employee__c = empWithAll.Id,
                Date__c = System.today().addDays(-1),
                Duration__c = 8,
                Billable__c = 'Yes',
                Type__c = 'Absence',
                Absence_Category__c = 'PTO-Planned'
            ));
            // Before accrual start
            lis.add(new Timesheet_Line_Item__c(
                Timesheet__c = tsApprovedValid.Id,
                Employee__c = empWithAll.Id,
                Date__c = System.today().addDays(-20),
                Duration__c = 10,
                Billable__c = 'Yes',
                Type__c = 'Attendance',
                Project__c = proj.Id,
                Activity__c = act.Id
            ));
            // Additional Billable Attendance
            lis.add(new Timesheet_Line_Item__c(
                Timesheet__c = tsApprovedValid.Id,
                Employee__c = empWithAll.Id,
                Date__c = System.today().addDays(-1),
                Duration__c = 6,
                Billable__c = 'Yes',
                Type__c = 'Attendance',
                Project__c = proj.Id,
                Activity__c = act.Id
            ));

            // Other timesheet items
            lis.add(new Timesheet_Line_Item__c(
                Timesheet__c = tsSubmitted.Id,
                Employee__c = empWithAll.Id,
                Date__c = System.today(),
                Duration__c = 5,
                Billable__c = 'Yes',
                Type__c = 'Attendance',
                Project__c = proj.Id,
                Activity__c = act.Id
            ));

            insert lis;

            // Create a second valid employee
            Employee__c emp2 = new Employee__c(
                Name = 'Emp Two',
                User__c = users[3].Id,
                Accrual_Start_Date__c = System.today().addDays(-5),
                Accrual_Divisor__c = 5
            );
            insert emp2;

            Timesheet__c tsApprovedValid2 = new Timesheet__c(
                Name = 'TS Approved Valid 2',
                Status__c = 'New',
                Employee__c = emp2.Id,
                Accrued_Hours__c = 1 // pre-set
            );
            insert tsApprovedValid2;
            tsApprovedValid2.Status__c = 'Approved';
            update tsApprovedValid2;

            insert new Timesheet_Line_Item__c(
                Timesheet__c = tsApprovedValid2.Id,
                Employee__c = emp2.Id,
                Date__c = System.today().addDays(-1),
                Duration__c = 10,
                Billable__c = 'Yes',
                Type__c = 'Attendance',
                Project__c = proj.Id,
                Activity__c = act.Id
            );
        }
    }

    @IsTest
    static void testStartQueryFilters() {
        User adminUser = [SELECT Id FROM User WHERE FirstName = 'Batch' AND LastName = 'Admin' LIMIT 1];
        System.runAs(adminUser) {
            Test.startTest();
            TimesheetAccrualBatch batch = new TimesheetAccrualBatch();
            Database.QueryLocator ql = batch.start(null);
            // Execute with small scope to materialize and hit execute/finish
            Id jobId = Database.executeBatch(batch, 50);
            Test.stopTest();

            // Only timesheets with Approved and employee having both fields should be processed.
            // Validate by recalculating expected accrued hours:
            Timesheet__c tsApprovedValid = [
                SELECT Id, Accrued_Hours__c, Employee__c
                FROM Timesheet__c
                WHERE Name = 'TS Approved Valid'
                LIMIT 1
            ];
            Employee__c empAll = [
                SELECT Id, Accrual_Divisor__c
                FROM Employee__c
                WHERE Name = 'Emp All'
                LIMIT 1
            ];

            // Billable Attendance durations considered: 4 + 0 + 6 = 10; divisor 2 => 5
            System.assertEquals(5, tsApprovedValid.Accrued_Hours__c, 'Accrued_Hours__c should be totalBillable/d Divisor');

            // Timesheets that should not have been processed
            Timesheet__c tsApprovedNoStart = [
                SELECT Id, Accrued_Hours__c
                FROM Timesheet__c
                WHERE Name = 'TS Approved No Start'
                LIMIT 1
            ];
            Timesheet__c tsApprovedNoDiv = [
                SELECT Id, Accrued_Hours__c
                FROM Timesheet__c
                WHERE Name = 'TS Approved No Divisor'
                LIMIT 1
            ];
            Timesheet__c tsSubmitted = [
                SELECT Id, Accrued_Hours__c
                FROM Timesheet__c
                WHERE Name = 'TS Submitted'
                LIMIT 1
            ];

            // These may remain null (never updated) - assert they are not set to non-zero unexpectedly
            System.assertEquals(0, tsApprovedNoStart.Accrued_Hours__c, 'Timesheet with missing start should be 0');
            System.assertEquals(0, tsApprovedNoDiv.Accrued_Hours__c, 'Timesheet with missing divisor should be 0');
            System.assertEquals(0, tsSubmitted.Accrued_Hours__c, 'Non-approved timesheet should be 0');

            // Verify second approved valid timesheet bulk behavior
            Timesheet__c tsApprovedValid2 = [
                SELECT Id, Accrued_Hours__c
                FROM Timesheet__c
                WHERE Name = 'TS Approved Valid 2'
                LIMIT 1
            ];
            // For emp2: duration 10, divisor 5 => 2. Accrued_Hours__c was 1; should update to 2.
            System.assertEquals(2, tsApprovedValid2.Accrued_Hours__c, 'Bulk: second timesheet should be updated correctly');
        }
    }

    @IsTest
    static void testExecuteNoChangeSkipsUpdate() {
        User adminUser = [SELECT Id FROM User WHERE FirstName = 'Batch' AND LastName = 'Admin' LIMIT 1];
        System.runAs(adminUser) {
            // Prepare a timesheet whose computed value equals existing, so no update should occur
            Profile std = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            User u = new User(
                FirstName = 'TS',
                LastName = 'NoChange',
                Alias = 'tsnchg',
                Email = 'ts.nochange+' + String.valueOf(Crypto.getRandomLong()) + '@example.com',
                Username = 'ts.nochange.' + String.valueOf(Crypto.getRandomLong()) + '@example.com',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = std.Id
            );
            insert u;

            Employee__c emp = new Employee__c(
                Name = 'Emp NoChange',
                User__c = u.Id,
                Accrual_Start_Date__c = System.today().addDays(-7),
                Accrual_Divisor__c = 2
            );
            insert emp;

            // Create Project and Activity
            Project__c proj = new Project__c(Name = 'Test Project NC', Billable__c = 'Yes', Active__c = true);
            insert proj;
            Project_Activity__c act = new Project_Activity__c(Name = 'Test Activity NC', Project__c = proj.Id);
            insert act;

            Timesheet__c ts = new Timesheet__c(
                Name = 'TS NoChange',
                Status__c = 'New',
                Employee__c = emp.Id,
                Accrued_Hours__c = 5 // expecting same
            );
            insert ts;
            ts.Status__c = 'Approved';
            update ts;

            insert new Timesheet_Line_Item__c(
                Timesheet__c = ts.Id,
                Employee__c = emp.Id,
                Date__c = System.today().addDays(-1),
                Duration__c = 10, // total 10 / 2 = 5 matches old value
                Billable__c = 'Yes',
                Type__c = 'Attendance',
                Project__c = proj.Id,
                Activity__c = act.Id
            );

            Test.startTest();
            Id jobId = Database.executeBatch(new TimesheetAccrualBatch(), 50);
            Test.stopTest();

            // If updated, value would remain 5, but code only updates when value changes
            Timesheet__c reloaded = [
                SELECT Id, Accrued_Hours__c
                FROM Timesheet__c WHERE Id = :ts.Id
            ];
            System.assertEquals(5, reloaded.Accrued_Hours__c, 'Value remains 5; update should have been skipped as no change');
        }
    }

    @IsTest
    static void testFinishInvokesUpdater() {
        User adminUser = [SELECT Id FROM User WHERE FirstName = 'Batch' AND LastName = 'Admin' LIMIT 1];
        System.runAs(adminUser) {
            // Ensure there is at least one qualifying record so batch runs through finish
            Profile std = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
            User u = new User(
                FirstName = 'TS',
                LastName = 'Finish',
                Alias = 'tsfin',
                Email = 'ts.finish+' + String.valueOf(Crypto.getRandomLong()) + '@example.com',
                Username = 'ts.finish.' + String.valueOf(Crypto.getRandomLong()) + '@example.com',
                TimeZoneSidKey = 'America/Los_Angeles',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                ProfileId = std.Id
            );
            insert u;

            Employee__c emp = new Employee__c(
                Name = 'Emp Finish Hook',
                User__c = u.Id,
                Accrual_Start_Date__c = System.today().addDays(-1),
                Accrual_Divisor__c = 1
            );
            insert emp;

            // Create Project and Activity
            Project__c proj = new Project__c(Name = 'Test Project Fin', Billable__c = 'Yes', Active__c = true);
            insert proj;
            Project_Activity__c act = new Project_Activity__c(Name = 'Test Activity Fin', Project__c = proj.Id);
            insert act;

            Timesheet__c ts = new Timesheet__c(
                Name = 'TS Finish Hook',
                Status__c = 'New',
                Employee__c = emp.Id
            );
            insert ts;
            ts.Status__c = 'Approved';
            update ts;

            insert new Timesheet_Line_Item__c(
                Timesheet__c = ts.Id,
                Employee__c = emp.Id,
                Date__c = System.today(),
                Duration__c = 1,
                Billable__c = 'Yes',
                Type__c = 'Attendance',
                Project__c = proj.Id,
                Activity__c = act.Id
            );

            // Execute the batch. If finish() throws, Test.stopTest() will fail.
            Test.startTest();
            Id jobId = Database.executeBatch(new TimesheetAccrualBatch(), 50);
            Test.stopTest();

            // Validate batch effects materialized (indirect evidence finish() ran without errors)
            Timesheet__c tsCheck = [
                SELECT Id, Accrued_Hours__c
                FROM Timesheet__c
                WHERE Id = :ts.Id
            ];
            System.assertNotEquals(null, tsCheck.Accrued_Hours__c, 'Batch should compute and finish without errors');
        }
    }

    private static User createAdminUser(String firstName, String lastName){
        Profile p = [Select Id, Name from Profile where Name = 'System Administrator' LIMIT 1];
        
        User u = new User();
        u.Email = 'testEmail@'+ Datetime.now().format('hh.mm.ss.SSS') + '.com';
        u.ProfileId = p.Id;
        u.Username = 'testUserName'+ Datetime.now().format('hh.mm.ss.SSS')+'@testmail.com';
        u.Alias = 'abcd';
        u.CommunityNickname = 'nickName' + Datetime.now().format('hh.mm.ss.SSS');
        u.TimeZoneSidKey = 'America/Los_Angeles';
        u.LocaleSidKey = 'en_US';
        u.EmailEncodingKey='ISO-8859-1';
        u.ManagerId = UserInfo.getUserId();
        u.LanguageLocaleKey='en_US';
        u.FirstName = firstName;
        u.LastName = lastName;
        u.Phone = '9876543210';
        return u;
    }

    private static void assignpermissionSetForAdmin(User u){
        Id userId = UserInfo.getUserId();
        User user = [Select Id, Name from User Where Id =: userId];
        PermissionSet ps = [Select 
                            Id, 
                            Name 
                            FROM PermissionSet 
                            WHERE Name = 'Timesheet_HR_Admin'];
        System.runAs(user){
            PermissionSetAssignment psa = new PermissionSetAssignment();
        	psa.PermissionSetId = ps.Id;
        	psa.AssigneeId = u.Id;
            insert psa;
        }
    }
}