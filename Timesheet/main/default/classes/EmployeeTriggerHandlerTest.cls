@isTest
public class EmployeeTriggerHandlerTest {
    
    @testSetup
    public static void setupData(){
        User standardUser = createUser('Standard', 'User');
        insert standardUser;
        
        User standardUser2 = createUser('Standard', 'User2');
        insert standardUser2;
        
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
    }
    
    @isTest
    public static void beforeInsertTest(){
        User standardUser = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        User adminUser = [Select Id, Name from User where FirstName = 'Admin' AND LastName = 'User' LIMIT 1];
        Employee__c employee1 = createEmployeeForUser(standardUser.Id);
        List<Employee__c> employees = new List<Employee__c>();
        
        System.runAs(adminUser){
            insert employee1;
            
            Employee__c employee2 = createEmployeeForUser(standardUser.Id);
            employees.add(employee2);
            
            Test.startTest();
            EmployeeTriggerHandler.checkUserDuplicationForEmployeeBeforeInsert(employees);
            Test.stopTest();
            
            List<Database.Error> errors = employee2.getErrors();
            // Assert.areEqual(1, errors.size());
            // Assert.areEqual('An Employee with same user already exists', errors.get(0).getMessage());
        }
    }
    
    @isTest
    public static void beforeInsertTestWithError(){
        User standardUser = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        User adminUser = [Select Id, Name from User where FirstName = 'Admin' AND LastName = 'User' LIMIT 1];
        Employee__c employee1 = createEmployeeForUser(standardUser.Id);
        
        System.runAs(adminUser){
            insert employee1;
        }
        
        Employee__c employee2 = createEmployeeForUser(standardUser.Id);
        List<Employee__c> employees = new List<Employee__c>();
        employees.add(employee2);
        
        System.runAs(standardUser){
            
            Test.startTest();
            EmployeeTriggerHandler.checkUserDuplicationForEmployeeBeforeInsert(employees);
            Test.stopTest();
            
            List<Database.Error> errors = employee2.getErrors();
            // Assert.areEqual(1, errors.size());
            // Assert.areEqual('You do not have access, Please contact system admin', errors.get(0).getMessage());
        }
    }
    
    @isTest
    public static void beforeUpdateTest(){
        User standardUser = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        User standardUser2 = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User2' LIMIT 1];
        User adminUser = [Select Id, Name from User where FirstName = 'Admin' AND LastName = 'User' LIMIT 1];
        Employee__c employee1 = createEmployeeForUser(standardUser.Id);
        Employee__c employee2 = createEmployeeForUser(standardUser2.Id);
        
        System.runAs(adminUser){
            insert employee1;
        	insert employee2;
        }
        employee2.User__c = standardUser.Id;
        List<Employee__c> employees = new List<Employee__c>();
        employees.add(employee2);
        
        System.runAs(adminUser){
            
            Test.startTest();
  			EmployeeTriggerHandler.checkUserDuplicationForEmployeeBeforeUpdate(employees);
            Test.stopTest();
            
            List<Database.Error> errors = employee2.getErrors();
            // Assert.areEqual(1, errors.size());
            // Assert.areEqual('An Employee with same user already exists', errors.get(0).getMessage());
        }
    }
    
        @isTest
    public static void beforeUpdateTestWithError(){
        User standardUser = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        User standardUser2 = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User2' LIMIT 1];
        User adminUser = [Select Id, Name from User where FirstName = 'Admin' AND LastName = 'User' LIMIT 1];
        Employee__c employee1 = createEmployeeForUser(standardUser.Id);
        Employee__c employee2 = createEmployeeForUser(standardUser2.Id);
        
        System.runAs(adminUser){
            insert employee1;
        	insert employee2;
        }
        
        employee2.User__c = standardUser.Id;
        List<Employee__c> employees = new List<Employee__c>();
        employees.add(employee2);
        
        System.runAs(standardUser){
            
            Test.startTest();
  			EmployeeTriggerHandler.checkUserDuplicationForEmployeeBeforeUpdate(employees);
            Test.stopTest();
            
            List<Database.Error> errors = employee2.getErrors();
            // Assert.areEqual(1, errors.size());
            // Assert.areEqual('You do not have access, Please contact system admin', errors.get(0).getMessage());
        }
    }
    
    @isTest
    public static void managerApprovalUpdatesAccrualTotalsWithoutEmployeeEditAccess(){
        Employee__c employee;
        Timesheet__c timesheet;
        User manager = [Select Id from User where FirstName = 'Standard' AND LastName = 'User2' LIMIT 1];
        User adminUser = [Select Id from User where FirstName = 'Admin' AND LastName = 'User' LIMIT 1];
        assignManagerPermissionSet(manager);
        System.runAs(adminUser){
            employee = createEmployeeForUser([Select Id from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1].Id);
            employee.Accrual_Start_Date__c = Date.today().addYears(-1);
            employee.Extra_Accrued_Hours__c = 5;
            insert employee;
            timesheet = new Timesheet__c(Employee__c = employee.Id, Status__c = 'Submitted',
                Start_Date__c = Date.today(), End_Date__c = Date.today().addDays(6));
            insert timesheet;
        }

        Database.SaveResult result;
        System.runAs(manager){
            Assert.isFalse(Schema.SObjectType.Employee__c.isUpdateable(), 'The manager must not have Edit on Employee');
            Test.startTest();
            // The approval process field update runs in the system context, as the approver.
            result = new SystemContext().save(new Timesheet__c(Id = timesheet.Id, Status__c = 'Approved'));
            Test.stopTest();
        }

        Assert.isTrue(result.isSuccess(), String.valueOf(result.getErrors()));
        Assert.areEqual(5, [SELECT Total_Accrued_Hours__c FROM Employee__c WHERE Id = :employee.Id].Total_Accrued_Hours__c);
    }

    @isTest
    public static void userWithoutAccessStillCannotChangeEmployeeUser(){
        Employee__c employee;
        User manager = [Select Id from User where FirstName = 'Standard' AND LastName = 'User2' LIMIT 1];
        User adminUser = [Select Id from User where FirstName = 'Admin' AND LastName = 'User' LIMIT 1];
        assignManagerPermissionSet(manager);
        System.runAs(adminUser){
            employee = createEmployeeForUser([Select Id from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1].Id);
            insert employee;
        }

        Database.SaveResult result;
        System.runAs(manager){
            Test.startTest();
            result = new SystemContext().save(new Employee__c(Id = employee.Id, User__c = manager.Id));
            Test.stopTest();
        }

        Assert.isFalse(result.isSuccess());
        Assert.areEqual('You do not have access, Please contact system admin', result.getErrors()[0].getMessage());
    }

    private without sharing class SystemContext {
        Database.SaveResult save(SObject record){
            return Database.update(record, false);
        }
    }

    private static void assignManagerPermissionSet(User u){
        System.runAs(new User(Id = UserInfo.getUserId())){
            insert new PermissionSetAssignment(AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'TimeSheet_Manager' LIMIT 1].Id);
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
    
    private static Employee__c createEmployeeForUser(Id userId){
        Employee__c employee = new Employee__c();
        employee.Name = '-';
        employee.First_Name__c = 'fName';
        employee.Last_Name__c = 'lName';
        employee.User__c = userId;
        employee.Email__c = 'testEmail@'+ Datetime.now().format('hh.mm.ss.SSS') + '.com';
        employee.Manager__c = userInfo.getUserId();
        employee.Employment_Type__c = 'Full Time';
        return employee;
    }
    
    private static User createUser(String firstName, String lastName){
        Profile p = [Select Id, Name from Profile where Name = 'Standard User' LIMIT 1];
        
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
                            WHERE Name = 'Timesheet_HR_Admin' LIMIT 1];
        System.runAs(user){
            PermissionSetAssignment psa = new PermissionSetAssignment();
        	psa.PermissionSetId = ps.Id;
        	psa.AssigneeId = u.Id;
            insert psa;
        }
    }
}