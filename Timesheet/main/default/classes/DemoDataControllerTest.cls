/**
 * @description Tests for DemoDataController: the demo data flow, step order, and who may create or delete demo data.
 */
@IsTest
private class DemoDataControllerTest {

    private static final String HR_ADMIN_PERMISSION_SET = 'Timesheet_HR_Admin';
    private static final String USER_PERMISSION_SET = 'Timesheet_User';

    @IsTest
    static void eligibleHrAdminCanCreate() {
        User hrAdmin = createUser('hradm', HR_ADMIN_PERMISSION_SET);

        System.runAs(hrAdmin) {
            Map<String, Object> status = DemoDataController.getDemoStatus();
            Assert.isTrue((Boolean) status.get('hasAccess'), 'HR admin without an employee should have access');
            Assert.isTrue((Boolean) status.get('canCreate'), 'HR admin without an employee should be able to create demo data');
            Assert.isTrue(status.containsKey('isProductionOrg'), 'Status should say whether the org is production');
        }
    }

    @IsTest
    static void fullDemoFlowCreatesAndDeletesRecords() {
        User hrAdmin = createUser('hradm', HR_ADMIN_PERMISSION_SET);

        System.runAs(hrAdmin) {
            DemoDataController.createDemoEmployee();
            DemoDataController.createChildEmployees();
            DemoDataController.createDemoProjects();
            DemoDataController.createDemoProjectAssignments();
            Test.startTest();
            DemoDataController.createDemoTimesheets();
            Test.stopTest();

            Employee__c demoEmployee = [
                SELECT User__c, Manager__c FROM Employee__c
                WHERE Is_Demo__c = true AND Last_Name__c = :DemoDataController.PARENT_LAST_NAME
            ];
            Assert.areEqual(hrAdmin.Id, demoEmployee.User__c, 'Demo Employee should be linked to the running user');
            Assert.isNull(demoEmployee.Manager__c, 'Demo Employee should have no manager when the user has none');
            for (Employee__c child : [SELECT Manager__c FROM Employee__c WHERE Is_Demo__c = true AND Last_Name__c LIKE 'Child Employee%']) {
                Assert.areEqual(hrAdmin.Id, child.Manager__c, 'Child employees should report to the running user');
            }

            DemoDataController.DemoDataWrapper records = DemoDataController.getDemoRecords();
            Assert.areEqual(3, records.employees.size(), 'Demo employee plus two child employees');
            Assert.areEqual(3, records.projects.size(), 'Billable, non-billable and legacy projects');
            Assert.areEqual(9, records.projectEmployees.size(), 'Every employee assigned to every project');
            Assert.areEqual(12, records.timesheets.size(), 'Four weekly timesheets per employee');
            Assert.isTrue(records.userTimesheetsWithoutManager, 'The user has no manager, so their timesheets have none');

            Integer approved = 0;
            Integer lineItems = 0;
            for (DemoDataController.TimesheetDetail ts : records.timesheets) {
                if (ts.status == 'Approved') {
                    approved++;
                }
                lineItems += ts.lineItems.size();
            }
            Assert.areEqual(6, approved, 'The two oldest weeks of each employee should be approved');
            // Per employee: 5 legacy days + (4 days x 2 projects + 1 sick day) + (3 days x 2 projects + 2 sick days) = 22
            Assert.areEqual(66, lineItems, 'Line items for three employees');

            for (DemoDataController.DemoRecordDetail project : records.projects) {
                Assert.areEqual(project.name != DemoDataController.PROJECT_LEGACY, project.active, 'Only the legacy project is deactivated: ' + project.name);
            }

            DemoDataController.DeleteSummary summary = DemoDataController.getDeleteSummary();
            Assert.areEqual(66, summary.lineItems, 'Line items to delete');
            Assert.areEqual(12, summary.timesheets, 'Timesheets to delete');
            Assert.areEqual(9, summary.projectEmployees, 'Project assignments to delete');
            Assert.areEqual(3, summary.projects, 'Projects to delete');
            Assert.areEqual(3, summary.employees, 'Employees to delete');

            DemoDataController.deleteDemoRecords();
        }

        Assert.areEqual(0, [SELECT COUNT() FROM Employee__c WHERE Is_Demo__c = true], 'Demo employees deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Project__c WHERE Is_Demo__c = true], 'Demo projects deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Timesheet__c WHERE Is_Demo__c = true], 'Demo timesheets deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Timesheet_Line_Item__c], 'Demo line items deleted');
        Assert.areEqual(0, [SELECT COUNT() FROM Project_Employee__c], 'Demo project assignments deleted');
    }

    @IsTest
    static void skippedChildEmployeesCanBeAddedLater() {
        User hrAdmin = createUser('hradm', HR_ADMIN_PERMISSION_SET);

        System.runAs(hrAdmin) {
            // Child employees skipped: only the demo employee gets assignments, timesheets and line items.
            DemoDataController.createDemoEmployee();
            DemoDataController.createDemoProjects();
            DemoDataController.createDemoProjectAssignments();
            DemoDataController.createDemoTimesheets();

            DemoDataController.DemoDataWrapper records = DemoDataController.getDemoRecords();
            Assert.areEqual(1, records.employees.size(), 'Only the demo employee');
            Assert.isTrue(records.employees[0].canCreateChildren, 'Child employees can still be added');
            Assert.areEqual(3, records.employees[0].assignmentCount, 'Demo employee assigned to every project');
            Assert.areEqual(4, records.employees[0].timesheetCount, 'Four weekly timesheets');
            Assert.areEqual(3, records.projectEmployees.size(), 'Assignments for the demo employee only');
            Assert.areEqual(22, countLineItems(records), 'Line items for the demo employee only');

            // Added later: the assignment and timesheet steps only fill the gaps.
            DemoDataController.createChildEmployees();
            records = DemoDataController.getDemoRecords();
            Assert.areEqual(3, records.employees.size(), 'Demo employee plus two child employees');
            for (DemoDataController.DemoRecordDetail emp : records.employees) {
                Assert.isFalse(emp.canCreateChildren, 'Child employees exist now');
            }

            Test.startTest();
            DemoDataController.createDemoProjectAssignments();
            DemoDataController.createDemoTimesheets();
            Test.stopTest();

            records = DemoDataController.getDemoRecords();
            Assert.areEqual(9, records.projectEmployees.size(), 'Every employee assigned to every project once');
            Assert.areEqual(12, records.timesheets.size(), 'Four weekly timesheets per employee, no duplicates');
            Assert.areEqual(66, countLineItems(records), 'Line items for three employees');
            for (DemoDataController.DemoRecordDetail emp : records.employees) {
                Assert.areEqual(3, emp.assignmentCount, 'Assignments of ' + emp.name);
                Assert.areEqual(4, emp.timesheetCount, 'Timesheets of ' + emp.name);
            }
            for (DemoDataController.DemoRecordDetail project : records.projects) {
                Assert.areEqual(project.name != DemoDataController.PROJECT_LEGACY, project.active, 'Project states restored after filling the gaps: ' + project.name);
            }
        }
    }

    @IsTest
    static void saveDemoRecordsUpdatesAllowedFields() {
        User hrAdmin = createUser('hradm', HR_ADMIN_PERMISSION_SET);

        System.runAs(hrAdmin) {
            DemoDataController.createDemoEmployee();
            DemoDataController.createDemoProjects();
            DemoDataController.createDemoProjectAssignments();
            Test.startTest();
            DemoDataController.createDemoTimesheets();
            Test.stopTest();

            // Edit an assignment on the legacy project, which the timesheet step deactivated: the Project
            // lookup filter (active projects only) is checked on every update, even when the lookup doesn't change.
            DemoDataController.DemoDataWrapper records = DemoDataController.getDemoRecords();
            String employeeId = records.employees[0].recordId;
            String assignmentId;
            for (DemoDataController.DemoRecordDetail pe : records.projectEmployees) {
                if (pe.projectName == DemoDataController.PROJECT_LEGACY) {
                    assignmentId = pe.recordId;
                }
            }

            Map<String, String> errors = DemoDataController.saveDemoRecords('employees', new List<Map<String, Object>>{
                new Map<String, Object>{ 'recordId' => employeeId, 'email' => 'edited@example.com', 'active' => false }
            });
            Assert.isTrue(errors.isEmpty(), 'Employee saved: ' + errors);
            errors = DemoDataController.saveDemoRecords('projectEmployees', new List<Map<String, Object>>{
                new Map<String, Object>{ 'recordId' => assignmentId, 'hourlyRate' => '200' }
            });
            Assert.isTrue(errors.isEmpty(), 'Legacy assignment saved: ' + errors);
        }

        Employee__c emp = [SELECT Email__c, Active__c FROM Employee__c WHERE Is_Demo__c = true];
        Assert.areEqual('edited@example.com', emp.Email__c, 'Email updated');
        Assert.isFalse(emp.Active__c, 'Active updated');
        Assert.areEqual(1, [SELECT COUNT() FROM Project_Employee__c WHERE Hourly_Rate__c = 200], 'Hourly rate updated');
        Assert.isFalse([SELECT Active__c FROM Project__c WHERE Name = :DemoDataController.PROJECT_LEGACY].Active__c, 'Legacy project stays inactive');
    }

    @IsTest
    static void saveDemoRecordsRejectsOtherRecordsAndFields() {
        User hrAdmin = createUser('hradm', HR_ADMIN_PERMISSION_SET);
        Employee__c realEmployee = newEmployee(null, true);
        insert realEmployee;

        System.runAs(hrAdmin) {
            DemoDataController.createDemoEmployee();
            DemoDataController.createDemoProjects();
        }
        // A real employee assigned to a demo project: not shown in the demo tables, so not editable there.
        Project__c demoProject = [SELECT Id FROM Project__c WHERE Name = :DemoDataController.PROJECT_BILLABLE];
        Project_Employee__c realAssignment = new Project_Employee__c(Employee__c = realEmployee.Id, Project__c = demoProject.Id, Hourly_Rate__c = 100);
        insert realAssignment;

        System.runAs(hrAdmin) {
            String demoEmployeeId = DemoDataController.getDemoRecords().employees[0].recordId;

            Map<String, String> errors = DemoDataController.saveDemoRecords('employees', new List<Map<String, Object>>{
                new Map<String, Object>{ 'recordId' => realEmployee.Id, 'email' => 'changed@example.com' },
                new Map<String, Object>{ 'recordId' => demoEmployeeId, 'accrualDivisor' => '10' }
            });
            Assert.areEqual('This record cannot be edited here.', errors.get(realEmployee.Id), 'Non-demo records are rejected');
            Assert.areEqual('The field accrualDivisor cannot be edited here.', errors.get(demoEmployeeId), 'Read-only columns are rejected');

            errors = DemoDataController.saveDemoRecords('projectEmployees', new List<Map<String, Object>>{
                new Map<String, Object>{ 'recordId' => realAssignment.Id, 'hourlyRate' => '999' }
            });
            Assert.areEqual('This record cannot be edited here.', errors.get(realAssignment.Id), 'Real employees on demo projects are rejected');

            try {
                DemoDataController.saveDemoRecords('lineItems', new List<Map<String, Object>>());
                Assert.fail('Unknown tables should be rejected');
            } catch (AuraHandledException e) {
                Assert.areEqual('Unknown demo data table: lineItems', e.getMessage(), 'Line items are read-only');
            }
        }

        Assert.areEqual('real.employee@example.com', [SELECT Email__c FROM Employee__c WHERE Id = :realEmployee.Id].Email__c, 'Real employee not changed');
        Assert.areNotEqual(10, [SELECT Accrual_Divisor__c FROM Employee__c WHERE Is_Demo__c = true].Accrual_Divisor__c, 'Demo employee not changed');
        Assert.areEqual(100, [SELECT Hourly_Rate__c FROM Project_Employee__c WHERE Id = :realAssignment.Id].Hourly_Rate__c, 'Real assignment not changed');
    }

    @IsTest
    static void stepsRequirePreviousSteps() {
        User hrAdmin = createUser('hradm', HR_ADMIN_PERMISSION_SET);

        System.runAs(hrAdmin) {
            assertAuraError('Create the demo employee first.', 'children');
            assertAuraError('Create the demo projects first.', 'timesheets');

            DemoDataController.createDemoEmployee();
            assertAuraError('A demo employee already exists.', 'employee');

            DemoDataController.createChildEmployees();
            assertAuraError('Child employees already exist.', 'children');
        }
    }

    @IsTest
    static void activeEmployeeCanOnlyCleanUp() {
        User hrAdmin = createUser('hradm', HR_ADMIN_PERMISSION_SET);
        System.runAs(hrAdmin) {
            DemoDataController.createDemoProjects();
        }

        insert newEmployee(hrAdmin.Id, true);

        System.runAs(hrAdmin) {
            Map<String, Object> status = DemoDataController.getDemoStatus();
            Assert.isTrue((Boolean) status.get('hasAccess'), 'HR admin with demo records should keep access to clean up');
            Assert.isFalse((Boolean) status.get('canCreate'), 'HR admin with an active employee cannot create demo data');
            assertAuraError('Demo data can only be created by HR admins without an active employee record.', 'employee');

            DemoDataController.deleteDemoRecords();

            status = DemoDataController.getDemoStatus();
            Assert.isFalse((Boolean) status.get('hasAccess'), 'No access once the demo records are gone');
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Project__c WHERE Is_Demo__c = true], 'Demo projects deleted');
        Assert.areEqual(1, [SELECT COUNT() FROM Employee__c WHERE Is_Demo__c = false], 'Real employee kept');
    }

    @IsTest
    static void linkedInactiveEmployeeBlocksDemoEmployee() {
        User hrAdmin = createUser('hradm', HR_ADMIN_PERMISSION_SET);
        insert newEmployee(hrAdmin.Id, false);

        System.runAs(hrAdmin) {
            Assert.isTrue((Boolean) DemoDataController.getDemoStatus().get('canCreate'), 'An inactive employee does not block demo data');
            assertAuraError('An employee record is already linked to your user, so the demo employee cannot be linked to you.', 'employee');
        }
    }

    @IsTest
    static void nonHrAdminHasNoAccess() {
        User employeeUser = createUser('emplo', USER_PERMISSION_SET);

        System.runAs(employeeUser) {
            Map<String, Object> status = DemoDataController.getDemoStatus();
            Assert.isFalse((Boolean) status.get('hasAccess'), 'Only HR admins have access');
            Assert.isFalse((Boolean) status.get('canCreate'), 'Only HR admins can create demo data');

            String accessError = 'Demo data setup is available to HR admins without an active employee record.';
            try {
                DemoDataController.getDemoRecords();
                Assert.fail('getDemoRecords should be rejected');
            } catch (AuraHandledException e) {
                Assert.areEqual(accessError, e.getMessage(), 'getDemoRecords error');
            }
            try {
                DemoDataController.deleteDemoRecords();
                Assert.fail('deleteDemoRecords should be rejected');
            } catch (AuraHandledException e) {
                Assert.areEqual(accessError, e.getMessage(), 'deleteDemoRecords error');
            }
            assertAuraError('Demo data can only be created by HR admins without an active employee record.', 'projects');
        }
    }

    /** Runs one create step and asserts it fails with the expected message. */
    private static void assertAuraError(String expectedMessage, String step) {
        try {
            if (step == 'employee') {
                DemoDataController.createDemoEmployee();
            } else if (step == 'children') {
                DemoDataController.createChildEmployees();
            } else if (step == 'projects') {
                DemoDataController.createDemoProjects();
            } else if (step == 'timesheets') {
                DemoDataController.createDemoTimesheets();
            }
            Assert.fail('Expected "' + expectedMessage + '" from step ' + step);
        } catch (AuraHandledException e) {
            Assert.areEqual(expectedMessage, e.getMessage(), 'Error from step ' + step);
        }
    }

    private static Integer countLineItems(DemoDataController.DemoDataWrapper records) {
        Integer count = 0;
        for (DemoDataController.TimesheetDetail ts : records.timesheets) {
            count += ts.lineItems.size();
        }
        return count;
    }

    private static Employee__c newEmployee(Id userId, Boolean active) {
        return new Employee__c(
            First_Name__c = 'Real',
            Last_Name__c = 'Employee',
            User__c = userId,
            Email__c = 'real.employee@example.com',
            Employment_Type__c = 'Full Time',
            Active__c = active
        );
    }

    private static User createUser(String alias, String permissionSetName) {
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
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1].Id
            );
        }
        return u;
    }
}
