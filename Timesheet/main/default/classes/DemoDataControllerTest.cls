/**
 * @description Test class for DemoDataController
 * @author Ayan
 */
@IsTest
private class DemoDataControllerTest {

    @IsTest
    static void testCreateDemoData() {
        Test.startTest();
        String result = DemoDataController.createDemoData();
        Test.stopTest();

        System.assertEquals('Success', result, 'createDemoData should return Success');

        // Verify Employee created
        List<Employee__c> emps = [
            SELECT Id, First_Name__c, Last_Name__c, Accrual_Start_Date__c, Accrual_Divisor__c, Extra_Accrued_Hours__c 
            FROM Employee__c 
            WHERE User__c = :UserInfo.getUserId()
        ];
        System.assertEquals(1, emps.size(), 'Should create exactly 1 employee');
        System.assertEquals('Test', emps[0].First_Name__c);
        System.assertEquals('T.', emps[0].Last_Name__c);
        System.assertEquals(System.today().addMonths(-1), emps[0].Accrual_Start_Date__c);
        System.assertEquals(8, emps[0].Accrual_Divisor__c);
        System.assertEquals(30, emps[0].Extra_Accrued_Hours__c);

        // Verify Projects created
        List<Project__c> projs = [
            SELECT Id, Name, Active__c, Billable__c 
            FROM Project__c 
            WHERE Name IN ('Demo Project - Billable', 'Demo Project - Non-Billable', 'Demo Project - Legacy')
        ];
        System.assertEquals(3, projs.size(), 'Should create 3 demo projects');

        // Verify Project Employee assignments
        List<Project_Employee__c> pes = [
            SELECT Id 
            FROM Project_Employee__c 
            WHERE Employee__c = :emps[0].Id
        ];
        System.assertEquals(3, pes.size(), 'Should assign 3 projects to the employee');

        // Verify Timesheets created
        List<Timesheet__c> tsList = [
            SELECT Id, Start_Date__c, Status__c, Manager__c
            FROM Timesheet__c 
            WHERE Employee__c = :emps[0].Id 
            ORDER BY Start_Date__c ASC
        ];
        System.assertEquals(4, tsList.size(), 'Should create 4 timesheets');
        System.assertEquals('Approved', tsList[0].Status__c, 'Last last week timesheet should be Approved');
        System.assertEquals('Approved', tsList[1].Status__c, 'Last week timesheet should be Approved');
        System.assertEquals('Submitted', tsList[2].Status__c, 'Current week timesheet should be submitted for approval');
        System.assertEquals('New', tsList[3].Status__c, 'Next week timesheet should be New');
        for (Timesheet__c ts : tsList) {
            System.assertEquals(emps[0].Manager__c, ts.Manager__c, 'Each demo timesheet should inherit the employee manager');
        }
    }

    @IsTest
    static void testCreateDemoDataRequiresUserManager() {
        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User noManagerUser = new User(
            FirstName = 'No',
            LastName = 'Manager',
            Alias = 'nmgr',
            Email = 'no.manager.' + Datetime.now().getTime() + '@example.com',
            Username = 'no.manager.' + Datetime.now().getTime() + '@example.com',
            CommunityNickname = 'noManager',
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US',
            ProfileId = p.Id
        );
        insert noManagerUser;

        PermissionSet ps = [SELECT Id FROM PermissionSet WHERE Name = 'Timesheet_HR_Admin' LIMIT 1];
        insert new PermissionSetAssignment(AssigneeId = noManagerUser.Id, PermissionSetId = ps.Id);

        System.runAs(noManagerUser) {
            try {
                DemoDataController.createDemoData();
                System.assert(false, 'Expected createDemoData to throw when current user has no manager');
            } catch (AuraHandledException e) {
                System.assertEquals('Please assign a manager in your User record before creating demo data.', e.getMessage());
            }
        }
    }

    @IsTest
    static void testDemoDataManagement() {
        // Test status when no employee exists
        Map<String, Object> statusBefore = DemoDataController.getDemoStatus();
        System.assertEquals(false, statusBefore.get('hasEmployee'));
        System.assertEquals(false, statusBefore.get('isTestEmployee'));

        // Test records when empty
        List<DemoDataController.DemoRecordDetail> emptyRecords = DemoDataController.getDemoRecords();
        System.assertEquals(0, emptyRecords.size());

        // Create demo data
        DemoDataController.createDemoData();

        // Check status after creation
        Map<String, Object> statusAfter = DemoDataController.getDemoStatus();
        System.assertEquals(true, statusAfter.get('hasEmployee'));
        System.assertEquals(true, statusAfter.get('isTestEmployee'));
        System.assertEquals('Test T.', statusAfter.get('employeeName'));

        // Check records after creation
        List<DemoDataController.DemoRecordDetail> createdRecords = DemoDataController.getDemoRecords();
        System.assert(createdRecords.size() >= 8, 'Should return records for employee, projects, assignments, and timesheets');

        // Delete test records
        String deleteRes = DemoDataController.deleteTestRecords();
        System.assertEquals('Success', deleteRes);

        // Check status after deletion
        Map<String, Object> statusDeleted = DemoDataController.getDemoStatus();
        System.assertEquals(false, statusDeleted.get('hasEmployee'));
        System.assertEquals(0, [SELECT count() FROM Timesheet__c WHERE OwnerId = :UserInfo.getUserId()], 'All timesheets should be deleted');
        System.assertEquals(0, [SELECT count() FROM Timesheet_Line_Item__c], 'All timesheet line items should be deleted');
        System.assertEquals(0, [SELECT count() FROM Project_Employee__c], 'All project employees should be deleted');
    }
}
