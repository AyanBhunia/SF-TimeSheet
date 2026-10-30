@isTest
private class GetDashboardManagerEmployeeDetailsTest {

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
    static void testGetManagerEmployeeDetails_success() {
        User u = createAdminUser('Admin', 'User');
        insert u;
        
        assignpermissionSetForAdmin(u);
        System.runAs(u){

            // Get a System Admin user
            User adminUser = [SELECT Id, ProfileId FROM User WHERE Profile.Name = 'System Administrator' AND IsActive = TRUE LIMIT 1];

            // Create a Manager User
            User managerUser = new User(
                FirstName = 'Manager',
                LastName = 'User',
                Email = 'manager.user@example.com',
                Username = 'manager.user.' + DateTime.now().getTime() + '@test.com',
                Alias = 'mgrusr',
                TimeZoneSidKey = 'America/New_York',
                LocaleSidKey = 'en_US',
                EmailEncodingKey = 'UTF-8',
                ProfileId = adminUser.ProfileId,
                LanguageLocaleKey = 'en_US'
            );
            insert managerUser;

            // Create an Employee assigned to the manager
            Employee__c employee = new Employee__c(
                Name = 'Managed Employee',
                User__c = adminUser.Id,
                Manager__c = managerUser.Id,
                Active__c = true,
                Employment_Type__c = 'Full Time'
            );
            insert employee;

            Test.startTest();
            List<Employee__c> results = GetDashboardManagerEmployeeDetails.getManagerEmployeeDetails(managerUser.Id);
            Test.stopTest();

            System.assertNotEquals(null, results, 'Result should not be null');
        }
    }

    @isTest
    static void testGetManagerEmployeeDetails_nullId() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
            System.runAs(adminUser){
            Test.startTest();
            try {
                GetDashboardManagerEmployeeDetails.getManagerEmployeeDetails(null);
                System.assert(false, 'Expected AuraHandledException for null managerId');
            } catch (AuraHandledException e) {
                System.assertNotEquals(null,e.getMessage(), 'Incorrect error message');
            }
            Test.stopTest();
        }
    }
}