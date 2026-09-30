/**
 * @description Tests for DemoDataController: every record the demo creates (with and without child employees),
 *              that it matches the blueprint the popup previews, how many queries each method uses, and that
 *              delete removes everything and nothing else.
 */
@IsTest
private class DemoDataControllerTest {

    private static final String HR_ADMIN_PERMISSION_SET = 'Timesheet_HR_Admin';

    @IsTest
    static void fullFlowWithChildEmployees() {
        User hrAdmin = createUser('hradm');
        System.runAs(hrAdmin) {
            runFullFlow(true);
            assertCreatedRecords(hrAdmin, true);
            assertDeletesEverything(true);
        }
    }

    @IsTest
    static void fullFlowWithoutChildEmployees() {
        User hrAdmin = createUser('hradm');
        System.runAs(hrAdmin) {
            runFullFlow(false);
            assertCreatedRecords(hrAdmin, false);
            assertDeletesEverything(false);
        }
    }

    @IsTest
    static void blueprintDescribesTheDemo() {
        User hrAdmin = createUser('hradm');
        System.runAs(hrAdmin) {
            DemoDataController.DemoState state = DemoDataController.getDemoData();
            Assert.areEqual(0, state.employees.size(), 'No demo data yet');
            Assert.areEqual(0, state.projects.size(), 'No demo projects yet');

            DemoDataController.Blueprint blueprint = state.blueprint;
            Assert.areEqual(3, blueprint.employees.size(), 'Demo Employee and two child employees');
            Assert.areEqual('Demo Employee', blueprint.employees[0].name, 'Demo Employee first');
            Assert.isFalse(blueprint.employees[0].isChild, 'Demo Employee is not a child');
            Assert.isNull(blueprint.employees[0].manager, 'Demo Employee has no manager');
            for (Integer i = 1; i < 3; i++) {
                Assert.isTrue(blueprint.employees[i].isChild, 'Child employee flagged');
                Assert.areEqual(UserInfo.getName(), blueprint.employees[i].manager, 'Child employees report to the user');
            }
            Assert.areEqual(3, blueprint.projects.size(), 'Three projects');
            Assert.areEqual(150, blueprint.hourlyRate, 'Hourly rate');
            Assert.areEqual(4, blueprint.weeks.size(), 'Four weeks');
            List<Integer> itemCounts = new List<Integer>();
            List<Integer> rounds = new List<Integer>();
            for (DemoDataController.WeekPlan week : blueprint.weeks) {
                itemCounts.add(week.lineItems.size());
                rounds.add(week.approvalRound);
                Assert.areEqual(week.startDate.addDays(6), week.endDate, 'Monday to Sunday');
            }
            Assert.areEqual(new List<Integer>{ 5, 9, 8, 0 }, itemCounts, 'Line items per week');
            Assert.areEqual(new List<Integer>{ 1, 2, 0, 0 }, rounds, 'Approval rounds per week');
            Assert.areEqual(0, Math.mod(Date.newInstance(1900, 1, 1).daysBetween(blueprint.weeks[0].startDate), 7), 'Weeks start on Monday');
        }
    }

    @IsTest
    static void weekPlanFollowsTheTimesheetsIntoLaterWeeks() {
        User hrAdmin = createUser('hradm');
        System.runAs(hrAdmin) {
            DemoDataController.createDemoEmployees(true);
            DemoDataController.createDemoProjects();
            DemoDataController.createDemoProjectAssignments();
            DemoDataController.createDemoTimesheets();
        }
        // As if the timesheets were created a week ago and the Line Items step runs in the following week.
        List<Timesheet__c> sheets = [SELECT Id, Start_Date__c, End_Date__c FROM Timesheet__c WHERE Is_Demo__c = true];
        for (Timesheet__c ts : sheets) {
            ts.Start_Date__c = ts.Start_Date__c.addDays(-7);
            ts.End_Date__c = ts.End_Date__c.addDays(-7);
        }
        update sheets;

        System.runAs(hrAdmin) {
            DemoDataController.DemoState state = DemoDataController.getDemoData();
            Date oldest = state.blueprint.weeks[0].startDate;
            Assert.areEqual(oldest.addDays(7), DemoDataController.getDemoData().blueprint.weeks[1].startDate, 'Weeks follow each other');
            Assert.isTrue(oldest < Date.today().addDays(-14), 'The plan starts at the moved timesheets, not two weeks before today');
            for (DemoDataController.TimesheetDetail ts : state.timesheets) {
                Assert.isTrue(ts.startDate >= oldest, 'Every timesheet is on a planned week');
            }
            Assert.areEqual(12, DemoDataController.createDemoTimesheets().timesheets.size(), 'No extra timesheets for the new week');

            Test.startTest();
            state = DemoDataController.createDemoLineItems();
            Test.stopTest();

            Assert.areEqual(66, countLineItems(state), 'Every timesheet got its planned line items');
            Map<String, Integer> itemsByPeriod = new Map<String, Integer>();
            for (DemoDataController.TimesheetDetail ts : state.timesheets) {
                Boolean approved = ts.periodName == 'Two Weeks Ago' || ts.periodName == 'Last Week';
                Assert.areEqual(approved ? 'Approved' : 'New', ts.status, 'Status of ' + ts.periodName);
                Integer count = itemsByPeriod.containsKey(ts.periodName) ? itemsByPeriod.get(ts.periodName) : 0;
                itemsByPeriod.put(ts.periodName, count + ts.lineItems.size());
            }
            Assert.areEqual(new Map<String, Integer>{ 'Two Weeks Ago' => 15, 'Last Week' => 27, 'Current Week' => 24, 'Next Week' => 0 },
                itemsByPeriod, 'Line items per week keep their creation-time names');
        }
    }

    @IsTest
    static void rerunningStepsCreatesNothingNew() {
        User hrAdmin = createUser('hradm');
        System.runAs(hrAdmin) {
            DemoDataController.createDemoEmployees(false);
            DemoDataController.createDemoProjects();
            DemoDataController.createDemoProjectAssignments();
            DemoDataController.createDemoTimesheets();
            Test.startTest();
            DemoDataController.createDemoLineItems();

            Assert.areEqual(3, DemoDataController.createDemoProjects().projects.size(), 'No duplicate projects');
            DemoDataController.DemoState state = DemoDataController.createDemoProjectAssignments();
            Assert.areEqual(3, state.projectEmployees.size(), 'No duplicate assignments');
            state = DemoDataController.createDemoTimesheets();
            Assert.areEqual(4, state.timesheets.size(), 'No duplicate timesheets');
            state = DemoDataController.createDemoLineItems();
            Test.stopTest();
            Assert.areEqual(22, countLineItems(state), 'No duplicate line items');
            Assert.isNull(state.projects, 'Nothing changed, so projects are not returned');
        }
    }

    @IsTest
    static void demoEmployeesCanOnlyBeCreatedOnce() {
        User hrAdmin = createUser('hradm');
        System.runAs(hrAdmin) {
            DemoDataController.createDemoEmployees(false);
            // Children can't be added later: the Employee trigger rejects a second employee for the user.
            try {
                DemoDataController.createDemoEmployees(true);
                Assert.fail('A second Demo Employee should be rejected');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('same user already exists'), e.getMessage());
            }
            Assert.areEqual(1, DemoDataController.getDemoData().employees.size(), 'Still one employee');
        }
    }

    @IsTest
    static void userWithEmployeeRecordCannotCreateDemoEmployee() {
        User hrAdmin = createUser('hradm');
        insert newEmployee(hrAdmin.Id);
        System.runAs(hrAdmin) {
            try {
                DemoDataController.createDemoEmployees(true);
                Assert.fail('The user already has an employee record');
            } catch (AuraHandledException e) {
                Assert.isTrue(e.getMessage().contains('same user already exists'), e.getMessage());
            }
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Employee__c WHERE Is_Demo__c = true], 'No demo employees');
    }

    @IsTest
    static void stepsRequirePreviousSteps() {
        User hrAdmin = createUser('hradm');
        System.runAs(hrAdmin) {
            try {
                DemoDataController.createDemoTimesheets();
                Assert.fail('Timesheets need employees');
            } catch (AuraHandledException e) {
                Assert.areEqual('Create the demo employees first.', e.getMessage(), 'Timesheets without employees');
            }
            try {
                DemoDataController.createDemoLineItems();
                Assert.fail('Line items need projects');
            } catch (AuraHandledException e) {
                Assert.areEqual('Create the demo projects first.', e.getMessage(), 'Line items without projects');
            }
            // Assignments without employees or projects create nothing.
            Assert.areEqual(0, DemoDataController.createDemoProjectAssignments().projectEmployees.size(), 'No assignments');
        }
    }

    @IsTest
    static void deleteOnlyTouchesTheUsersDemoData() {
        User hrAdmin = createUser('hradm');
        User otherAdmin = createUser('other');
        Employee__c realEmployee = newEmployee(null);
        insert realEmployee;
        System.runAs(otherAdmin) {
            DemoDataController.createDemoEmployees(false);
            DemoDataController.createDemoProjects();
        }
        System.runAs(hrAdmin) {
            DemoDataController.createDemoEmployees(false);
            DemoDataController.createDemoProjects();
        }
        // A real employee on one of the user's demo projects goes with the project (master-detail).
        Project__c demoProject = [SELECT Id FROM Project__c WHERE CreatedById = :hrAdmin.Id AND Name = :DemoDataController.PROJECT_BILLABLE];
        insert new Project_Employee__c(Employee__c = realEmployee.Id, Project__c = demoProject.Id, Hourly_Rate__c = 100);

        System.runAs(hrAdmin) {
            DemoDataController.deleteDemoRecords();
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Employee__c WHERE CreatedById = :hrAdmin.Id], 'User\'s demo employees deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Project__c WHERE CreatedById = :hrAdmin.Id], 'User\'s demo projects deleted');
        Assert.areEqual(1, [SELECT COUNT() FROM Employee__c WHERE CreatedById = :otherAdmin.Id], 'Other user\'s demo employee kept');
        Assert.areEqual(3, [SELECT COUNT() FROM Project__c WHERE CreatedById = :otherAdmin.Id], 'Other user\'s demo projects kept');
        Assert.areEqual(1, [SELECT COUNT() FROM Employee__c WHERE Id = :realEmployee.Id], 'Real employee kept');
        Assert.areEqual(0, [SELECT COUNT() FROM Project_Employee__c WHERE Employee__c = :realEmployee.Id], 'Assignment went with the demo project');
    }

    @IsTest
    static void isProductionOrgMatchesOrganization() {
        Organization org = [SELECT IsSandbox, TrialExpirationDate FROM Organization LIMIT 1];
        Assert.areEqual(!org.IsSandbox && org.TrialExpirationDate == null, DemoDataController.isProductionOrg(), 'Production check');
    }

    // ---------- Flow and assertions ----------

    /** Runs every step as the popup does, checking each method's query count and returned state. */
    private static void runFullFlow(Boolean withChildren) {
        Integer employees = withChildren ? 3 : 1;

        Integer queries = Limits.getQueries();
        DemoDataController.DemoState state = DemoDataController.getDemoData();
        Assert.areEqual(2, Limits.getQueries() - queries, 'getDemoData: employees and projects queries');

        queries = Limits.getQueries();
        state = DemoDataController.createDemoEmployees(withChildren);
        Assert.isTrue(Limits.getQueries() - queries <= 4, 'createDemoEmployees: 1 query plus the Employee trigger, got ' + (Limits.getQueries() - queries));
        Assert.areEqual(employees, state.employees.size(), 'Employees returned');
        Assert.isNull(state.projects, 'Projects unchanged, not returned');

        queries = Limits.getQueries();
        state = DemoDataController.createDemoProjects();
        Assert.areEqual(1, Limits.getQueries() - queries, 'createDemoProjects: 1 query, result built from memory');
        Assert.areEqual(3, state.projects.size(), 'Projects returned');
        Assert.isNull(state.employees, 'Employees unchanged, not returned');
        List<String> projectNames = new List<String>();
        for (DemoDataController.DemoRecordDetail proj : state.projects) {
            Assert.isNotNull(proj.recordId, 'Project saved');
            projectNames.add(proj.name);
        }
        Assert.areEqual(new List<String>{ DemoDataController.PROJECT_BILLABLE, DemoDataController.PROJECT_LEGACY, DemoDataController.PROJECT_NON_BILLABLE }, projectNames, 'Projects in name order');

        queries = Limits.getQueries();
        state = DemoDataController.createDemoProjectAssignments();
        Assert.areEqual(3, Limits.getQueries() - queries, 'createDemoProjectAssignments: 3 queries');
        Assert.areEqual(employees * 3, state.projectEmployees.size(), 'Every employee on every project');

        queries = Limits.getQueries();
        state = DemoDataController.createDemoTimesheets();
        Assert.areEqual(2, Limits.getQueries() - queries, 'createDemoTimesheets: 2 queries');
        Assert.areEqual(employees * 4, state.timesheets.size(), 'Four timesheets per employee');
        for (DemoDataController.TimesheetDetail ts : state.timesheets) {
            Assert.areEqual('New', ts.status, 'Timesheets start New');
            Assert.areEqual(0, ts.lineItems.size(), 'No line items yet');
        }

        Test.startTest();
        queries = Limits.getQueries();
        state = DemoDataController.createDemoLineItems();
        Assert.isTrue(Limits.getQueries() - queries <= 25, 'createDemoLineItems: 3 queries plus the triggers, got ' + (Limits.getQueries() - queries));
        Test.stopTest();
        Assert.areEqual(employees * 22, countLineItems(state), '22 line items per employee');
        Assert.areEqual(3, state.projects.size(), 'Projects returned with Legacy deactivated');
        for (DemoDataController.DemoRecordDetail proj : state.projects) {
            Assert.areEqual(proj.name != DemoDataController.PROJECT_LEGACY, proj.active, 'Only Legacy inactive: ' + proj.name);
        }
        Assert.isTrue(state.userTimesheetsWithoutManager, 'The user has no manager, so the Demo Employee\'s timesheets have none');
    }

    /** Checks every created record against the blueprint the popup previews. */
    private static void assertCreatedRecords(User hrAdmin, Boolean withChildren) {
        DemoDataController.Blueprint blueprint = DemoDataController.getDemoData().blueprint;
        Integer employees = withChildren ? 3 : 1;

        // Employees
        List<Employee__c> emps = [
            SELECT Name, First_Name__c, Last_Name__c, User__c, Manager__c, Email__c, Employment_Type__c, Active__c,
                Accrual_Start_Date__c, Accrual_Divisor__c, Extra_Accrued_Hours__c, Is_Demo__c
            FROM Employee__c WHERE CreatedById = :hrAdmin.Id ORDER BY CreatedDate, User__c NULLS LAST, Last_Name__c
        ];
        Assert.areEqual(employees, emps.size(), 'Employees created');
        for (Integer i = 0; i < emps.size(); i++) {
            Employee__c emp = emps[i];
            DemoDataController.DemoRecordDetail plan = blueprint.employees[i];
            Assert.areEqual(plan.name, emp.First_Name__c + ' ' + emp.Last_Name__c, 'Employee name as previewed');
            Assert.areEqual(plan.email, emp.Email__c, 'Email');
            Assert.areEqual(plan.employmentType, emp.Employment_Type__c, 'Employment type');
            Assert.areEqual(plan.accrualStartDate, emp.Accrual_Start_Date__c, 'Accrual start');
            Assert.areEqual(plan.accrualDivisor, emp.Accrual_Divisor__c, 'Accrual divisor');
            Assert.areEqual(plan.extraAccruedHours, emp.Extra_Accrued_Hours__c, 'Extra accrued hours');
            Assert.isTrue(emp.Is_Demo__c && emp.Active__c, 'Active demo employee');
            if (i == 0) {
                Assert.areEqual(hrAdmin.Id, emp.User__c, 'Demo Employee linked to the user');
                Assert.isNull(emp.Manager__c, 'Demo Employee has no manager');
            } else {
                Assert.isNull(emp.User__c, 'Child employee not linked to a user');
                Assert.areEqual(hrAdmin.Id, emp.Manager__c, 'Child employee reports to the user');
            }
        }

        // Projects
        Map<String, Project__c> projects = new Map<String, Project__c>();
        for (Project__c proj : [SELECT Name, Billable__c, Active__c, Is_Demo__c FROM Project__c WHERE CreatedById = :hrAdmin.Id]) {
            projects.put(proj.Name, proj);
        }
        Assert.areEqual(3, projects.size(), 'Projects created');
        for (DemoDataController.DemoRecordDetail plan : blueprint.projects) {
            Project__c proj = projects.get(plan.name);
            Assert.isNotNull(proj, 'Project created: ' + plan.name);
            Assert.areEqual(plan.billable, proj.Billable__c, 'Billable: ' + plan.name);
            Assert.isTrue(proj.Is_Demo__c, 'Demo project');
            Assert.areEqual(plan.name != DemoDataController.PROJECT_LEGACY, proj.Active__c, 'Only Legacy deactivated: ' + plan.name);
        }

        // Assignments
        Assert.areEqual(employees * 3, [SELECT COUNT() FROM Project_Employee__c WHERE Employee__c IN :emps AND Hourly_Rate__c = 150], 'Every employee on every project at 150');

        // Timesheets and line items, week by week
        Map<Date, DemoDataController.WeekPlan> weeks = new Map<Date, DemoDataController.WeekPlan>();
        for (DemoDataController.WeekPlan week : blueprint.weeks) {
            weeks.put(week.startDate, week);
        }
        List<Timesheet__c> timesheets = [
            SELECT Employee__c, Manager__c, Start_Date__c, End_Date__c, Status__c, Is_Demo__c, Total_Hours__c,
                (SELECT Date__c, Duration__c, Project__r.Name, Activity__c, Type__c, Absence_Category__c, Employee__c FROM Timesheets__r ORDER BY Date__c, Duration__c DESC, Project__r.Name)
            FROM Timesheet__c WHERE Employee__c IN :emps
        ];
        Assert.areEqual(employees * 4, timesheets.size(), 'Four timesheets per employee');
        Map<Id, Employee__c> empById = new Map<Id, Employee__c>(emps);
        for (Timesheet__c ts : timesheets) {
            DemoDataController.WeekPlan week = weeks.get(ts.Start_Date__c);
            Assert.isNotNull(week, 'Timesheet on a blueprint week');
            Assert.areEqual(week.endDate, ts.End_Date__c, 'End date');
            Assert.areEqual(empById.get(ts.Employee__c).Manager__c, ts.Manager__c, 'Timesheet manager = employee manager');
            Assert.isTrue(ts.Is_Demo__c, 'Demo timesheet');
            Assert.areEqual(week.approvalRound > 0 ? 'Approved' : 'New', ts.Status__c, 'Status of ' + week.periodName);
            Assert.areEqual(week.lineItems.size(), ts.Timesheets__r.size(), 'Line items in ' + week.periodName);
            Decimal expectedHours = 0;
            for (DemoDataController.LineItemPlan plan : week.lineItems) {
                expectedHours += plan.duration;
            }
            Decimal actualHours = 0;
            Map<String, Integer> expected = new Map<String, Integer>();
            for (DemoDataController.LineItemPlan plan : week.lineItems) {
                String key = plan.lineDate + '|' + plan.duration.setScale(2) + '|' + plan.projectName + '|' + plan.activity + '|' + plan.type + '|' + plan.absenceCategory;
                expected.put(key, (expected.containsKey(key) ? expected.get(key) : 0) + 1);
            }
            for (Timesheet_Line_Item__c tli : ts.Timesheets__r) {
                actualHours += tli.Duration__c;
                Assert.areEqual(ts.Employee__c, tli.Employee__c, 'Line item employee');
                String key = tli.Date__c + '|' + tli.Duration__c.setScale(2) + '|' + tli.Project__r?.Name + '|' + tli.Activity__c + '|' + tli.Type__c + '|' + tli.Absence_Category__c;
                Assert.isTrue(expected.containsKey(key) && expected.get(key) > 0, 'Line item as previewed: ' + key);
                expected.put(key, expected.get(key) - 1);
            }
            Assert.areEqual(expectedHours, actualHours, 'Hours in ' + week.periodName);
        }

        // What the popup loads matches the records
        DemoDataController.DemoState state = DemoDataController.getDemoData();
        Assert.areEqual(employees, state.employees.size(), 'Employees loaded');
        Assert.areEqual(3, state.projects.size(), 'Projects loaded');
        Assert.areEqual(employees * 3, state.projectEmployees.size(), 'Assignments loaded');
        Assert.areEqual(employees * 4, state.timesheets.size(), 'Timesheets loaded');
        Assert.areEqual(employees * 22, countLineItems(state), 'Line items loaded');
        Integer children = 0;
        for (DemoDataController.DemoRecordDetail emp : state.employees) {
            Assert.areEqual(3, emp.assignmentCount, 'Assignments of ' + emp.name);
            Assert.areEqual(4, emp.timesheetCount, 'Timesheets of ' + emp.name);
            children += emp.isChild ? 1 : 0;
        }
        Assert.areEqual(withChildren ? 2 : 0, children, 'Child employees flagged');
    }

    private static void assertDeletesEverything(Boolean withChildren) {
        Id userId = UserInfo.getUserId();
        Integer queries = Limits.getQueries();
        DemoDataController.deleteDemoRecords();
        Assert.isTrue(Limits.getQueries() - queries <= 8, 'deleteDemoRecords: 2 queries plus the Timesheet trigger, got ' + (Limits.getQueries() - queries));

        Assert.areEqual(0, [SELECT COUNT() FROM Employee__c WHERE CreatedById = :userId], 'Employees deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Project__c WHERE CreatedById = :userId], 'Projects deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Timesheet__c WHERE CreatedById = :userId], 'Timesheets deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE CreatedById = :userId], 'Line items deleted with their timesheets');
        Assert.areEqual(0, [SELECT COUNT() FROM Project_Employee__c WHERE CreatedById = :userId], 'Assignments deleted with their projects');

        DemoDataController.DemoState state = DemoDataController.getDemoData();
        Assert.areEqual(0, state.employees.size() + state.projects.size(), 'Nothing left to load');
    }

    private static Integer countLineItems(DemoDataController.DemoState state) {
        Integer count = 0;
        for (DemoDataController.TimesheetDetail ts : state.timesheets) {
            count += ts.lineItems.size();
        }
        return count;
    }

    private static Employee__c newEmployee(Id userId) {
        return new Employee__c(
            First_Name__c = 'Real',
            Last_Name__c = 'Employee',
            User__c = userId,
            Email__c = 'real.employee@example.com',
            Employment_Type__c = 'Full Time',
            Active__c = true
        );
    }

    private static User createUser(String alias) {
        String unique = alias + Datetime.now().getTime() + Crypto.getRandomInteger();
        User u = new User(
            FirstName = 'Test',
            LastName = alias,
            Alias = alias,
            Email = unique + '@example.com',
            Username = unique + '@demodata.test',
            CommunityNickname = unique.left(40),
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        // Setup objects (User, PermissionSetAssignment) need their own context to avoid mixed DML.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
            insert new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :HR_ADMIN_PERMISSION_SET LIMIT 1].Id
            );
        }
        return u;
    }
}
