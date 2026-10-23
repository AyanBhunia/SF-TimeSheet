@isTest
public class TimesheetLineItemTriggerHandlerTest {
    
    @testSetup
    public static void setupData(){
        
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        User noAccessUser = createUser('NoAccess', 'User');
        insert noAccessUser;
        
        User standardUser = createUser('Standard', 'User');
        insert standardUser;
        
        assignpermissionSetForUser(standardUser);
        assignpermissionSetForAdmin(adminUser);
        Employee__c employee = createEmployeeForUser(standardUser.Id);
        
        System.runAs(adminUser){
            insert employee;
        }        
        Timesheet__c timesheet = createTimesheet(employee.Id, standardUser.Id);
        insert timesheet;
        
        Project__c project = createProjectAsBillable('Test Project','Yes');
        insert project;
    }
    
    @isTest
    public static void updateEmployeeBeforeInsert(){
        User standardUser = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Name, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id, Name from Project__c LIMIT 1];
        Timesheet_Line_Item__c timesheetLineItem = createTimesheetLineItem(timesheet.Id, project.Id);
        List<Timesheet_Line_Item__c> timesheetLineItems = new List<Timesheet_Line_Item__c>();
        timesheetLineItems.add(timesheetLineItem);
        
        System.runAs(standardUser){
            Test.startTest();
            TimesheetLineItemTriggerHandler.updateEmployeeId(timesheetLineItems);
            Test.stopTest();
            
            Assert.areEqual(timesheet.Employee__c, timesheetLineItem.Employee__c , 'Assertion failed for Timesheet Line Item before insert for updating employee Id');
        }
    }
    
    @isTest
    public static void updateEmployeeBeforeInsertWithException(){
        User noAccessUser = [Select Id, Name from User where FirstName = 'NoAccess' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Name, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id, Name from Project__c LIMIT 1];
        Timesheet_Line_Item__c timesheetLineItem = createTimesheetLineItem(timesheet.Id, project.Id);
        List<Timesheet_Line_Item__c> timesheetLineItems = new List<Timesheet_Line_Item__c>();
        timesheetLineItems.add(timesheetLineItem);
        
        System.runAs(noAccessUser){
            Test.startTest();
            TimesheetLineItemTriggerHandler.updateEmployeeId(timesheetLineItems);
            Test.stopTest();
            
            List<Database.Error> errors = timesheetLineItem.getErrors();
            Assert.areEqual(1, errors.size());
            Assert.areEqual('You do not have access, Please contact system admin', errors.get(0).getMessage());
        }
    }
    
    @isTest
    public static void updateEmployeeBillableField(){
        User standardUser = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Name, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id, Name, Billable__c from Project__c LIMIT 1];
        Timesheet_Line_Item__c timesheetLineItem = createTimesheetLineItem(timesheet.Id, project.Id);
        List<Timesheet_Line_Item__c> timesheetLineItems = new List<Timesheet_Line_Item__c>();
        timesheetLineItems.add(timesheetLineItem);
        
        System.runAs(standardUser){
            Test.startTest();
            TimesheetLineItemTriggerHandler.updateBillableField(timesheetLineItems);
            Test.stopTest();
            
            Assert.areEqual(project.Billable__c , timesheetLineItem.Billable__c , 'Assertion failed for Timesheet Line Item before insert for updating employee Id');
        }
        
        
    }
    
    @isTest
    public static void updateEmployeeBillableFieldWithException(){
        User noAccessUser = [Select Id, Name from User where FirstName = 'NoAccess' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Name, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id, Name, Billable__c from Project__c LIMIT 1];
        Timesheet_Line_Item__c timesheetLineItem = createTimesheetLineItem(timesheet.Id, project.Id);
        List<Timesheet_Line_Item__c> timesheetLineItems = new List<Timesheet_Line_Item__c>();
        timesheetLineItems.add(timesheetLineItem);
        
        System.runAs(noAccessUser){
            Test.startTest();
            TimesheetLineItemTriggerHandler.updateBillableField(timesheetLineItems);
            Test.stopTest();
            
            List<Database.Error> errors = timesheetLineItem.getErrors();
            Assert.areEqual(1, errors.size());
            Assert.areEqual('You do not have access, Please contact system admin', errors.get(0).getMessage());
        }
    }
    
    @isTest
    public static void checkForDuplicateTimesheetLineItemTest(){
        User standardUser = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Name, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id, Name, Billable__c from Project__c LIMIT 1];
        Timesheet_Line_Item__c timesheetLineItem = createTimesheetLineItem(timesheet.Id, project.Id);
        Timesheet_Line_Item__c timesheetLineItem2 = createTimesheetLineItem(timesheet.Id, project.Id);
        
        System.runAs(standardUser){
            insert timesheetLineItem;
        	List<Timesheet_Line_Item__c> timesheetLineItems = new List<Timesheet_Line_Item__c>();
            timesheetLineItems.add(timesheetLineItem2);
            
            Test.startTest();
            TimesheetLineItemTriggerHandler.checkForDuplicateTimesheetLineItem(timesheetLineItems);
            Test.stopTest();
            
            List<Database.Error> errors = timesheetLineItem2.getErrors();
            Assert.areEqual('LineItem with the same project and activity or same absense category already exists for the same date, please update the existing record', errors.get(0).getMessage());
        }
    }
    
    @isTest
    public static void checkForDuplicateTimesheetLineItemTestWithException(){
        User noAccessUser = [Select Id, Name from User where FirstName = 'NoAccess' AND LastName = 'User' LIMIT 1];
        User standardUser = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Name, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id, Name, Billable__c from Project__c LIMIT 1];
        Timesheet_Line_Item__c timesheetLineItem = createTimesheetLineItem(timesheet.Id, project.Id);
        Timesheet_Line_Item__c timesheetLineItem2 = createTimesheetLineItem(timesheet.Id, project.Id);
        
        System.runAs(standardUser){
            insert timesheetLineItem;
        }
        
        List<Timesheet_Line_Item__c> timesheetLineItems = new List<Timesheet_Line_Item__c>();
        timesheetLineItems.add(timesheetLineItem2);
        
        System.runAs(noAccessUser){
            Test.startTest();
            TimesheetLineItemTriggerHandler.checkForDuplicateTimesheetLineItem(timesheetLineItems);
            Test.stopTest();
            
            List<Database.Error> errors = timesheetLineItem2.getErrors();
            Assert.areEqual('You do not have access, Please contact system admin', errors.get(0).getMessage());
        }
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
    
    private static Timesheet__c createTimesheet(Id employeeId, Id userId){
        Timesheet__c timesheet = new Timesheet__c();
        timesheet.Start_Date__c = System.today();
        timesheet.End_Date__c = System.today()+6;
        timesheet.Name = 'Timesheet for ' + timesheet.Start_Date__c + ' to '+ timesheet.End_Date__c;
        timesheet.Employee__c = employeeId;
        timesheet.OwnerId = userId;
        return timesheet;
    }
    
    private static Project__c createProjectAsBillable(String projectName, String isBillable){
        Project__c project = new Project__c();
        project.Name = projectName;
        project.Start_Date__c = System.today();
        project.End_Date__c = System.today()+365;
        project.Active__c = true;
        project.Billable__c = isBillable;
        return project;
    }
    
    // The Duration_Limit_RTF flow must count a new row's own hours, not only the rows already saved.
    @isTest
    public static void insertingHoursOverTheDailyMaximumIsRefused(){
        User standardUser = [Select Id, Name from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Name, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id, Name from Project__c LIMIT 1];
        System.runAs(standardUser){
            Timesheet_Line_Item__c first = createTimesheetLineItem(timesheet.Id, project.Id);
            first.Duration__c = 20;
            insert first;
            Timesheet_Line_Item__c second = createTimesheetLineItem(timesheet.Id, project.Id);
            second.Activity__c = 'Meeting';
            second.Duration__c = 6;
            try {
                insert second;
                Assert.fail('26 hours on one day must be refused');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('exceeded 24 hours'), e.getMessage());
            }
            Timesheet_Line_Item__c fits = createTimesheetLineItem(timesheet.Id, project.Id);
            fits.Activity__c = 'Meeting';
            fits.Duration__c = 4;
            insert fits;
            Assert.areEqual(1, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Activity__c = 'Meeting'], '24 hours in total is fine');
        }
    }

    // Rows saved together cannot see each other in the before-save flow, so the trigger adds them up.
    private static Timesheet_Line_Item__c rowFor(Timesheet__c timesheet, Project__c project, String activity, Decimal hours){
        Timesheet_Line_Item__c row = createTimesheetLineItem(timesheet.Id, project.Id);
        row.Activity__c = activity;
        row.Duration__c = hours;
        return row;
    }

    @isTest
    public static void severalNewRowsOfOneDayOverTheMaximumAreRefusedTogether(){
        User standardUser = [Select Id from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id from Project__c LIMIT 1];
        System.runAs(standardUser){
            try {
                insert new List<Timesheet_Line_Item__c>{ rowFor(timesheet, project, 'Testing', 15), rowFor(timesheet, project, 'Meeting', 15) };
                Assert.fail('30 hours on one day must be refused');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('exceeded 24 hours'), e.getMessage());
            }
            Assert.areEqual(0, [SELECT COUNT() FROM Timesheet_Line_Item__c], 'Nothing is saved');
            insert new List<Timesheet_Line_Item__c>{ rowFor(timesheet, project, 'Testing', 10), rowFor(timesheet, project, 'Meeting', 10) };
            Assert.areEqual(2, [SELECT COUNT() FROM Timesheet_Line_Item__c], '20 hours are fine');
        }
    }

    @isTest
    public static void newRowsAreAddedToHoursAlreadySaved(){
        User standardUser = [Select Id from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id from Project__c LIMIT 1];
        System.runAs(standardUser){
            insert rowFor(timesheet, project, 'Testing', 15);
            try {
                insert new List<Timesheet_Line_Item__c>{ rowFor(timesheet, project, 'Meeting', 5), rowFor(timesheet, project, 'Other', 5) };
                Assert.fail('25 hours on one day must be refused');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('exceeded 24 hours'), e.getMessage());
            }
            insert new List<Timesheet_Line_Item__c>{ rowFor(timesheet, project, 'Meeting', 4), rowFor(timesheet, project, 'Other', 5) };
            Assert.areEqual(3, [SELECT COUNT() FROM Timesheet_Line_Item__c], '24 hours exactly is fine');
        }
    }

    @isTest
    public static void updatingTwoRowsOfOneDayTogetherIsChecked(){
        User standardUser = [Select Id from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id from Project__c LIMIT 1];
        System.runAs(standardUser){
            List<Timesheet_Line_Item__c> rows = new List<Timesheet_Line_Item__c>{ rowFor(timesheet, project, 'Testing', 5), rowFor(timesheet, project, 'Meeting', 5) };
            insert rows;
            rows[0].Duration__c = 15;
            rows[1].Duration__c = 15;
            try {
                update rows;
                Assert.fail('30 hours on one day must be refused');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('exceeded 24 hours'), e.getMessage());
            }
            Assert.areEqual(10, [SELECT SUM(Duration__c) s FROM Timesheet_Line_Item__c][0].get('s'), 'The old hours stay');
        }
    }

    @isTest
    public static void dayTotalCheckNeedsOneQueryForAWholeWeek(){
        User standardUser = [Select Id from User where FirstName = 'Standard' AND LastName = 'User' LIMIT 1];
        Timesheet__c timesheet = [Select Id, Employee__c from Timesheet__c LIMIT 1];
        Project__c project = [Select Id from Project__c LIMIT 1];
        List<Timesheet_Line_Item__c> rows = new List<Timesheet_Line_Item__c>();
        for(Integer day = -3; day <= 3; day++){
            for(String activity : new List<String>{ 'Testing', 'Meeting', 'Other' }){
                Timesheet_Line_Item__c row = rowFor(timesheet, project, activity, 2);
                row.Date__c = Date.today().addDays(day);
                row.Employee__c = timesheet.Employee__c;
                rows.add(row);
            }
        }
        System.runAs(standardUser){
            Integer before = Limits.getQueries();
            TimesheetLineItemTriggerHandler.checkDayTotals(rows);
            Assert.areEqual(1, Limits.getQueries() - before, 'One aggregate query for the whole batch');
            Integer flagged = 0;
            for(Timesheet_Line_Item__c row : rows){
                flagged += row.Hours_Limit_Exceeded__c == true ? 1 : 0;
            }
            Assert.areEqual(0, flagged, '6 hours a day is fine');
        }
    }

    private static Timesheet_Line_Item__c createTimesheetLineItem(Id timesheetId, Id projectId){
        Timesheet_Line_Item__c timesheetLineItem = new Timesheet_Line_Item__c();
        timesheetLineItem.Type__c = 'Attendance';
        timesheetLineItem.Timesheet__c = timesheetId;
        timesheetLineItem.Date__c = System.today();
        timesheetLineItem.Project__c = projectId;
        timesheetLineItem.Activity__c = 'other';
        timesheetLineItem.Duration__c = 5;
        timesheetLineItem.Description__c = 'Test Description';
        return timesheetLineItem;
    }
    
    private static void assignpermissionSetForUser(User u){
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