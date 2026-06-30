@isTest
public class TestDataFactory {
    
    public static User createStandardUser(String firstName, String lastName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u = new User();
        u.Email = 'testEmail@' + Datetime.now().format('hh.mm.ss.SSS') + '.com';
        u.ProfileId = p.Id;
        u.Username = 'testUserName' + Datetime.now().format('hh.mm.ss.SSS') + '@testmail.com';
        u.Alias = 'abcd';
        u.CommunityNickname = 'nickName' + Datetime.now().format('hh.mm.ss.SSS');
        u.TimeZoneSidKey = 'America/Los_Angeles';
        u.LocaleSidKey = 'en_US';
        u.EmailEncodingKey = 'ISO-8859-1';
        u.ManagerId = UserInfo.getUserId();
        u.LanguageLocaleKey = 'en_US';
        u.FirstName = firstName;
        u.LastName = lastName;
        u.Phone = '9876543210';
        return u;
    }

    public static User createAdminUser(String firstName, String lastName) {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
        User u = new User();
        u.Email = 'testEmail@' + Datetime.now().format('hh.mm.ss.SSS') + '.com';
        u.ProfileId = p.Id;
        u.Username = 'testUserName' + Datetime.now().format('hh.mm.ss.SSS') + '@testmail.com';
        u.Alias = 'abcd';
        u.CommunityNickname = 'nickName' + Datetime.now().format('hh.mm.ss.SSS');
        u.TimeZoneSidKey = 'America/Los_Angeles';
        u.LocaleSidKey = 'en_US';
        u.EmailEncodingKey = 'ISO-8859-1';
        u.ManagerId = UserInfo.getUserId();
        u.LanguageLocaleKey = 'en_US';
        u.FirstName = firstName;
        u.LastName = lastName;
        u.Phone = '9876543210';
        return u;
    }

    public static void assignPermissionSet(User u, String permissionSetName) {
        Id userId = UserInfo.getUserId();
        User adminUser = [SELECT Id FROM User WHERE Id = :userId];
        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
        System.runAs(adminUser) {
            PermissionSetAssignment psa = new PermissionSetAssignment();
            psa.PermissionSetId = ps.Id;
            psa.AssigneeId = u.Id;
            insert psa;
        }
    }

    public static Employee__c createEmployee(Id userId) {
        Employee__c employee = new Employee__c();
        employee.Name = 'Test Employee';
        employee.OwnerId = userId;
        employee.First_Name__c = 'Test';
        employee.Last_Name__c = 'Employee';
        employee.User__c = userId;
        employee.Email__c = 'testEmail@' + Datetime.now().format('hh.mm.ss.SSS') + '.com';
        employee.Manager__c = UserInfo.getUserId();
        employee.Employment_Type__c = 'Full Time';
        employee.Accrual_Start_Date__c = System.today().addDays(-30);
        employee.Accrual_Divisor__c = 2;
        return employee;
    }

    public static Timesheet__c createTimesheet(Id employeeId) {
        Timesheet__c timesheet = new Timesheet__c();
        timesheet.Start_Date__c = System.today();
        timesheet.End_Date__c = System.today() + 6;
        timesheet.Name = 'Timesheet for ' + timesheet.Start_Date__c + ' to ' + timesheet.End_Date__c;
        timesheet.Employee__c = employeeId;
        timesheet.Status__c = 'New';
        return timesheet;
    }

    public static Project__c createProject(String projectName, String isBillable) {
        Project__c project = new Project__c();
        project.Name = projectName;
        project.Start_Date__c = System.today();
        project.End_Date__c = System.today() + 365;
        project.Active__c = true;
        project.Billable__c = isBillable;
        return project;
    }

    public static Project_Activity__c createProjectActivity(Id projectId, String activityName) {
        Project_Activity__c act = new Project_Activity__c();
        act.Name = activityName;
        act.Project__c = projectId;
        return act;
    }

    public static Project_Employee__c createProjectEmployee(Id projectId, Id employeeId) {
        Project_Employee__c projectEmployee = new Project_Employee__c();
        projectEmployee.Project__c = projectId;
        projectEmployee.Employee__c = employeeId;
        return projectEmployee;
    }

    public static Timesheet_Line_Item__c createTimesheetLineItem(Id timesheetId, Id projectId, Id activityId) {
        Timesheet_Line_Item__c tli = new Timesheet_Line_Item__c();
        tli.Type__c = 'Attendance';
        tli.Timesheet__c = timesheetId;
        tli.Date__c = System.today();
        tli.Project__c = projectId;
        tli.Activity__c = activityId;
        tli.Duration__c = 5;
        tli.Description__c = 'Test Description';
        return tli;
    }
}
