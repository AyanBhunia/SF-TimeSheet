@isTest
public class TimesheetPartialSubmitTest {

    @testSetup
    static void setupTestData() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            // Create a test user
            User u = new User(
                Alias = 'testpart',
                LastName = 'PartialTest',
                Email = 'testpart@example.com',
                Username = 'testpart' + DateTime.now().getTime() + '@example.com',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'America/Los_Angeles'
            );
            insert u;

            // Create a test employee
            Employee__c emp = new Employee__c(
                Name = 'Test Employee',
                User__c = u.Id,
                Employment_Type__c = 'Full Time',
                Accrual_Start_Date__c = Date.today().addDays(-30),
                Accrual_Divisor__c = 2
            );
            insert emp;

            // Create a test project
            Project__c project = new Project__c(
                Name = 'Test Project', 
                Billable__c = 'Yes',
                Active__c = true,
                Start_Date__c = Date.today().addDays(-30),
                End_Date__c = Date.today().addDays(365)
            );
            insert project;

            // Assign employee to the project
            Project_Employee__c pe = new Project_Employee__c(
                Employee__c = emp.Id,
                Project__c = project.Id
            );
            insert pe;

            // Create a timesheet
            Timesheet__c ts = new Timesheet__c(
                Name = 'Week 1',
                Employee__c = emp.Id,
                Start_Date__c = Date.today().addDays(-7),
                End_Date__c = Date.today(),
                Status__c = 'New'
            );
            insert ts;

            // Create two timesheet line items (with only 5 hours each, testing bypass of 8/9 hour minimum rule)
            Timesheet_Line_Item__c line1 = new Timesheet_Line_Item__c(
                Timesheet__c = ts.Id,
                Date__c = Date.today().addDays(-2),
                Project__c = project.Id,
                Activity__c = 'Testing',
                Duration__c = 5,
                Description__c = 'Worked on feature A',
                Type__c = 'Attendance',
                Line_Item_Status__c = 'New'
            );
            Timesheet_Line_Item__c line2 = new Timesheet_Line_Item__c(
                Timesheet__c = ts.Id,
                Date__c = Date.today().addDays(-1),
                Project__c = project.Id,
                Activity__c = 'Testing',
                Duration__c = 5,
                Description__c = 'Worked on feature B',
                Type__c = 'Attendance',
                Line_Item_Status__c = 'New'
            );
            insert new List<Timesheet_Line_Item__c>{ line1, line2 };
        }
    }

    @isTest
    static void testIsPartialSubmitAllowed() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser) {
            Boolean allowed = WeeklyTimesheetController.isPartialSubmitAllowed();
            System.assertNotEquals(null, allowed, 'isPartialSubmitAllowed should return a Boolean value');
        }
    }

    @isTest
    static void testPartialSubmitWorkflow() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser) {
            Timesheet__c ts = [SELECT Id, Status__c FROM Timesheet__c LIMIT 1];
            List<Timesheet_Line_Item__c> lines = [SELECT Id, Line_Item_Status__c FROM Timesheet_Line_Item__c WHERE Timesheet__c = :ts.Id];
            System.assertEquals(2, lines.size(), 'Should have 2 line items');

            List<Id> lineIdsToSubmit = new List<Id>{ lines[0].Id };
            String res = WeeklyTimesheetController.submitPartialLineItems(String.valueOf(ts.Id), lineIdsToSubmit);
            System.assertEquals('Success', res, 'submitPartialLineItems should succeed');

            ts = [SELECT Id, Status__c FROM Timesheet__c WHERE Id = :ts.Id];
            System.assertEquals('Partial', ts.Status__c, 'Timesheet status should be Partial');

            Timesheet_Line_Item__c item1 = [SELECT Id, Line_Item_Status__c FROM Timesheet_Line_Item__c WHERE Id = :lines[0].Id];
            Timesheet_Line_Item__c item2 = [SELECT Id, Line_Item_Status__c FROM Timesheet_Line_Item__c WHERE Id = :lines[1].Id];
            System.assertEquals('Partial Submitted', item1.Line_Item_Status__c, 'Item 1 should be Partial Submitted');
            System.assertEquals('New', item2.Line_Item_Status__c, 'Item 2 should still be New');
        }
    }

    @isTest
    static void testPartialApprovalWorkflow() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser) {
            Timesheet__c ts = [SELECT Id FROM Timesheet__c LIMIT 1];
            List<Timesheet_Line_Item__c> lines = [SELECT Id FROM Timesheet_Line_Item__c WHERE Timesheet__c = :ts.Id];
            
            WeeklyTimesheetController.submitPartialLineItems(String.valueOf(ts.Id), new List<Id>{ lines[0].Id, lines[1].Id });

            // Approve one line item
            Test.startTest();
            TimesheetApprovalController.approveLineItems(new List<Id>{ lines[0].Id });
            Test.stopTest();

            Timesheet__c updatedTs = [SELECT Id, Status__c FROM Timesheet__c WHERE Id = :ts.Id];
            System.assertEquals('Partial', updatedTs.Status__c, 'Timesheet should be in Partial status');

            Timesheet_Line_Item__c approvedItem = [SELECT Id, Line_Item_Status__c FROM Timesheet_Line_Item__c WHERE Id = :lines[0].Id];
            System.assertEquals('Partial Approved', approvedItem.Line_Item_Status__c, 'Line item should be Partial Approved');

            // Verify accrual service recognises Partial Approved as eligible
            System.assertEquals(true, AccrualCalculationService.isAccrualEligible(updatedTs), 'Partial Approved should be accrual eligible');
        }
    }

    @isTest
    static void testPartialRejectionWorkflow() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser) {
            Timesheet__c ts = [SELECT Id FROM Timesheet__c LIMIT 1];
            List<Timesheet_Line_Item__c> lines = [SELECT Id FROM Timesheet_Line_Item__c WHERE Timesheet__c = :ts.Id];
            
            WeeklyTimesheetController.submitPartialLineItems(String.valueOf(ts.Id), new List<Id>{ lines[0].Id });

            Test.startTest();
            TimesheetApprovalController.rejectLineItemsWithNotes(new List<Id>{ lines[0].Id }, 'Description lacks detail');
            Test.stopTest();

            Timesheet_Line_Item__c rejectedItem = [SELECT Id, Line_Item_Status__c, Rejection_Notes__c FROM Timesheet_Line_Item__c WHERE Id = :lines[0].Id];
            System.assertEquals('New', rejectedItem.Line_Item_Status__c, 'Line item should be New');
            System.assertEquals('Description lacks detail', rejectedItem.Rejection_Notes__c, 'Rejection note should be saved');

            Timesheet__c updatedTs = [SELECT Id, Status__c FROM Timesheet__c WHERE Id = :ts.Id];
            System.assertEquals('New', updatedTs.Status__c, 'Timesheet status should revert to New');
        }
    }

    @isTest
    static void testSubmitTimesheet() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser) {
            Timesheet__c ts = [SELECT Id FROM Timesheet__c LIMIT 1];
            String res = WeeklyTimesheetController.submitTimesheet(ts.Id);
            System.assertEquals('Success', res, 'submitTimesheet should succeed');
            Timesheet__c updatedTs = [SELECT Id, Status__c FROM Timesheet__c WHERE Id = :ts.Id];
            System.assertEquals('Submitted', updatedTs.Status__c, 'Status should be Submitted');
        }
    }

    @isTest
    static void testRejectTimesheets() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser) {
            Timesheet__c ts = [SELECT Id FROM Timesheet__c LIMIT 1];
            WeeklyTimesheetController.submitTimesheet(ts.Id);
            TimesheetApprovalController.rejectTimesheets(new List<Id>{ ts.Id });
            Timesheet__c updatedTs = [SELECT Id, Status__c FROM Timesheet__c WHERE Id = :ts.Id];
            System.assertEquals('New', updatedTs.Status__c, 'Status should be New after rejection');
        }
    }

    @isTest
    static void testAdminOverrideCascade() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser) {
            Timesheet__c ts = [SELECT Id FROM Timesheet__c LIMIT 1];
            WeeklyTimesheetController.submitTimesheet(ts.Id);
            // Admin override: change Status from Submitted to New
            ts.Status__c = 'New';
            update ts;
            List<Timesheet_Line_Item__c> lines = [SELECT Id, Line_Item_Status__c FROM Timesheet_Line_Item__c WHERE Timesheet__c = :ts.Id];
            for (Timesheet_Line_Item__c li : lines) {
                System.assertEquals('New', li.Line_Item_Status__c, 'Line item should cascade to New');
            }
        }
    }

    @isTest
    static void testAccrualCalculationServiceEligibility() {
        System.assertEquals(true, AccrualCalculationService.isAccrualEligible(new Timesheet__c(Status__c = 'Partial')), 'Partial should be eligible');
        System.assertEquals(true, AccrualCalculationService.isAccrualEligible(new Timesheet__c(Status__c = 'Approved')), 'Approved should be eligible');
        System.assertEquals(false, AccrualCalculationService.isAccrualEligible(new Timesheet__c(Status__c = 'New')), 'New should not be eligible');
        System.assertEquals(false, AccrualCalculationService.isAccrualEligible(new Timesheet__c(Status__c = 'Submitted')), 'Submitted should not be eligible');
    }

    private static User createAdminUser(String firstName, String lastName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User();
        u.Email = 'testEmail@' + Datetime.now().format('hh.mm.ss.SSS') + '.com';
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
        PermissionSet ps = [Select Id, Name FROM PermissionSet WHERE Name = 'Timesheet_HR_Admin'];
        System.runAs(user){
            PermissionSetAssignment psa = new PermissionSetAssignment();
            psa.PermissionSetId = ps.Id;
            psa.AssigneeId = u.Id;
            insert psa;
        }
    }
}
