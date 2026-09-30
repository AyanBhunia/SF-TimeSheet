@isTest
private class ProjectEmployeeControllerTest {

    @testSetup
    static void setupData() {
        User grouped = createUser('pegrp');
        User ungrouped = createUser('pesolo');

        // Setup objects (Group, GroupMember) need their own context to avoid mixed DML.
        System.runAs(new User(Id = UserInfo.getUserId())) {
            Group g = new Group(Name = 'PE Test Group', DeveloperName = 'PE_Test_Group', Type = 'Regular');
            insert g;
            insert new GroupMember(GroupId = g.Id, UserOrGroupId = grouped.Id);
        }

        insert new List<Project__c>{
            new Project__c(Name = 'PE Active Project', Billable__c = 'Yes', Active__c = true),
            new Project__c(Name = 'PE Second Project', Billable__c = 'No', Active__c = true),
            new Project__c(Name = 'PE Inactive Project', Billable__c = 'No', Active__c = false)
        };

        insert new List<Employee__c>{
            newEmployee('Grouped', grouped.Id, true),
            newEmployee('Solo', ungrouped.Id, true),
            newEmployee('Inactive', null, false)
        };

        insert new Project_Employee__c(
            Project__c = project('PE Active Project').Id,
            Employee__c = employee('Grouped').Id,
            Hourly_Rate__c = 100
        );
    }

    @isTest
    static void getInitialDataReturnsOnlyActiveRecords() {
        Test.startTest();
        ProjectEmployeeController.InitialDataWrapper data = ProjectEmployeeController.getInitialData();
        Test.stopTest();

        Set<String> projectNames = new Set<String>();
        for (Project__c p : data.projects) {
            projectNames.add(p.Name);
        }
        Assert.isTrue(projectNames.contains('PE Active Project'), 'Active project is listed');
        Assert.isTrue(projectNames.contains('PE Second Project'), 'Second active project is listed');
        Assert.isFalse(projectNames.contains('PE Inactive Project'), 'Inactive project is not listed');

        Set<Id> employeeIds = new Map<Id, Employee__c>(data.employees).keySet();
        Assert.isTrue(employeeIds.contains(employee('Grouped').Id), 'Active employee is listed');
        Assert.isTrue(employeeIds.contains(employee('Solo').Id), 'Active employee is listed');
        Assert.isFalse(employeeIds.contains(employee('Inactive').Id), 'Inactive employee is not listed');

        Boolean hasGroup = false;
        for (Group g : data.groups) {
            hasGroup = hasGroup || g.Name == 'PE Test Group';
        }
        Assert.isTrue(hasGroup, 'Public group is listed');
    }

    @isTest
    static void getEmployeesByGroupReturnsMembersOnly() {
        Id groupId = [SELECT Id FROM Group WHERE DeveloperName = 'PE_Test_Group'].Id;

        Test.startTest();
        List<Id> employeeIds = ProjectEmployeeController.getEmployeesByGroup(groupId);
        Test.stopTest();

        Assert.areEqual(new List<Id>{ employee('Grouped').Id }, employeeIds, 'Only the group member is returned');
    }

    @isTest
    static void getExistingCombinationsReturnsKeysOfExistingRecords() {
        Id activeProject = project('PE Active Project').Id;
        Id secondProject = project('PE Second Project').Id;
        Id grouped = employee('Grouped').Id;
        Id solo = employee('Solo').Id;

        Test.startTest();
        List<String> keys = ProjectEmployeeController.getExistingCombinations(
            new List<Id>{ activeProject, secondProject },
            new List<Id>{ grouped, solo }
        );
        Test.stopTest();

        Assert.areEqual(new List<String>{ activeProject + '_' + grouped }, keys, 'Only the existing pair is returned');
    }

    @isTest
    static void saveProjectEmployeesInsertsNewPairsAndSkipsDuplicates() {
        Id activeProject = project('PE Active Project').Id;
        Id secondProject = project('PE Second Project').Id;
        Id grouped = employee('Grouped').Id;
        Id solo = employee('Solo').Id;

        List<ProjectEmployeeController.ProjectEmployeeSaveWrapper> records = new List<ProjectEmployeeController.ProjectEmployeeSaveWrapper>{
            wrapper(activeProject, solo, 150),   // new
            wrapper(secondProject, grouped, 75), // new
            wrapper(activeProject, grouped, 999), // already exists
            wrapper(activeProject, solo, 200)    // duplicate within the request
        };

        Test.startTest();
        Integer created = ProjectEmployeeController.saveProjectEmployees(records);
        Test.stopTest();

        Assert.areEqual(2, created, 'Only the two new pairs are counted');

        Map<String, Decimal> rateByKey = new Map<String, Decimal>();
        for (Project_Employee__c pe : [SELECT Project__c, Employee__c, Hourly_Rate__c FROM Project_Employee__c]) {
            rateByKey.put(pe.Project__c + '_' + pe.Employee__c, pe.Hourly_Rate__c);
        }
        Assert.areEqual(3, rateByKey.size(), 'Two new records plus the existing one');
        Assert.areEqual(150, rateByKey.get(activeProject + '_' + solo), 'First row of a duplicated pair wins');
        Assert.areEqual(75, rateByKey.get(secondProject + '_' + grouped), 'New pair is created with its rate');
        Assert.areEqual(100, rateByKey.get(activeProject + '_' + grouped), 'Existing record is left unchanged');
    }

    @isTest
    static void saveProjectEmployeesWithOnlyExistingPairsInsertsNothing() {
        Test.startTest();
        Integer created = ProjectEmployeeController.saveProjectEmployees(new List<ProjectEmployeeController.ProjectEmployeeSaveWrapper>{
            wrapper(project('PE Active Project').Id, employee('Grouped').Id, 50)
        });
        Test.stopTest();

        Assert.areEqual(0, created, 'Nothing is reported as created');

        Assert.areEqual(1, [SELECT COUNT() FROM Project_Employee__c], 'No new records are inserted');
    }

    @isTest
    static void managerCanAssignEmployeesSharedWithThem() {
        User manager = createUser('pemgr', 'TimeSheet_Manager');
        Id solo = employee('Solo').Id;
        // Employee__c is Private; managers only see employees shared with them
        insert new Employee__Share(ParentId = solo, UserOrGroupId = manager.Id, AccessLevel = 'Read');

        System.runAs(manager) {
            ProjectEmployeeController.InitialDataWrapper data = ProjectEmployeeController.getInitialData();
            Assert.isTrue(new Map<Id, Employee__c>(data.employees).containsKey(solo), 'Manager sees employees shared with them');

            ProjectEmployeeController.saveProjectEmployees(new List<ProjectEmployeeController.ProjectEmployeeSaveWrapper>{
                wrapper(project('PE Second Project').Id, solo, 60)
            });
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Project_Employee__c WHERE Employee__c = :solo], 'Manager created the assignment');
    }

    @isTest
    static void hrAdminCanAssignAnyEmployee() {
        User hrAdmin = createUser('pehr', 'Timesheet_HR_Admin');
        Id solo = employee('Solo').Id;
        Id grouped = employee('Grouped').Id;

        System.runAs(hrAdmin) {
            ProjectEmployeeController.InitialDataWrapper data = ProjectEmployeeController.getInitialData();
            Assert.isTrue(new Map<Id, Employee__c>(data.employees).keySet().containsAll(new Set<Id>{ solo, grouped }), 'HR admin sees every active employee');

            ProjectEmployeeController.saveProjectEmployees(new List<ProjectEmployeeController.ProjectEmployeeSaveWrapper>{
                wrapper(project('PE Second Project').Id, solo, 60),
                wrapper(project('PE Second Project').Id, grouped, 70)
            });
        }
        Assert.areEqual(2, [SELECT COUNT() FROM Project_Employee__c WHERE Project__r.Name = 'PE Second Project'], 'HR admin created both assignments');
    }

    @isTest
    static void userWithoutCreateAccessCannotSave() {
        User employeeUser = createUser('peusr', 'Timesheet_User');
        Id solo = employee('Solo').Id;
        insert new Employee__Share(ParentId = solo, UserOrGroupId = employeeUser.Id, AccessLevel = 'Read');

        Boolean blocked = false;
        System.runAs(employeeUser) {
            try {
                ProjectEmployeeController.saveProjectEmployees(new List<ProjectEmployeeController.ProjectEmployeeSaveWrapper>{
                    wrapper(project('PE Second Project').Id, solo, 9999)
                });
            } catch (Exception e) {
                blocked = true;
            }
        }
        Assert.isTrue(blocked, 'User mode blocks users without create access on Project Employee');
        Assert.areEqual(0, [SELECT COUNT() FROM Project_Employee__c WHERE Employee__c = :solo], 'Nothing was inserted');
    }

    private static ProjectEmployeeController.ProjectEmployeeSaveWrapper wrapper(Id projectId, Id employeeId, Decimal rate) {
        ProjectEmployeeController.ProjectEmployeeSaveWrapper w = new ProjectEmployeeController.ProjectEmployeeSaveWrapper();
        w.projectId = projectId;
        w.employeeId = employeeId;
        w.hourlyRate = rate;
        return w;
    }

    private static Project__c project(String name) {
        return [SELECT Id FROM Project__c WHERE Name = :name];
    }

    private static Employee__c employee(String lastName) {
        return [SELECT Id FROM Employee__c WHERE Last_Name__c = :lastName];
    }

    private static Employee__c newEmployee(String lastName, Id userId, Boolean active) {
        return new Employee__c(
            First_Name__c = 'PE',
            Last_Name__c = lastName,
            User__c = userId,
            Email__c = lastName.toLowerCase() + '.pe@example.com',
            Employment_Type__c = 'Full Time',
            Active__c = active
        );
    }

    private static User createUser(String alias, String permissionSetName) {
        User u = createUser(alias);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(
                AssigneeId = u.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1].Id
            );
        }
        return u;
    }

    private static User createUser(String alias) {
        String unique = alias + Datetime.now().getTime() + Crypto.getRandomInteger();
        User u = new User(
            FirstName = 'Test',
            LastName = alias,
            Alias = alias,
            Email = unique + '@example.com',
            Username = unique + '@projectemployee.test',
            CommunityNickname = unique.left(40),
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }
}
