@isTest
private class GetTimesheetTest {

    @isTest
    static void testGetTimesheetRecords_success() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            // Create a test user (optional if running in system context)
            User u = [SELECT Id,ProfileId FROM User WHERE Profile.name = 'System Administrator' and IsActive =true Limit 1][0];

            // Create a Client Manager User
            User clientManager = new User(
                FirstName = 'John',
                LastName = 'Doe',
                Email = 'client.manager@example.com',
                Username = 'client.manager.' + DateTime.now().getTime() + '@test.com',
                Alias = 'clmngr',
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = u.ProfileId,
                LanguageLocaleKey = 'en_US'
            );
            insert clientManager;

            // Create Employee
            Employee__c employee = new Employee__c(
                Name = 'Test Employee',
                User__c = u.Id,
                Client_Manager__c = clientManager.Id,
                Client_Manager_email__c = clientManager.Email,
                Employment_Type__c = 'Full Time'
            );
            insert employee;

            // Create Timesheet
            Date startDate = Date.today().addDays(-7);
            Date endDate = Date.today();

            Timesheet__c timesheet = new Timesheet__c(
                Employee__c = employee.Id,
                Start_Date__c = startDate,
                End_Date__c = endDate
            );
            insert timesheet;

            // Create valid Timesheet Line Items (Attendance type)
            List<Timesheet_Line_Item__c> lineItems = new List<Timesheet_Line_Item__c>();

            for (Integer i = 0; i < 3; i++) {
                lineItems.add(new Timesheet_Line_Item__c(
                    Timesheet__c = timesheet.Id,
                    Employee__c = employee.Id,
                    Type__c = 'Attendance',
                    Date__c = startDate.addDays(i),
                    Project__c = null, // Assign a valid project Id if required
                    Activity__c = 'Development-Coding',
                    Duration__c = 8
                ));
            }

            // If Project__c is required via validation, insert and assign a dummy project
            Project__c project = new Project__c(Name = 'Test Project', Active__c = true,Billable__c='No');
            insert project;

            for (Timesheet_Line_Item__c item : lineItems) {
                item.Project__c = project.Id;
            }

            insert lineItems;

            Test.startTest();
            Timesheet__c result = GetTimesheet.getTimesheetRecords(timesheet.Id);
            Test.stopTest();

            System.assertNotEquals(null, result, 'Timesheet should be returned');
            System.assertEquals(timesheet.Id, result.Id, 'Returned timesheet should match inserted one');
            System.assert(result.Timesheets__r.size() == 3, 'Should return 3 timesheet line items');
        }
    }

    @isTest
    static void testGetTimesheetRecords_nullId() {
        Test.startTest();
        try {
            GetTimesheet.getTimesheetRecords(null);
            System.assert(false, 'Expected exception not thrown');
        } catch (Exception e) {
            // System.assert(e.getMessage(), 'Timesheet ID cannot be null');
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