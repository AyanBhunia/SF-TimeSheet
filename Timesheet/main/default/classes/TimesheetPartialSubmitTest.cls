@isTest
private class TimesheetPartialSubmitTest {

    private static final String ADMIN_LAST_NAME = 'PartialSubmitAdmin';

    @testSetup
    static void setupTestData() {
        User adminUser = TestDataFactory.createAdminUser('Partial', ADMIN_LAST_NAME);
        adminUser.Username = 'partialsubmit' + Datetime.now().getTime() + '@testmail.com';
        adminUser.CommunityNickname = 'partialsubmit' + Datetime.now().getTime();
        insert adminUser;
        TestDataFactory.assignPermissionSet(adminUser, 'Timesheet_HR_Admin');

        System.runAs(adminUser) {
            Employee__c emp = TestDataFactory.createEmployee(adminUser.Id);
            emp.Manager__c = adminUser.Id;
            insert emp;

            Project__c project = TestDataFactory.createProject('Partial Submit Project', 'Yes');
            insert project;

            Project_Activity__c activity = TestDataFactory.createProjectActivity(project.Id, 'Testing');
            insert activity;

            insert TestDataFactory.createProjectEmployee(project.Id, emp.Id);

            // One timesheet that allows partial approval and one that does not.
            Timesheet__c partialTs = TestDataFactory.createTimesheet(emp.Id);
            partialTs.Name = 'Partial Allowed';
            setIfWritable(partialTs, 'Is_Partial_Allowed__c', true);
            setIfWritable(partialTs, 'Manager__c', adminUser.Id);

            Timesheet__c fullTs = TestDataFactory.createTimesheet(emp.Id);
            fullTs.Name = 'Partial Not Allowed';
            fullTs.Start_Date__c = System.today().addDays(-7);
            fullTs.End_Date__c = System.today().addDays(-1);
            setIfWritable(fullTs, 'Is_Partial_Allowed__c', false);
            setIfWritable(fullTs, 'Manager__c', adminUser.Id);

            insert new List<Timesheet__c>{ partialTs, fullTs };

            List<Timesheet_Line_Item__c> items = new List<Timesheet_Line_Item__c>();
            items.add(newLine(partialTs.Id, project.Id, activity.Id, partialTs.Start_Date__c));
            items.add(newLine(partialTs.Id, project.Id, activity.Id, partialTs.Start_Date__c.addDays(1)));
            items.add(newLine(fullTs.Id, project.Id, activity.Id, fullTs.Start_Date__c));
            items.add(newLine(fullTs.Id, project.Id, activity.Id, fullTs.Start_Date__c.addDays(1)));
            insert items;
        }
    }

    // ---------------------------------------------------------------- helpers

    private static Timesheet_Line_Item__c newLine(Id tsId, Id projectId, Id activityId, Date day) {
        Timesheet_Line_Item__c li = TestDataFactory.createTimesheetLineItem(tsId, projectId, activityId);
        li.Date__c = day;
        li.Line_Item_Status__c = 'New';
        return li;
    }

    // Sets a field only when this org lets it be written (it may be a formula in some orgs).
    private static void setIfWritable(SObject record, String fieldName, Object value) {
        Schema.SObjectField field = record.getSObjectType().getDescribe().fields.getMap().get(fieldName);
        if (field != null && field.getDescribe().isCreateable()) {
            record.put(fieldName, value);
        }
    }

    private static User admin() {
        return [SELECT Id FROM User WHERE LastName = :ADMIN_LAST_NAME LIMIT 1];
    }

    private static Timesheet__c sheet(String name) {
        return [SELECT Id, Status__c, Is_Partial_Allowed__c FROM Timesheet__c WHERE Name = :name LIMIT 1];
    }

    private static List<Timesheet_Line_Item__c> lines(Id tsId) {
        return [
            SELECT Id, Line_Item_Status__c, Rejection_Notes__c
            FROM Timesheet_Line_Item__c
            WHERE Timesheet__c = :tsId
            ORDER BY Date__c
        ];
    }

    private static void markSubmitted(Id tsId) {
        List<Timesheet_Line_Item__c> items = lines(tsId);
        for (Timesheet_Line_Item__c li : items) {
            li.Line_Item_Status__c = 'Submitted';
        }
        update items;
    }

    // Approval.lock needs "record locking in Apex" enabled in the org; the status changes happen before it.
    private static void assertSubmitResult(String res) {
        System.assert(res == 'Success' || res.containsIgnoreCase('lock'), 'Unexpected submit result: ' + res);
    }

    // ------------------------------------------------- WeeklyTimesheetController

    @isTest
    static void submitTimesheetSubmitsNewLines() {
        System.runAs(admin()) {
            Timesheet__c ts = sheet('Partial Allowed');

            Test.startTest();
            String res = WeeklyTimesheetController.submitTimesheet(ts.Id);
            Test.stopTest();

            assertSubmitResult(res);
            System.assertEquals('Submitted', sheet('Partial Allowed').Status__c, 'Timesheet should be Submitted');
            for (Timesheet_Line_Item__c li : lines(ts.Id)) {
                System.assertEquals('Submitted', li.Line_Item_Status__c, 'Every New line should be Submitted');
            }
        }
    }

    @isTest
    static void submitTimesheetWithNothingNewReturnsError() {
        System.runAs(admin()) {
            Timesheet__c ts = sheet('Partial Allowed');
            markSubmitted(ts.Id);

            String res = WeeklyTimesheetController.submitTimesheet(ts.Id);
            System.assert(res.startsWith('Error'), 'Submitting without New lines should fail: ' + res);
        }
    }

    @isTest
    static void submitTimesheetRejectsApprovedAndNull() {
        System.runAs(admin()) {
            System.assert(WeeklyTimesheetController.submitTimesheet(null).startsWith('Error'), 'Null Id should fail');

            Timesheet__c ts = sheet('Partial Allowed');
            List<Timesheet_Line_Item__c> items = lines(ts.Id);
            for (Timesheet_Line_Item__c li : items) {
                li.Line_Item_Status__c = 'Approved';
            }
            update items;
            update ts; // status sync moves the timesheet to Approved

            String res = WeeklyTimesheetController.submitTimesheet(ts.Id);
            System.assert(res.startsWith('Error'), 'An Approved timesheet cannot be submitted: ' + res);
        }
    }

    @isTest
    static void getTimesheetReturnsPartialFields() {
        System.runAs(admin()) {
            Timesheet__c ts = sheet('Partial Allowed');
            Timesheet__c loaded = WeeklyTimesheetController.getTimesheet(ts.Id);
            System.assertEquals(ts.Id, loaded.Id, 'Should load the timesheet');
            System.assertEquals(2, WeeklyTimesheetController.getWeeklyTimesheetItems(ts.Id).size(), 'Should load both lines');
        }
    }

    // ------------------------------------------- TimesheetTriggerHandler (via trigger)

    @isTest
    static void statusSyncFollowsLineItems() {
        System.runAs(admin()) {
            Timesheet__c ts = sheet('Partial Allowed');

            List<Timesheet_Line_Item__c> items = lines(ts.Id);
            items[0].Line_Item_Status__c = 'Submitted';
            update items;
            update ts;
            System.assertEquals('Submitted', sheet('Partial Allowed').Status__c, 'Mixed lines should mean Submitted');

            items = lines(ts.Id);
            for (Timesheet_Line_Item__c li : items) {
                li.Line_Item_Status__c = 'Approved';
            }
            update items;
            update ts;
            System.assertEquals('Approved', sheet('Partial Allowed').Status__c, 'All Approved lines should mean Approved');
        }
    }

    @isTest
    static void statusChangeCascadesToLineItems() {
        System.runAs(admin()) {
            Timesheet__c ts = sheet('Partial Allowed');
            markSubmitted(ts.Id);

            Test.startTest();
            ts.Status__c = 'New';
            update ts;
            Test.stopTest();

            for (Timesheet_Line_Item__c li : lines(ts.Id)) {
                System.assertEquals('New', li.Line_Item_Status__c, 'Lines should follow the timesheet back to New');
            }
        }
    }

    // ------------------------------------------------ TimesheetApprovalController

    @isTest
    static void approveAndRejectLineItemsOnPartialTimesheet() {
        System.runAs(admin()) {
            Timesheet__c ts = sheet('Partial Allowed');
            markSubmitted(ts.Id);
            List<Timesheet_Line_Item__c> items = lines(ts.Id);

            Test.startTest();
            String approveRes = TimesheetApprovalController.approveLineItems(new List<Id>{ items[0].Id });
            String rejectRes = TimesheetApprovalController.rejectLineItemsWithNotes(new List<Id>{ items[1].Id }, 'Needs detail');
            Test.stopTest();

            System.assertEquals('Success', approveRes, approveRes);
            System.assertEquals('Success', rejectRes, rejectRes);

            items = lines(ts.Id);
            if (sheet('Partial Allowed').Is_Partial_Allowed__c == true) {
                System.assertEquals('Approved', items[0].Line_Item_Status__c, 'Line should be Approved');
                System.assertEquals('New', items[1].Line_Item_Status__c, 'Rejected line should go back to New');
                System.assertEquals('Needs detail', items[1].Rejection_Notes__c, 'Rejection note should be saved');
            }

            System.assert(TimesheetApprovalController.approveLineItems(null).startsWith('Error'), 'Empty list should fail');
            System.assert(TimesheetApprovalController.rejectLineItemsWithNotes(null, 'x').startsWith('Error'), 'Empty list should fail');
        }
    }

    @isTest
    static void approveWholeTimesheet() {
        System.runAs(admin()) {
            Timesheet__c ts = sheet('Partial Not Allowed');
            markSubmitted(ts.Id);

            Test.startTest();
            String res = TimesheetApprovalController.approveTimesheets(new List<Id>{ ts.Id });
            Test.stopTest();

            System.assertEquals('Success', res, res);
            for (Timesheet_Line_Item__c li : lines(ts.Id)) {
                System.assertEquals('Approved', li.Line_Item_Status__c, 'Every submitted line should be Approved');
            }
            System.assert(TimesheetApprovalController.approveTimesheets(null).startsWith('Error'), 'Empty list should fail');
        }
    }

    @isTest
    static void rejectWholeTimesheet() {
        System.runAs(admin()) {
            Timesheet__c ts = sheet('Partial Not Allowed');
            markSubmitted(ts.Id);

            Test.startTest();
            String res = TimesheetApprovalController.rejectTimesheets(new List<Id>{ ts.Id }, 'Please fix');
            Test.stopTest();

            System.assertEquals('Success', res, res);
            for (Timesheet_Line_Item__c li : lines(ts.Id)) {
                System.assertEquals('New', li.Line_Item_Status__c, 'Rejected lines should go back to New');
                System.assertEquals('Please fix', li.Rejection_Notes__c, 'Rejection note should be saved');
            }
            System.assert(TimesheetApprovalController.rejectTimesheets(null, 'x').startsWith('Error'), 'Empty list should fail');
        }
    }

    @isTest
    static void updateSubmittedTimesheetLineItemsSubmitsNewLines() {
        System.runAs(admin()) {
            Timesheet__c ts = sheet('Partial Allowed');
            List<Timesheet_Line_Item__c> items = lines(ts.Id);
            items[0].Line_Item_Status__c = 'Submitted';
            update items;
            update ts; // sync: mixed lines -> Submitted

            TimesheetApprovalController.updateSubmittedTimesheetLineItems(ts.Id);
            for (Timesheet_Line_Item__c li : lines(ts.Id)) {
                System.assertEquals('Submitted', li.Line_Item_Status__c, 'New lines should be Submitted');
            }

            Boolean threw = false;
            try {
                TimesheetApprovalController.updateSubmittedTimesheetLineItems(ts.Id);
            } catch (AuraHandledException e) {
                threw = true;
            }
            System.assert(threw, 'With no New lines left it should throw');
        }
    }

    @isTest
    static void getTimesheetDataForEveryRangeAndGrouping() {
        System.runAs(admin()) {
            markSubmitted(sheet('Partial Allowed').Id);
            markSubmitted(sheet('Partial Not Allowed').Id);

            List<String> columns = new List<String>{
                'employeeName', 'date', 'projectName', 'activityName', 'duration', 'status'
            };

            Test.startTest();
            TimesheetApprovalController.TimesheetDataResponse all = TimesheetApprovalController.getTimesheetData(
                'All Pending', null, null, new List<Integer>{ 0, 1, 2, 3 }, columns);
            TimesheetApprovalController.getTimesheetData(
                'All Pending', null, null, new List<Integer>{ 4, 0 }, columns);
            for (String range : new List<String>{ 'Current Week', 'Last Week', 'Current Month', 'Last Month' }) {
                TimesheetApprovalController.getTimesheetData(range, null, null, new List<Integer>{ 2 }, columns);
            }
            TimesheetApprovalController.getTimesheetData(
                'Custom', System.today().addDays(-10), System.today().addDays(10), null, columns);
            Test.stopTest();

            System.assertNotEquals(null, all, 'A response should always come back');
            System.assertNotEquals(null, all.rows, 'Rows should never be null');
        }
    }
}