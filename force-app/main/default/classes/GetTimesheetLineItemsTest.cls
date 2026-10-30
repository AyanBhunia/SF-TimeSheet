@isTest
private class GetTimesheetLineItemsTest {

    @isTest
    static void testGetTimesheetLineItemsRecords_success() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            // Get a System Administrator user to mimic your pattern
            User u = [SELECT Id, ProfileId FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE LIMIT 1];

            // Create a Client Manager
            User clientManager = new User(
                FirstName = 'Jane',
                LastName = 'Doe',
                Email = 'client.manager@example.com',
                Username = 'client.manager.' + DateTime.now().getTime() + '@test.com',
                Alias = 'jmana',
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = u.ProfileId,
                LanguageLocaleKey = 'en_US'
            );
            insert clientManager;

            // Create an Employee
            Employee__c employee = new Employee__c(
                Name = 'Test Employee',
                User__c = u.Id,
                Client_Manager__c = clientManager.Id,
                Client_Manager_email__c = clientManager.Email,
                Employment_Type__c = 'Full Time'
            );
            insert employee;

            // Create a Project (required for validation)
            Project__c project = new Project__c(
                Name = 'Test Project',
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

            // Create Timesheet Line Items (Type = Attendance)
            List<Timesheet_Line_Item__c> lineItems = new List<Timesheet_Line_Item__c>();
            for (Integer i = 0; i < 3; i++) {
                lineItems.add(new Timesheet_Line_Item__c(
                    Timesheet__c = timesheet.Id,
                    Employee__c = employee.Id,
                    Type__c = 'Attendance',
                    Date__c = startDate.addDays(i),
                    Project__c = project.Id,
                    Activity__c = 'Development-Coding',
                    Duration__c = 8
                ));
            }
            insert lineItems;

            Test.startTest();
            List<AggregateResult> results = GetTimesheetLineItems.getTimesheetLineItemsRecords(timesheet.Id);
            Test.stopTest();

            System.assertNotEquals(null, results, 'Results should not be null');
            System.assertEquals(3, results.size(), 'Should return 3 grouped dates');

            // for (AggregateResult ar : results) {
            //     Date lineDate = (Date) ar.get('Date__c');
            //     Decimal duration = (Decimal) ar.get('duration');
            //     System.assert(duration == 8, 'Each date should have 8 hours total');
            // }
        }
    }

    @isTest
    static void testGetTimesheetLineItemsRecords_nullId() {
        Test.startTest();
        try {
            GetTimesheetLineItems.getTimesheetLineItemsRecords(null);
            System.assert(false, 'Expected exception not thrown');
        } catch (Exception e) {
            // System.assert(e.getMessage().contains('Timesheet ID cannot be null'), 'Expected validation error message');
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