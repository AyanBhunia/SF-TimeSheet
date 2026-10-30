@isTest
private class GetRangeOfTimesheetsLineItemsTest {

    @isTest
    static void testGetTimesheetsLineItems_success() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            User u = [SELECT Id, ProfileId FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE LIMIT 1];

            // Create Client Manager
            User manager = new User(
                FirstName = 'Manager',
                LastName = 'Test',
                Email = 'manager@test.com',
                Username = 'manager' + DateTime.now().getTime() + '@test.com',
                Alias = 'mngr',
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = u.ProfileId,
                LanguageLocaleKey = 'en_US'
            );
            insert manager;

            // Create Employee
            Employee__c employee = new Employee__c(
                Name = 'Range Test Employee',
                User__c = u.Id,
                Client_Manager__c = manager.Id,
                Client_Manager_email__c = manager.Email,
                Employment_Type__c = 'Full Time'
            );
            insert employee;

            // Create Project (required for validation rules)
            Project__c project = new Project__c(
                Name = 'Project Range',
                Active__c = true,
                Billable__c = 'No'
            );
            insert project;

            // Create Timesheet
            Date startDate = Date.today().addDays(-5);
            Date endDate = Date.today();

            Timesheet__c timesheet = new Timesheet__c(
                Employee__c = employee.Id,
                Start_Date__c = startDate,
                End_Date__c = endDate
            );
            insert timesheet;

            // Create valid Timesheet Line Items within a date range
            List<Timesheet_Line_Item__c> items = new List<Timesheet_Line_Item__c>();

            for (Integer i = 0; i < 3; i++) {
                items.add(new Timesheet_Line_Item__c(
                    Timesheet__c = timesheet.Id,
                    Employee__c = employee.Id,
                    Type__c = 'Attendance',
                    Date__c = startDate.addDays(i),
                    Duration__c = 8,
                    Project__c = project.Id,
                    Activity__c = 'Testing'
                ));
            }
            insert items;

            Test.startTest();
            List<AggregateResult> results = GetRangeOfTimesheetsLineItems.getTimesheetsLineItems(
                employee.Id, startDate, endDate
            );
            Test.stopTest();

            System.assertNotEquals(null, results, 'Results should not be null');
            System.assertEquals(3, results.size(), 'Should return 3 grouped attendance entries');
        }
    }

    @isTest
    static void testGetTimesheetsLineItems_nullEmployee() {
        Test.startTest();
        try {
            GetRangeOfTimesheetsLineItems.getTimesheetsLineItems(null, Date.today(), Date.today());
            System.assert(false, 'Expected exception not thrown for null employee ID');
        } catch (Exception e) {
            // System.assert(e.getMessage().contains('Employee ID cannot be null'));
        }
        Test.stopTest();
    }

    @isTest
    static void testGetTimesheetsLineItems_missingDates() {
        User u = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        Test.startTest();
        try {
            GetRangeOfTimesheetsLineItems.getTimesheetsLineItems(u.Id, null, null);
            System.assert(false, 'Expected exception not thrown for null dates');
        } catch (Exception e) {
            // System.assert(e.getMessage().contains('Start date and end date must be specified'));
        }
        Test.stopTest();
    }

    @isTest
    static void testGetTimesheetsLineItems_invalidRange() {
        User u = [SELECT Id FROM User WHERE Profile.Name = 'System Administrator' LIMIT 1];
        Date today = Date.today();
        Test.startTest();
        try {
            GetRangeOfTimesheetsLineItems.getTimesheetsLineItems(u.Id, today, today.addDays(-1));
            System.assert(false, 'Expected exception not thrown for invalid range');
        } catch (Exception e) {
            // System.assert(e.getMessage().contains('Start date cannot be after end date'));
        }
        Test.stopTest();
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