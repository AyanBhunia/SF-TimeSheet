@isTest
private class EmployeeAccrualUpdaterTest {
    @isTest
    static void testAccrualUpdate() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        
        System.runAs(adminUser) {
            // Create Employee
            dbt__Employee__c emp = new dbt__Employee__c();
            emp.Name = 'Test Emp';
            emp.dbt__Employment_Type__c = 'Full Time';
            emp.dbt__Accrual_Start_Date__c = Date.today().addMonths(-1);
            
            // Use the field name as it appears in the main class logic
            try {
                emp.put('dbt__Accrual_Divisor__c', 9);
            } catch(Exception e) {
                emp.put('Accrual_Divisor__c', 9);
            }
            insert emp;
            
            // Create Project
            dbt__Project__c proj = new dbt__Project__c();
            proj.Name = 'Test Project';
            proj.dbt__Billable__c = 'Yes';
            proj.dbt__Active__c = true;
            proj.dbt__Start_Date__c = Date.today().addMonths(-1);
            proj.dbt__End_Date__c = Date.today().addMonths(1);
            insert proj;
            
            // Create Timesheet
            dbt__Timesheet__c ts = new dbt__Timesheet__c();
            ts.dbt__Employee__c = emp.Id;
            ts.dbt__Status__c = 'Approved';
            ts.dbt__Start_Date__c = Date.today();
            ts.dbt__End_Date__c = Date.today().addDays(6);
            insert ts;
            
            // Create Timesheet Line Item to generate hours which triggers Accrued_Hours__c calculation
            dbt__Timesheet_Line_Item__c li = new dbt__Timesheet_Line_Item__c();
            li.dbt__Timesheet__c = ts.Id;
            li.dbt__Date__c = Date.today();
            li.dbt__Project__c = proj.Id;
            li.dbt__Type__c = 'Attendance';
            li.dbt__Activity__c = 'Development-Coding';
            li.dbt__Duration__c = 18;
            li.dbt__Billable__c = 'Yes';
            insert li;
            
            // Refresh Timesheet to get calculated Accrued_Hours__c
            ts = [SELECT Id, Accrued_Hours__c FROM dbt__Timesheet__c WHERE Id = :ts.Id];
            
            Test.startTest();
            EmployeeAccrualUpdater.EmployeeAccrualUpdater();
            Test.stopTest();
            
            dbt__Employee__c res = [SELECT Total_Accrued_Hours__c FROM dbt__Employee__c WHERE Id = :emp.Id];
            
            // Assert that the Employee total matches the Timesheet accrued hours
            System.assertEquals(ts.Accrued_Hours__c, res.Total_Accrued_Hours__c, 'Employee Total should match Timesheet Accrued Hours');
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