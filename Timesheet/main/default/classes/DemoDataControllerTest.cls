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
                String expected = project.name == DemoDataController.PROJECT_LEGACY ? 'Inactive' : 'Active';
                Assert.areEqual(expected, project.status, 'Only the legacy project is deactivated: ' + project.name);
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
