@isTest
private class GetEmployeeDetailsTest {

    @isTest
    static void testGetEmployee_success() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            // Fetch a System Admin user for context
            User u = [SELECT Id, ProfileId FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE LIMIT 1];

            // Create a Client Manager
            User clientManager = new User(
                FirstName = 'Jane',
                LastName = 'Doe',
                Email = 'client.manager@example.com',
                Username = 'client.manager.' + DateTime.now().getTime() + '@test.com',
                Alias = 'jdoe',
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

            // Create Project
            Project__c project = new Project__c(
                Name = 'Sample Project',
                Active__c = true,
                Billable__c = 'Yes'
            );
            insert project;

            // Create Project Assignment (Project_Employee__c)
            Project_Employee__c projectEmployee = new Project_Employee__c(
                Employee__c = employee.Id,
                Project__c = project.Id
            );
            insert projectEmployee;

            Test.startTest();
            Employee__c result = GetEmployeeDetails.getEmployee(employee.Id);
            Test.stopTest();

            System.assertNotEquals(null, result, 'Returned employee should not be null');
            System.assertEquals(employee.Id, result.Id, 'Returned employee ID should match');
            System.assertEquals(clientManager.Id, result.Client_Manager__c, 'Client Manager should match');
            System.assert(result.Project_Employees__r.size() > 0, 'Employee should have related project employee records');
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

    @isTest
    static void testGetEmployee_nullId() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Test.startTest();
            try {
                GetEmployeeDetails.getEmployee(null);
                System.assert(false, 'Expected exception was not thrown');
            } catch (Exception e) {
                // System.assert(e.getMessage().contains('Employee ID cannot be null'), 'Expected error message mismatch');
            }
            Test.stopTest();
        }
    }
}