@isTest
public class WeeklyTimesheetControllerTest {

    @testSetup
    static void setupTestData() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            // Create a test user
            User u = new User(
                Alias = 'testuser',
                LastName = 'Test',
                Email = 'test@example.com',
                Username = 'testuser' + DateTime.now().getTime() + '@example.com',
                ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
                EmailEncodingKey = 'UTF-8',
                LanguageLocaleKey = 'en_US',
                LocaleSidKey = 'en_US',
                TimeZoneSidKey = 'America/Los_Angeles'
            );
            insert u;

            // Create a test employee
            Employee__c emp = new Employee__c(
                Name = 'Test Employee',
                User__c = u.Id,
                Employment_Type__c = 'Full Time'
            );
            insert emp;

            // Create a test project
            Project__c project = new Project__c(Name = 'Test Project', Billable__c = 'Yes',Active__c = true);
            insert project;

            // Assign employee to the project
            Project_Employee__c pe = new Project_Employee__c(
                Employee__c = emp.Id,
                Project__c = project.Id
            );
            insert pe;

            // Create a timesheet
            Timesheet__c ts1 = new Timesheet__c(
                Name = 'Week 1',
                Employee__c = emp.Id,
                Start_Date__c = Date.today().addDays(-7),
                End_Date__c = Date.today()
            );
            insert ts1;

            // Create another timesheet for history
            Timesheet__c ts2 = new Timesheet__c(
                Name = 'Week 0',
                Employee__c = emp.Id,
                Start_Date__c = Date.today().addDays(-14),
                End_Date__c = Date.today().addDays(-8)
            );
            insert ts2;

            // Create timesheet line item
            Timesheet_Line_Item__c lineItem = new Timesheet_Line_Item__c(
                Timesheet__c = ts1.Id,
                Date__c = Date.today().addDays(-5),
                Project__c = project.Id,
                Activity__c = 'Testing',
                Duration__c = 8,
                Description__c = 'Worked on feature A',
                Type__c = 'Attendance'
            );
            insert lineItem;
        }
    }

    @isTest
    static void testGetTimesheet() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet__c ts = [SELECT Id FROM Timesheet__c LIMIT 1];
            Timesheet__c result = WeeklyTimesheetController.getTimesheet(ts.Id);
            System.assertNotEquals(null, result);
        }
    }

    @isTest
    static void testGetEmployeeTimesheetItems() {User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet__c ts = [SELECT Id, Employee__c FROM Timesheet__c LIMIT 1];
            List<Timesheet__c> results = WeeklyTimesheetController.getEmployeeTimesheetItems(
                String.valueOf(ts.Employee__c), String.valueOf(ts.Id));
            System.assert(results != null);
        }
    }

    @isTest
    static void testGetProjects() {User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet__c ts = [SELECT Employee__c FROM Timesheet__c LIMIT 1];
            List<Project_Employee__c> projects = WeeklyTimesheetController.getProjects(
                String.valueOf(ts.Employee__c));
            System.assert(projects != null);
        }
    }

    @isTest
    static void testGetWeeklyTimesheetItems() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet__c ts = [SELECT Id FROM Timesheet__c LIMIT 1];
            List<Timesheet_Line_Item__c> items = WeeklyTimesheetController.getWeeklyTimesheetItems(ts.Id);
            System.assert(items.size() > 0, 'Should return at least one line item');
        }
    }

    @isTest
    static void testUpsertLineItems() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            // Create a test project
            Project__c project = new Project__c(Name = 'Test Project', Billable__c = 'Yes',Active__c = true);
            insert project;
            
            Timesheet__c ts = [SELECT Id FROM Timesheet__c LIMIT 1];
            Timesheet_Line_Item__c newItem = new Timesheet_Line_Item__c(
                Timesheet__c = ts.Id,
                Date__c = Date.today(),
                Project__c = project.Id,
                Activity__c = 'Testing',
                Duration__c = 4,
                Type__c = 'Attendance'
            );

            List<Timesheet_Line_Item__c> items = new List<Timesheet_Line_Item__c>{ newItem };

            String result = WeeklyTimesheetController.upsertLineItems(items);
            System.assertEquals('Success', result);
        }
    }

    @isTest
    static void testUpsertLineItemsEmptyList() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            String result = WeeklyTimesheetController.upsertLineItems(new List<Timesheet_Line_Item__c>());
            System.assertEquals(true, result.contains('Error'));
        }
    }

    @isTest
    static void testDeleteTimesheetLineItems() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet_Line_Item__c item = [SELECT Id FROM Timesheet_Line_Item__c LIMIT 1];
            List<Timesheet_Line_Item__c> toDelete = new List<Timesheet_Line_Item__c>{ item };
            String result = WeeklyTimesheetController.deleteTimesheetLineItems(toDelete);
            System.assertEquals('Success', result);
        }
    }

    @isTest
    static void testDeleteSkipsRunningTimer() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;

        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet_Line_Item__c item = [SELECT Id FROM Timesheet_Line_Item__c LIMIT 1];
            item.Timer_Data__c = '{"startMs":1,"pausedMs":0}';
            update item;
            String result = WeeklyTimesheetController.deleteTimesheetLineItems(new List<Timesheet_Line_Item__c>{ item });
            System.assertEquals('Success', result);
            System.assertEquals(1, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Id = :item.Id], 'A row with a running timer must not be deleted');
        }
    }

    @isTest
    static void testDeleteTimesheetLineItemsEmptyList() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            String result = WeeklyTimesheetController.deleteTimesheetLineItems(new List<Timesheet_Line_Item__c>());
            System.assertEquals(true, result.contains('Error'));
        }
    }

    // ---------------------------------------------------------------- saveWeek (one transaction)

    private static Timesheet_Line_Item__c newGridRow(Timesheet_Line_Item__c base, String activity, Date day, Decimal hours) {
        return new Timesheet_Line_Item__c(
            Timesheet__c = base.Timesheet__c, Project__c = base.Project__c, Activity__c = activity,
            Date__c = day, Duration__c = hours, Type__c = 'Attendance'
        );
    }

    @isTest
    static void testSaveWeekDeletesAndUpsertsTogether() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet_Line_Item__c old = [SELECT Id, Timesheet__c, Project__c, Date__c, Duration__c FROM Timesheet_Line_Item__c LIMIT 1];
            WeeklyTimesheetController.SaveResult res = WeeklyTimesheetController.saveWeek(
                new List<Timesheet_Line_Item__c>{ newGridRow(old, 'Meeting', old.Date__c, 3) },
                new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = old.Id, Duration__c = old.Duration__c) }
            , null);
            System.assertEquals(true, res.success, 'saved: ' + res.message);
            System.assertEquals(0, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Id = :old.Id]);
            System.assertEquals(1, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Activity__c = 'Meeting']);
        }
    }

    @isTest
    static void testSaveWeekRollsBackDeletesWhenTheUpsertFails() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet_Line_Item__c old = [SELECT Id, Timesheet__c, Project__c, Date__c, Duration__c FROM Timesheet_Line_Item__c LIMIT 1];
            Timesheet_Line_Item__c bad = newGridRow(old, 'Meeting', old.Date__c, 3);
            bad.Type__c = 'Bogus'; // rejected by the picklist
            WeeklyTimesheetController.SaveResult res = WeeklyTimesheetController.saveWeek(
                new List<Timesheet_Line_Item__c>{ bad },
                new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = old.Id, Duration__c = old.Duration__c) }
            , null);
            System.assertEquals(false, res.success);
            System.assertEquals(1, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Id = :old.Id], 'The delete must be undone');
        }
    }

    @isTest
    static void testSaveWeekRefusesToDeleteARowChangedSinceItWasLoaded() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet_Line_Item__c old = [SELECT Id, Duration__c FROM Timesheet_Line_Item__c LIMIT 1];
            WeeklyTimesheetController.SaveResult res = WeeklyTimesheetController.saveWeek(
                null,
                new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = old.Id, Duration__c = 0) } // grid loaded it as 0h
            , null);
            System.assertEquals(false, res.success);
            System.assertEquals(1, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Id = :old.Id]);
        }
    }

    @isTest
    static void testSaveWeekKeepsARunningTimerRow() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet_Line_Item__c item = [SELECT Id, Duration__c FROM Timesheet_Line_Item__c LIMIT 1];
            item.Timer_Data__c = '{"startMs":1,"pausedMs":0}';
            update item;
            WeeklyTimesheetController.SaveResult res = WeeklyTimesheetController.saveWeek(
                null, new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = item.Id, Duration__c = item.Duration__c) }, null);
            System.assertEquals(true, res.success);
            System.assertEquals(1, res.keptTimerRows);
            System.assertEquals(1, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Id = :item.Id]);
        }
    }

    @isTest
    static void testSaveWeekRefusesANewRowOnARunningTimersDay() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet_Line_Item__c timerRow = [SELECT Id, Timesheet__c, Project__c, Activity__c, Date__c, Duration__c FROM Timesheet_Line_Item__c LIMIT 1];
            timerRow.Timer_Data__c = '{"startMs":1,"pausedMs":0}';
            update timerRow;
            Timesheet_Line_Item__c other = newGridRow(timerRow, 'Meeting', timerRow.Date__c.addDays(-1), 2);
            insert other;
            WeeklyTimesheetController.SaveResult res = WeeklyTimesheetController.saveWeek(
                new List<Timesheet_Line_Item__c>{ newGridRow(timerRow, timerRow.Activity__c, timerRow.Date__c, 4) },
                new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = other.Id, Duration__c = other.Duration__c) }
            , null);
            System.assertEquals(false, res.success);
            System.assert(res.message.contains('timer is running'), res.message);
            System.assertEquals(1, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Id = :other.Id], 'Nothing may be deleted');
        }
    }

    private static void assertClosedTimesheetRefusesChanges(String status) {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet_Line_Item__c row = [SELECT Id, Timesheet__c, Project__c, Date__c, Duration__c FROM Timesheet_Line_Item__c LIMIT 1];
            update new Timesheet__c(Id = row.Timesheet__c, Status__c = status);

            Timesheet_Line_Item__c edited = new Timesheet_Line_Item__c(Id = row.Id, Duration__c = 40);
            WeeklyTimesheetController.SaveResult editResult = WeeklyTimesheetController.saveWeek(
                new List<Timesheet_Line_Item__c>{ edited }, null, null);
            System.assertEquals(false, editResult.success, 'Editing a ' + status + ' timesheet is refused');
            System.assert(editResult.message.contains('already ' + status.toLowerCase()), editResult.message);

            WeeklyTimesheetController.SaveResult deleteResult = WeeklyTimesheetController.saveWeek(
                null, new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = row.Id, Duration__c = row.Duration__c) }, null);
            System.assertEquals(false, deleteResult.success, 'Deleting from a ' + status + ' timesheet is refused');

            System.assertEquals(row.Duration__c, [SELECT Duration__c FROM Timesheet_Line_Item__c WHERE Id = :row.Id].Duration__c);

            update new Timesheet__c(Id = row.Timesheet__c, Status__c = 'New');
            System.assertEquals(true, WeeklyTimesheetController.saveWeek(
                new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = row.Id, Timesheet__c = row.Timesheet__c, Project__c = row.Project__c,
                    Activity__c = 'Testing', Date__c = row.Date__c, Duration__c = 4, Type__c = 'Attendance') }, null, null).success, 'Allowed again once reopened');
        }
    }

    @isTest
    static void testSaveWeekRefusesASubmittedTimesheet() {
        assertClosedTimesheetRefusesChanges('Submitted');
    }

    @isTest
    static void testSaveWeekRefusesAnApprovedTimesheet() {
        assertClosedTimesheetRefusesChanges('Approved');
    }

    @isTest
    static void testSaveWeekRefusesAnEditOfARowChangedSinceItWasLoaded() {
        User adminUser = createAdminUser('Admin', 'User');
        insert adminUser;
        assignpermissionSetForAdmin(adminUser);
        System.runAs(adminUser){
            Timesheet_Line_Item__c row = [SELECT Id, Timesheet__c, Project__c, Date__c, Duration__c FROM Timesheet_Line_Item__c LIMIT 1];
            // The grid loaded the row with 2 h; the timer saved more hours meanwhile (now 8 h).
            Timesheet_Line_Item__c edit = new Timesheet_Line_Item__c(Id = row.Id, Timesheet__c = row.Timesheet__c, Project__c = row.Project__c,
                Activity__c = 'Testing', Date__c = row.Date__c, Duration__c = 3, Type__c = 'Attendance');
            WeeklyTimesheetController.SaveResult stale = WeeklyTimesheetController.saveWeek(
                new List<Timesheet_Line_Item__c>{ edit }, null, new Map<Id, Decimal>{ row.Id => 2 });
            System.assertEquals(false, stale.success);
            System.assert(stale.message.contains('changed elsewhere'), stale.message);
            System.assertEquals(row.Duration__c, [SELECT Duration__c FROM Timesheet_Line_Item__c WHERE Id = :row.Id].Duration__c, 'The newer hours stay');

            WeeklyTimesheetController.SaveResult current = WeeklyTimesheetController.saveWeek(
                new List<Timesheet_Line_Item__c>{ edit }, null, new Map<Id, Decimal>{ row.Id => row.Duration__c });
            System.assertEquals(true, current.success, 'Saved when the grid is up to date: ' + current.message);
            System.assertEquals(3, [SELECT Duration__c FROM Timesheet_Line_Item__c WHERE Id = :row.Id].Duration__c);
        }
    }

    // Runs as ordinary employees (Timesheet_User), so sharing and field access are really in play.
    @isTest
    static void testSaveWeekAsAnEmployeeOnlyTouchesTheirOwnRows() {
        Profile standard = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User one = new User(Alias = 'savone', LastName = 'SaveOne', Email = 'saveone@example.com',
            Username = 'saveone' + Datetime.now().getTime() + '@example.com', ProfileId = standard.Id,
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles');
        User two = new User(Alias = 'savtwo', LastName = 'SaveTwo', Email = 'savetwo@example.com',
            Username = 'savetwo' + Datetime.now().getTime() + '@example.com', ProfileId = standard.Id,
            EmailEncodingKey = 'UTF-8', LanguageLocaleKey = 'en_US', LocaleSidKey = 'en_US', TimeZoneSidKey = 'America/Los_Angeles');
        Timesheet_Line_Item__c ownRow;
        Timesheet_Line_Item__c otherRow;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ one, two };
            PermissionSet employeeSet = [SELECT Id FROM PermissionSet WHERE Name = 'Timesheet_User'];
            insert new List<PermissionSetAssignment>{
                new PermissionSetAssignment(PermissionSetId = employeeSet.Id, AssigneeId = one.Id),
                new PermissionSetAssignment(PermissionSetId = employeeSet.Id, AssigneeId = two.Id) };
            Employee__c empOne = new Employee__c(Name = '-', First_Name__c = 'Save', Last_Name__c = 'One', User__c = one.Id, Email__c = 'saveone.emp@example.com', Employment_Type__c = 'Full Time', Active__c = true);
            Employee__c empTwo = new Employee__c(Name = '-', First_Name__c = 'Save', Last_Name__c = 'Two', User__c = two.Id, Email__c = 'savetwo.emp@example.com', Employment_Type__c = 'Full Time', Active__c = true);
            insert new List<Employee__c>{ empOne, empTwo };
            Project__c project = new Project__c(Name = 'Save Project', Billable__c = 'Yes', Active__c = true);
            insert project;
            Timesheet__c sheetOne = new Timesheet__c(Name = 'Save One', Employee__c = empOne.Id, Start_Date__c = Date.today().addDays(-3), End_Date__c = Date.today().addDays(3), OwnerId = one.Id);
            Timesheet__c sheetTwo = new Timesheet__c(Name = 'Save Two', Employee__c = empTwo.Id, Start_Date__c = Date.today().addDays(-3), End_Date__c = Date.today().addDays(3), OwnerId = two.Id);
            insert new List<Timesheet__c>{ sheetOne, sheetTwo };
            ownRow = new Timesheet_Line_Item__c(Timesheet__c = sheetOne.Id, Project__c = project.Id, Activity__c = 'Testing', Date__c = Date.today(), Duration__c = 2, Type__c = 'Attendance');
            otherRow = new Timesheet_Line_Item__c(Timesheet__c = sheetTwo.Id, Project__c = project.Id, Activity__c = 'Testing', Date__c = Date.today(), Duration__c = 7.5, Type__c = 'Attendance');
            insert new List<Timesheet_Line_Item__c>{ ownRow, otherRow };
        }

        System.runAs(one) {
            // Another employee's row is not visible: the answer is the same for right and wrong hours, and nothing happens.
            WeeklyTimesheetController.SaveResult rightHours = WeeklyTimesheetController.saveWeek(
                null, new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = otherRow.Id, Duration__c = 7.5) }, null);
            WeeklyTimesheetController.SaveResult wrongHours = WeeklyTimesheetController.saveWeek(
                null, new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = otherRow.Id, Duration__c = 1) }, null);
            System.assertEquals(rightHours.success, wrongHours.success, 'No way to tell the hours of a row that is not yours');
            System.assertEquals(rightHours.message, wrongHours.message);

            // Editing another employee's row by sending only its Id (no timesheet) must not change it either.
            WeeklyTimesheetController.SaveResult tamper = WeeklyTimesheetController.saveWeek(
                new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = otherRow.Id, Duration__c = 0.5, Description__c = 'Tampered') }, null, null);
            System.assertEquals(false, tamper.success, 'Another employee\'s row cannot be edited: ' + tamper.message);

            WeeklyTimesheetController.SaveResult edit = WeeklyTimesheetController.saveWeek(
                new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = ownRow.Id, Timesheet__c = ownRow.Timesheet__c,
                    Project__c = ownRow.Project__c, Activity__c = 'Testing', Date__c = ownRow.Date__c, Duration__c = 5, Type__c = 'Attendance') },
                null, new Map<Id, Decimal>{ ownRow.Id => 2 });
            System.assertEquals(true, edit.success, 'Own row can be edited: ' + edit.message);

            WeeklyTimesheetController.SaveResult removal = WeeklyTimesheetController.saveWeek(
                null, new List<Timesheet_Line_Item__c>{ new Timesheet_Line_Item__c(Id = ownRow.Id, Duration__c = 5) }, null);
            System.assertEquals(true, removal.success, 'Own row can be removed: ' + removal.message);
        }
        System.assertEquals(0, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Id = :ownRow.Id], 'Own row is gone');
        System.assertEquals(7.5, [SELECT Duration__c FROM Timesheet_Line_Item__c WHERE Id = :otherRow.Id].Duration__c, 'The other employee\'s row is untouched');
    }

    @isTest
    static void testSaveWeekWithNothingToDoSucceeds() {
        System.assertEquals(true, WeeklyTimesheetController.saveWeek(null, null, null).success);
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