@isTest
public class GetDashboardProfileDetailsTest {

    @isTest
    static void testGetEmployeeDetailsReturnsCorrectData() {
                User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            // Create a test User
            User testUser = new User(
                Alias = 'testu',
                LastName = 'User',
                Email = 'testuser@example.com',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                Username = 'testuser_' + System.currentTimeMillis() + '@example.com'
            );
            insert testUser;

            // Create an Employee record linked to the user
            Employee__c emp = new Employee__c(
                Name = 'John Doe',
                User__c = testUser.Id,
                Email__c = 'john.doe@example.com',
                Hire_Date__c = Date.newInstance(2022, 1, 1),
                Last_Working_Date__c = Date.newInstance(2025, 12, 31),
                No_of_Vacations_Taken__c = 5,
                Phone_Number__c = '123-456-7890',
                Client_Manager_email__c = 'manager@example.com',
                Employment_Type__c = 'Full Time'
            );
            insert emp;

            // Create a related Client Manager contact and associate via lookup if applicable
            // Uncomment if Client_Manager__c is a lookup and required:
            // Contact manager = new Contact(LastName = 'Manager');
            // insert manager;
            // emp.Client_Manager__c = manager.Id;
            // update emp;

            // Create Project
            Project__c project = new Project__c(
                Name = 'Dashboard Project',
                Active__c = true,
                Billable__c = 'Yes'
            );
            insert project;

            // Create a Project Employee record
            Project_Employee__c projectEmp = new Project_Employee__c(
                Employee__c = emp.Id,
                Project__c = project.Id
            );
            insert projectEmp;

            // Create a Timesheet record for the current year
            Timesheet__c timesheet = new Timesheet__c(
                Employee__c = emp.Id,
                Start_Date__c = System.today()
            );
            insert timesheet;

            Test.startTest();

            Map<String, Object> result = GetDashboardProfileDetails.getEmployeeDetails(testUser.Id);

            Test.stopTest();

            // Basic assertions
            System.assert(result != null, 'Result should not be null');
            // System.assertEquals('John Doe', (String) result.get('Name'));
            System.assertEquals('john.doe@example.com', (String) result.get('Email'));
            System.assertEquals('Dashboard Project', (String) result.get('Projects'));
            System.assertEquals([SELECT Active__c FROM Employee__c WHERE User__c = :testUser.Id].Active__c, result.get('Active'), 'Active flag for demoDataPrompt');
            System.assertEquals(false, result.get('IsDemo'), 'Demo flag for demoDataPrompt');
        }
    }

    @isTest
    static void testGetEmployeeDetailsWithNoEmployeeRecord() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            User testUser = new User(
                Alias = 'nouser',
                LastName = 'User',
                Email = 'nouser@example.com',
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                TimeZoneSidKey = 'America/Los_Angeles',
                Username = 'nouser_' + System.currentTimeMillis() + '@example.com'
            );
            insert testUser;

            Test.startTest();
            Boolean exceptionThrown = false;

            try {
                GetDashboardProfileDetails.getEmployeeDetails(testUser.Id);
            } catch (AuraHandledException ex) {
                exceptionThrown = true;
            }

            Test.stopTest();

            System.assertEquals(true, exceptionThrown, 'An exception should be thrown if no employee record exists');
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