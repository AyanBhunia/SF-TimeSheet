@isTest
private class GetDashboardTimesheetLineItemsTest {

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

    @isTest
    static void testGetDashboardTimesheetLineItemsDetails_success() {
                User u = createAdminUser('Admin', 'User');
        insert u;
        
        assignpermissionSetForAdmin(u);
        System.runAs(u){
            // Get System Admin user
            User adminUser = [SELECT Id, ProfileId FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE LIMIT 1];

            // Create Client Manager
            User clientManager = new User(
                FirstName = 'Jane',
                LastName = 'Doe',
                Email = 'client.manager@example.com',
                Username = 'client.manager.' + DateTime.now().getTime() + '@test.com',
                Alias = 'cmdr',
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = adminUser.ProfileId,
                LanguageLocaleKey = 'en_US'
            );
            insert clientManager;

            // Create Employee and link to user
            Employee__c employee = new Employee__c(
                Name = 'Dashboard Employee',
                User__c = adminUser.Id,
                Client_Manager__c = clientManager.Id,
                Client_Manager_email__c = clientManager.Email,
                Employment_Type__c = 'Full Time'
            );
            insert employee;

            // Create Project
            Project__c project = new Project__c(
                Name = 'Dashboard Project',
                Active__c = true,
                Billable__c = 'Yes'
            );
            insert project;

            // Create Timesheet
            Date startDate = Date.today().addDays(-3);
            Date endDate = Date.today().addDays(3);

            Timesheet__c timesheet = new Timesheet__c(
                Employee__c = employee.Id,
                Start_Date__c = startDate,
                End_Date__c = endDate
            );
            insert timesheet;

            // Create Timesheet Line Items within date range
            List<Timesheet_Line_Item__c> items = new List<Timesheet_Line_Item__c>();
            for (Integer i = 0; i < 3; i++) {
                Date entryDate = startDate.addDays(i); // Date within Start & End

                items.add(new Timesheet_Line_Item__c(
                    Timesheet__c = timesheet.Id,
                    Employee__c = employee.Id,
                    Date__c = entryDate,
                    Duration__c = 8,
                    Type__c = 'Attendance',
                    Project__c = project.Id,
                    Activity__c = 'Development-Coding'
                ));
            }
            insert items;


            Test.startTest();
            List<AggregateResult> results = GetDashboardTimesheetLineItems.getDashboardTimesheetLineItemsDetails(adminUser.Id);
            Test.stopTest();

            System.assertNotEquals(null, results, 'Results should not be null');
            System.assert(results.size() > 0, 'Expected aggregated results for dashboard');
        }
    }

    @isTest
    static void testGetDashboardTimesheetLineItemsDetails_invalidUser() {
                User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
            System.runAs(adminUser){
            Test.startTest();
            try {
                // Use an invalid/null user ID
                GetDashboardTimesheetLineItems.getDashboardTimesheetLineItemsDetails(null);
                System.assert(false, 'Expected exception for null user ID not thrown');
            } catch (Exception e) {
                System.assertNotEquals(null, e.getMessage(), 'Error message should not be null');
            }
            Test.stopTest();
        }
    }
}