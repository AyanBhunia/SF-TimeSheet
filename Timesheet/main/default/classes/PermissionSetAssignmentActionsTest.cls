/**
 * @description Tests for GetPermissionSetAssignments and SavePermissionSetAssignments, the invocable
 *              actions used by the "In-app Guidence using STF" flow.
 *              Users: Psa1 and Psa2 already have Timesheet_Reminder_Access, Psa3 does not.
 */
@isTest
private class PermissionSetAssignmentActionsTest {

    @TestSetup
    static void setupData() {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ newUser('Psa1'), newUser('Psa2'), newUser('Psa3') };
            insert new List<PermissionSetAssignment>{
                newAssignment(user('Psa1').Id, Datetime.now().addDays(1)),
                newAssignment(user('Psa2').Id, Datetime.now().addDays(1))
            };
        }
    }

    @isTest
    static void getReturnsOnlyRequestedUsers() {
        GetPermissionSetAssignments.Request request = new GetPermissionSetAssignments.Request();
        request.permissionSetId = reminderPermissionSetId();
        request.userIds = new List<String>{ user('Psa1').Id, user('Psa3').Id };

        Test.startTest();
        List<GetPermissionSetAssignments.Response> responses =
            GetPermissionSetAssignments.getAssignments(new List<GetPermissionSetAssignments.Request>{ request });
        Test.stopTest();

        Assert.areEqual(1, responses.size(), 'One response per request');
        Assert.areEqual(1, responses[0].assignments.size(), 'Only Psa1 has an assignment; Psa2 was not requested');
        Assert.areEqual(user('Psa1').Id, responses[0].assignments[0].AssigneeId, 'Psa1 assignment returned');
    }

    @isTest
    static void getHandlesMissingInput() {
        GetPermissionSetAssignments.Request empty = new GetPermissionSetAssignments.Request();
        empty.permissionSetId = reminderPermissionSetId();
        empty.userIds = new List<String>();
        GetPermissionSetAssignments.Request noInput = new GetPermissionSetAssignments.Request();

        List<GetPermissionSetAssignments.Response> responses =
            GetPermissionSetAssignments.getAssignments(new List<GetPermissionSetAssignments.Request>{ empty, noInput });

        Assert.areEqual(2, responses.size(), 'One response per request');
        Assert.isTrue(responses[0].assignments.isEmpty(), 'No users, no assignments');
        Assert.isTrue(responses[1].assignments.isEmpty(), 'Null input, no assignments');
    }

    @isTest
    static void saveIsPartial() {
        Id psId = reminderPermissionSetId();
        Datetime expiry = Datetime.now().addDays(3);
        PermissionSetAssignment existing = [
            SELECT Id FROM PermissionSetAssignment WHERE AssigneeId = :user('Psa2').Id AND PermissionSetId = :psId
        ];
        SavePermissionSetAssignments.Request request = new SavePermissionSetAssignments.Request();
        // Psa1 already has the permission set, so its insert fails with DUPLICATE_VALUE; Psa3 must still be saved.
        request.toInsert = new List<PermissionSetAssignment>{
            newAssignment(user('Psa1').Id, expiry),
            newAssignment(user('Psa3').Id, expiry)
        };
        request.toUpdate = new List<PermissionSetAssignment>{
            new PermissionSetAssignment(Id = existing.Id, ExpirationDate = expiry)
        };

        Test.startTest();
        List<SavePermissionSetAssignments.Response> responses =
            SavePermissionSetAssignments.save(new List<SavePermissionSetAssignments.Request>{ request });
        Test.stopTest();

        SavePermissionSetAssignments.Response response = responses[0];
        Assert.areEqual(1, response.inserted, 'Psa3 inserted');
        Assert.areEqual(1, response.updated, 'Psa2 updated');
        Assert.areEqual(1, response.failed, 'Psa1 duplicate failed alone');
        Assert.isTrue(response.errors.contains('DUPLICATE_VALUE'), 'Failure reason reported: ' + response.errors);
        Assert.areEqual(1, [SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :user('Psa3').Id AND PermissionSetId = :psId], 'Psa3 has the permission set');
        Datetime saved = [SELECT ExpirationDate FROM PermissionSetAssignment WHERE Id = :existing.Id].ExpirationDate;
        Assert.isTrue(saved > Datetime.now().addDays(2), 'Psa2 expiry extended');
    }

    @isTest
    static void saveHandlesEmptyLists() {
        SavePermissionSetAssignments.Response response =
            SavePermissionSetAssignments.save(new List<SavePermissionSetAssignments.Request>{ new SavePermissionSetAssignments.Request() })[0];

        Assert.areEqual(0, response.inserted + response.updated + response.failed, 'Nothing to save');
        Assert.areEqual('', response.errors, 'No errors');
    }

    private static Id reminderPermissionSetId() {
        return [SELECT Id FROM PermissionSet WHERE Name = 'Timesheet_Reminder_Access' LIMIT 1].Id;
    }

    private static PermissionSetAssignment newAssignment(Id userId, Datetime expiry) {
        return new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = reminderPermissionSetId(), ExpirationDate = expiry);
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName AND Username LIKE '%@psatest.example' LIMIT 1];
    }

    private static User newUser(String lastName) {
        String unique = lastName + Datetime.now().getTime() + Crypto.getRandomInteger();
        return new User(
            FirstName = 'Test',
            LastName = lastName,
            Alias = lastName.left(8),
            Email = unique + '@example.com',
            Username = unique + '@psatest.example',
            CommunityNickname = unique.left(40),
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }
}
