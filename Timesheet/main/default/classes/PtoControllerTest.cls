/**
 * @description Tests for the PTO tab: PtoController, PtoData, PtoRequestService, PtoNotifier, LeaveValidator,
 *              LeaveToLineItem and the PTO_Request__c / Leave_Line_Item__c triggers.
 *              Users: an employee (PtoEmp) whose manager is PtoMgr, an unrelated user (PtoOut) and HR (PtoHr).
 *              The employee has a timesheet for the week starting WEEK_START, so approved leave in that week
 *              is written to it.
 */
@isTest
private class PtoControllerTest {

    private static final Date WEEK_START = Date.newInstance(2030, 1, 7);
    private static final Integer YEAR = 2030;
    private static final String PLANNED = 'PTO-Planned';
    private static final String SICK = 'Sick Leave';

    @TestSetup
    static void setupData() {
        User manager = newUser('PtoMgr', null);
        User hr = newUser('PtoHr', null);
        User outsider = newUser('PtoOut', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new List<User>{ manager, hr, outsider };
            User employee = newUser('PtoEmp', manager.Id);
            insert employee;
            assign(manager.Id, new List<String>{ 'Timesheet_User', 'TimeSheet_Manager' });
            assign(employee.Id, new List<String>{ 'Timesheet_User' });
            assign(outsider.Id, new List<String>{ 'Timesheet_User' });
            assign(hr.Id, new List<String>{ 'Timesheet_HR_Admin' });
            grantHrAdminToRunningUser();
        }
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insertEmployeesAndTimesheet(manager.Id, hr.Id, outsider.Id);
        }
    }

    private static void insertEmployeesAndTimesheet(Id managerId, Id hrId, Id outsiderId) {
        Id employeeUserId = user('PtoEmp').Id;
        insert new List<Employee__c>{
            newEmployee('PtoEmp', employeeUserId, managerId),
            newEmployee('PtoMgr', managerId, null),
            newEmployee('PtoOut', outsiderId, null),
            newEmployee('PtoHr', hrId, null)
        };
        insert new Timesheet__c(
            Name = 'PTO test week',
            Employee__c = employee('PtoEmp').Id,
            Start_Date__c = WEEK_START,
            End_Date__c = WEEK_START.addDays(6),
            OwnerId = employeeUserId
        );
    }

    // ---------------------------------------------------------------- context and reads

    @isTest
    static void contextReflectsEachRole() {
        PtoController.Context asEmployee;
        PtoController.Context asManager;
        PtoController.Context asHr;
        Test.startTest();
        System.runAs(user('PtoEmp')) { asEmployee = PtoController.getContext(); }
        System.runAs(user('PtoMgr')) { asManager = PtoController.getContext(); }
        System.runAs(user('PtoHr')) { asHr = PtoController.getContext(); }
        Test.stopTest();

        Assert.areEqual(employee('PtoEmp').Id, asEmployee.employee.id, 'Employee sees their own record');
        Assert.isFalse(asEmployee.canApprove, 'An employee cannot approve');
        Assert.areEqual(0, asEmployee.employees.size(), 'An employee acts only for themselves');
        Assert.isTrue(asManager.isManager, 'Manager permission is detected');
        Assert.areEqual(1, asManager.employees.size(), 'A manager sees their one direct report');
        Assert.areEqual(employee('PtoEmp').Id, asManager.employees[0].id, 'The direct report is listed');
        Assert.isTrue(asHr.isHrAdmin, 'HR permission is detected');
        Assert.isTrue(asHr.employees.size() >= 3, 'HR sees every active employee but themselves');
        for (PtoController.CategoryOption o : asEmployee.categories) {
            Assert.areNotEqual(LeaveValidator.CATEGORY_HOLIDAY, o.value, 'Holiday cannot be requested');
        }
        Assert.areEqual(24, asEmployee.dailyMax, 'Daily maximum comes from the default values');
    }

    @isTest
    static void submittedLeaveShowsInEveryView() {
        Id requestId = submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8), day(1, SICK, 4) }, 'Family trip');

        PtoController.DayRecords days;
        PtoController.PastPage past;
        PtoController.RequestDetail detail;
        PtoController.Overview overview;
        Test.startTest();
        System.runAs(user('PtoEmp')) {
            days = PtoController.getDayRecords(null, WEEK_START, WEEK_START.addDays(6));
            past = PtoController.getPast(null, 0);
            detail = PtoController.getRequestLines(requestId);
            overview = PtoController.getOverview(null, YEAR);
        }
        Test.stopTest();

        Assert.areEqual(2, days.leaves.size(), 'Both leave days are in the range');
        Assert.areEqual(LeaveValidator.STATUS_SUBMITTED, days.leaves[0].status, 'Days wait for approval');
        Assert.areEqual(1, past.rows.size(), 'One request in the history');
        Assert.isFalse(past.hasMore, 'No second page');
        Assert.areEqual(2, past.rows[0].dayCount, 'Request counts its days');
        Assert.areEqual('Family trip', past.rows[0].notes, 'Reason is kept');
        Assert.areEqual(2, detail.lines.size(), 'Detail lists both days');
        Assert.areEqual(LeaveValidator.SYNC_WAITING, detail.lines[0].syncStatus, 'Not on the timesheet before approval');
        Assert.areEqual(12, overview.pendingHours, 'Pending hours add up both days');
        Assert.areEqual(0, overview.takenHours, 'Nothing approved yet');
        Assert.areEqual(1, overview.pendingRequests, 'One pending request');
        Assert.areEqual(String.valueOf(WEEK_START), overview.nextLeaveDate, 'Next leave starts on the first day');
        Assert.areEqual(2, overview.nextLeaveCount, 'Two consecutive days of leave');
        Assert.areEqual(2, overview.nextLeavePendingCount, 'Both still pending');
        Assert.areEqual(2, overview.byCategory.size(), 'One total per category used');
    }

    @isTest
    static void dayRecordsRejectsBadRanges() {
        System.runAs(user('PtoEmp')) {
            Test.startTest();
            try {
                PtoController.getDayRecords(null, WEEK_START, WEEK_START.addDays(-1));
                Assert.fail('Expected an error containing: ' + 'start date');
            } catch (AuraHandledException e) {
                assertMessage(e, 'start date');
            }
            try {
                PtoController.getDayRecords(null, WEEK_START, WEEK_START.addDays(100));
                Assert.fail('Expected an error containing: ' + 'days or fewer');
            } catch (AuraHandledException e) {
                assertMessage(e, 'days or fewer');
            }
            Test.stopTest();
        }
    }

    // ---------------------------------------------------------------- submit validation

    @isTest
    static void submitReportsRowErrorsWithoutSaving() {
        PtoController.SubmitResponse response;
        Test.startTest();
        System.runAs(user('PtoEmp')) {
            response = PtoController.submitLeave(null, JSON.serialize(new List<Map<String, Object>>{
                day(0, LeaveValidator.CATEGORY_HOLIDAY, 8), // not requestable
                day(1, PLANNED, 9),                        // over the category maximum
                day(2, PLANNED, 4),                        // entered twice
                day(2, PLANNED, 4),
                day(3, PLANNED, 0),                        // no hours
                new Map<String, Object>{ 'date' => 'not a date', 'category' => PLANNED, 'hours' => 'x' }
            }), null);
        }
        Test.stopTest();

        Assert.isFalse(response.success, 'Nothing is saved when a row is invalid');
        Assert.isTrue(response.rowErrors[0].contains('can\'t be requested'), response.rowErrors[0]);
        Assert.isTrue(response.rowErrors[1].contains('allows up to 8'), response.rowErrors[1]);
        Assert.isTrue(response.rowErrors[2].contains('more than once'), response.rowErrors[2]);
        Assert.isTrue(response.rowErrors[4].contains('more than 0'), response.rowErrors[4]);
        Assert.isTrue(response.rowErrors[5].contains('Pick a date'), response.rowErrors[5]);
        Assert.areEqual(0, [SELECT COUNT() FROM PTO_Request__c], 'No request created');
    }

    @isTest
    static void submitRejectsDaysAlreadyRequestedOrOverTheDailyLimit() {
        submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8) }, null);
        System.runAs(user('PtoHr')) {
            insert new Timesheet_Line_Item__c(
                Timesheet__c = timesheet().Id,
                Date__c = WEEK_START.addDays(1),
                Type__c = LeaveValidator.LINE_TYPE_ABSENCE,
                Absence_Category__c = SICK,
                Duration__c = 8
            );
        }

        PtoController.SubmitResponse response;
        Test.startTest();
        System.runAs(user('PtoEmp')) {
            response = PtoController.submitLeave(null, JSON.serialize(new List<Map<String, Object>>{
                day(0, PLANNED, 8), // already requested
                day(1, SICK, 8)     // already an absence on the timesheet
            }), null);
        }
        Test.stopTest();

        Assert.isFalse(response.success, 'Duplicates are refused');
        Assert.isTrue(response.rowErrors[0].contains('waiting for approval'), response.rowErrors[0]);
        Assert.isTrue(response.rowErrors[1].contains('already on the timesheet'), response.rowErrors[1]);
    }

    @isTest
    static void submitNeedsDaysAndAShortReason() {
        System.runAs(user('PtoEmp')) {
            Test.startTest();
            try {
                PtoController.submitLeave(null, '[]', null);
                Assert.fail('Expected an error containing: ' + 'at least one day');
            } catch (AuraHandledException e) {
                assertMessage(e, 'at least one day');
            }
            try {
                PtoController.submitLeave(null, JSON.serialize(new List<Map<String, Object>>{ day(0, PLANNED, 8) }),
                'x'.repeat(PtoRequestService.NOTES_MAX + 1));
                Assert.fail('Expected an error containing: ' + '2,000 characters');
            } catch (AuraHandledException e) {
                assertMessage(e, '2,000 characters');
            }
            Test.stopTest();
        }
    }

    @isTest
    static void userWithoutEmployeeRecordIsTold() {
        User noEmployee = newUser('PtoNone', null);
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert noEmployee;
            assign(noEmployee.Id, new List<String>{ 'Timesheet_User' });
        }
        System.runAs(noEmployee) {
            Test.startTest();
            try {
                PtoController.getOverview(null, YEAR);
                Assert.fail('Expected an error containing: ' + 'isn\'t linked to an employee');
            } catch (AuraHandledException e) {
                assertMessage(e, 'isn\'t linked to an employee');
            }
            Test.stopTest();
        }
    }

    // ---------------------------------------------------------------- access rules

    @isTest
    static void managerActsForDirectReportOnly() {
        Id reportId = employee('PtoEmp').Id;
        Id otherId = employee('PtoOut').Id;
        PtoController.SubmitResponse response;
        System.runAs(user('PtoMgr')) {
            Test.startTest();
            response = PtoController.submitLeave(reportId, JSON.serialize(new List<Map<String, Object>>{ day(2, PLANNED, 8) }), null);
            try {
                PtoController.getPast(otherId, 0);
                Assert.fail('Expected an error containing: ' + 'yourself and your direct reports');
            } catch (AuraHandledException e) {
                assertMessage(e, 'yourself and your direct reports');
            }
            try {
                PtoController.getPast(missingEmployeeId(), 0);
                Assert.fail('Expected an error containing: ' + 'doesn\'t exist');
            } catch (AuraHandledException e) {
                assertMessage(e, 'doesn\'t exist');
            }
            Test.stopTest();
        }
        Assert.isTrue(response.success, 'Manager can apply for a direct report: ' + response.rowErrors + response.warnings);
        PTO_Request__c request = [SELECT Employee__c, Approver__c, OwnerId FROM PTO_Request__c WHERE Id = :response.requestId];
        Assert.areEqual(reportId, request.Employee__c, 'Request belongs to the report');
        Assert.areEqual(user('PtoMgr').Id, request.Approver__c, 'Approver is the employee\'s manager');
        Assert.areEqual(user('PtoEmp').Id, request.OwnerId, 'The employee owns the request');
    }

    @isTest
    static void othersCannotSeeOrDecideARequest() {
        Id requestId = submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8) }, null);
        PtoController.ActionResult ownTry;
        System.runAs(user('PtoOut')) {
            Test.startTest();
            try {
                PtoController.getRequestLines(requestId);
                Assert.fail('Expected an error containing: ' + 'only see leave requests');
            } catch (AuraHandledException e) {
                assertMessage(e, 'only see leave requests');
            }
            try {
                PtoController.approveRequests(new List<Id>{ requestId });
                Assert.fail('Expected an error containing: ' + 'Only managers and HR');
            } catch (AuraHandledException e) {
                assertMessage(e, 'Only managers and HR');
            }
            try {
                PtoController.getPendingApprovals();
                Assert.fail('Expected an error containing: ' + 'Only managers and HR');
            } catch (AuraHandledException e) {
                assertMessage(e, 'Only managers and HR');
            }
            try {
                PtoController.getTeamYear(YEAR);
                Assert.fail('Expected an error containing: ' + 'Only managers and HR');
            } catch (AuraHandledException e) {
                assertMessage(e, 'Only managers and HR');
            }
            try {
                PtoController.retrySync(requestId);
                Assert.fail('Expected an error containing: ' + 'Only HR');
            } catch (AuraHandledException e) {
                assertMessage(e, 'Only HR');
            }
            Test.stopTest();
        }
        Assert.areEqual(LeaveValidator.STATUS_SUBMITTED, status(requestId), 'Request is untouched');
    }

    @isTest
    static void hrCannotApproveTheirOwnRequest() {
        PtoController.SubmitResponse submitted;
        PtoController.ActionResult result;
        System.runAs(user('PtoHr')) {
            submitted = PtoController.submitLeave(null, JSON.serialize(new List<Map<String, Object>>{ day(0, PLANNED, 8) }), null);
            Test.startTest();
            result = PtoController.approveRequests(new List<Id>{ submitted.requestId });
            Test.stopTest();
        }
        Assert.isTrue(submitted.success, 'HR can apply for themselves');
        Assert.isTrue(submitted.warnings[0].contains('no manager'), 'No manager is flagged');
        Assert.areEqual(0, result.processed, 'Nobody approves their own leave');
        Assert.isTrue(result.errors[0].contains('can\'t approve'), result.errors[0]);
    }

    // ---------------------------------------------------------------- approve, reject, sync

    @isTest
    static void managerApprovalWritesLeaveToTheTimesheet() {
        Id requestId = submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8), day(1, SICK, 4) }, 'Trip\nsecond line');
        List<PtoController.RequestRow> pending;
        PtoController.ActionResult result;
        PtoController.TeamYear team;
        System.runAs(user('PtoMgr')) {
            pending = PtoController.getPendingApprovals();
            Test.startTest();
            result = PtoController.approveRequests(new List<Id>{ requestId });
            Test.stopTest();
            team = PtoController.getTeamYear(YEAR);
        }

        Assert.areEqual(1, pending.size(), 'Manager sees the report\'s request');
        Assert.areEqual(1, result.processed, 'Request approved: ' + result.errors);
        PTO_Request__c request = [SELECT Status__c, Decided_By__c, Decision_Notes__c FROM PTO_Request__c WHERE Id = :requestId];
        Assert.areEqual(LeaveValidator.STATUS_APPROVED, request.Status__c, 'Status is Approved');
        Assert.areEqual(user('PtoMgr').Id, request.Decided_By__c, 'Decider is stamped');
        Assert.isTrue(request.Decision_Notes__c.startsWith('Approved by'), request.Decision_Notes__c);
        List<Timesheet_Line_Item__c> items = [
            SELECT Absence_Category__c, Duration__c, Description__c FROM Timesheet_Line_Item__c
            WHERE Timesheet__c = :timesheet().Id AND Type__c = :LeaveValidator.LINE_TYPE_ABSENCE ORDER BY Date__c
        ];
        Assert.areEqual(2, items.size(), 'Both days are on the timesheet');
        Assert.areEqual('Trip', items[0].Description__c, 'First line of the reason becomes the description');
        Assert.areEqual(2, [SELECT COUNT() FROM Leave_Line_Item__c WHERE Sync_Status__c = :LeaveValidator.SYNC_DONE], 'Days marked as synced');
        Assert.areEqual(1, team.rows.size(), 'Team chart has the report');
        Assert.areEqual(12, team.rows[0].total, 'Approved hours are totalled');
    }

    @isTest
    static void rejectionNeedsAReasonAndFreesTheDays() {
        Id requestId = submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8) }, null);
        PtoController.ActionResult result;
        PtoController.ActionResult again;
        System.runAs(user('PtoMgr')) {
            Test.startTest();
            try {
                PtoController.rejectRequests(new List<Id>{ requestId }, ' ');
                Assert.fail('Expected an error containing: ' + 'reason');
            } catch (AuraHandledException e) {
                assertMessage(e, 'reason');
            }
            result = PtoController.rejectRequests(new List<Id>{ requestId }, 'Busy week');
            again = PtoController.rejectRequests(new List<Id>{ requestId }, 'Twice');
            Test.stopTest();
        }
        Assert.areEqual(1, result.processed, 'Request rejected: ' + result.errors);
        Assert.isTrue(again.errors[0].contains('no longer waiting'), 'A decided request cannot be decided again');
        PTO_Request__c request = [SELECT Status__c, Decision_Notes__c FROM PTO_Request__c WHERE Id = :requestId];
        Assert.areEqual(LeaveValidator.STATUS_REJECTED, request.Status__c, 'Status is Rejected');
        Assert.isTrue(request.Decision_Notes__c.contains('Busy week'), 'Reason is recorded');
        Assert.areEqual(0, [SELECT COUNT() FROM Leave_Line_Item__c WHERE Unique_Key__c != null], 'Rejected days are released');

        // The same day can be requested again once the first request is rejected
        Id second = submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8) }, null);
        Assert.isNotNull(second, 'Released day can be requested again');
    }

    @isTest
    static void leaveWithoutATimesheetWaitsThenSyncsWhenTheWeekIsCreated() {
        Date nextWeek = WEEK_START.addDays(7);
        Id requestId = submitAsEmployee(new List<Map<String, Object>>{ day(7, PLANNED, 8) }, null);
        PtoController.ActionResult retry;
        Test.startTest();
        System.runAs(user('PtoHr')) {
            PtoController.approveRequests(new List<Id>{ requestId });
            retry = PtoController.retrySync(requestId);
        }
        Assert.areEqual(0, retry.processed, 'No timesheet yet, so nothing to add');
        Assert.areEqual(LeaveValidator.SYNC_WAITING, [SELECT Sync_Status__c FROM Leave_Line_Item__c LIMIT 1].Sync_Status__c,
            'Day waits for its timesheet');

        System.runAs(user('PtoHr')) {
            insert new Timesheet__c(
                Name = 'PTO test next week',
                Employee__c = employee('PtoEmp').Id,
                Start_Date__c = nextWeek,
                End_Date__c = nextWeek.addDays(6)
            );
        }
        Test.stopTest();

        Assert.areEqual(LeaveValidator.SYNC_DONE, [SELECT Sync_Status__c FROM Leave_Line_Item__c LIMIT 1].Sync_Status__c,
            'New timesheet picks up the approved day');
        Assert.areEqual(1, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Date__c = :nextWeek], 'Line item created');
    }

    @isTest
    static void hrRetryResetsAnEditedAbsenceItem() {
        Id requestId = submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 6) }, null);
        System.runAs(user('PtoHr')) {
            PtoController.approveRequests(new List<Id>{ requestId });
        }
        // Someone changes the synced absence item, and the day is flagged for another try
        Timesheet_Line_Item__c item = [SELECT Id FROM Timesheet_Line_Item__c WHERE Date__c = :WEEK_START LIMIT 1];
        Leave_Line_Item__c line = [SELECT Id FROM Leave_Line_Item__c LIMIT 1];
        System.runAs(user('PtoHr')) {
            update new Timesheet_Line_Item__c(Id = item.Id, Duration__c = 5);
            update new Leave_Line_Item__c(Id = line.Id, Sync_Status__c = LeaveValidator.SYNC_ERROR, Sync_Error__c = 'Test');
        }

        PtoController.ActionResult retry;
        System.runAs(user('PtoHr')) {
            Test.startTest();
            retry = PtoController.retrySync(requestId);
            Test.stopTest();
        }
        Assert.areEqual(1, retry.processed, 'Day is on the timesheet after the retry: ' + retry.syncErrors);
        Assert.areEqual(6, [SELECT Duration__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id].Duration__c,
            'Existing absence takes the leave hours again');
    }

    @isTest
    static void retryOnlyForApprovedRequests() {
        Id requestId = submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8) }, null);
        System.runAs(user('PtoHr')) {
            Test.startTest();
            try {
                PtoController.retrySync(requestId);
                Assert.fail('Expected an error containing: ' + 'isn\'t approved');
            } catch (AuraHandledException e) {
                assertMessage(e, 'isn\'t approved');
            }
            try {
                PtoController.retrySync(null);
                Assert.fail('Expected an error containing: ' + 'doesn\'t exist');
            } catch (AuraHandledException e) {
                assertMessage(e, 'doesn\'t exist');
            }
            Test.stopTest();
        }
    }

    // ---------------------------------------------------------------- trigger rules

    @isTest
    static void decisionMadeOutsideTheTabIsStampedAndFinal() {
        Id requestId = submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8) }, null);
        Test.startTest();
        update new PTO_Request__c(Id = requestId, Status__c = LeaveValidator.STATUS_APPROVED);
        PTO_Request__c request = [SELECT Decided_By__c, Decision_Notes__c FROM PTO_Request__c WHERE Id = :requestId];
        Assert.areEqual(UserInfo.getUserId(), request.Decided_By__c, 'Decider stamped by the trigger');

        Database.SaveResult reopen = Database.update(new PTO_Request__c(Id = requestId, Status__c = LeaveValidator.STATUS_SUBMITTED), false);
        Database.SaveResult move = Database.update(new PTO_Request__c(Id = requestId, Employee__c = employee('PtoOut').Id), false);
        Test.stopTest();

        Assert.isFalse(reopen.isSuccess(), 'Approved requests cannot change status');
        Assert.isFalse(move.isSuccess(), 'Requests cannot move to another employee');
    }

    @isTest
    static void rejectedRequestsCannotBeReopened() {
        Id requestId = submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8) }, null);
        update new PTO_Request__c(Id = requestId, Status__c = LeaveValidator.STATUS_REJECTED);
        Test.startTest();
        Database.SaveResult reopen = Database.update(new PTO_Request__c(Id = requestId, Status__c = LeaveValidator.STATUS_SUBMITTED), false);
        Test.stopTest();
        Assert.isFalse(reopen.isSuccess(), 'Rejected requests stay rejected');
        Assert.isTrue(reopen.getErrors()[0].getMessage().contains('can\'t be reopened'), reopen.getErrors()[0].getMessage());
    }

    @isTest
    static void leaveDaysAreFixedOnceSubmitted() {
        Id requestId = submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8) }, null);
        Leave_Line_Item__c line = [SELECT Id FROM Leave_Line_Item__c LIMIT 1];
        Test.startTest();
        Database.SaveResult edit = Database.update(new Leave_Line_Item__c(Id = line.Id, Duration__c = 4), false);
        // An admin without the HR permission: delete access, but pending days are still protected
        User admin = newUser('PtoAdmin', null);
        admin.ProfileId = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1].Id;
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert admin;
        }
        Database.DeleteResult removal;
        System.runAs(admin) {
            removal = Database.delete(line.Id, false);
        }
        update new PTO_Request__c(Id = requestId, Status__c = LeaveValidator.STATUS_APPROVED);
        Database.SaveResult addLater = Database.insert(new Leave_Line_Item__c(
            PTO_Request__c = requestId, Date__c = WEEK_START.addDays(1), Absence_Category__c = PLANNED, Duration__c = 8
        ), false);
        Test.stopTest();

        Assert.isFalse(edit.isSuccess(), 'Days cannot be edited');
        Assert.isFalse(removal.isSuccess(), 'Pending days cannot be deleted');
        Assert.isFalse(addLater.isSuccess(), 'Days cannot be added to a decided request');
    }

    @isTest
    static void manualAbsenceCannotDuplicatePendingLeave() {
        submitAsEmployee(new List<Map<String, Object>>{ day(0, PLANNED, 8) }, null);
        Id timesheetId = timesheet().Id;
        Database.SaveResult result;
        Test.startTest();
        System.runAs(user('PtoHr')) {
            result = Database.insert(new Timesheet_Line_Item__c(
                Timesheet__c = timesheetId,
                Date__c = WEEK_START,
                Type__c = LeaveValidator.LINE_TYPE_ABSENCE,
                Absence_Category__c = PLANNED,
                Duration__c = 8
            ), false);
        }
        Test.stopTest();
        Assert.isFalse(result.isSuccess(), 'Pending leave blocks a manual absence on the same day');
        Assert.isTrue(result.getErrors()[0].getMessage().contains('waiting for approval'), result.getErrors()[0].getMessage());
    }

    @isTest
    static void helpersFormatAndKeyValues() {
        Assert.areEqual('8', LeaveValidator.formatHours(8), 'Whole hours have no decimals');
        Assert.areEqual('7.5', LeaveValidator.formatHours(7.5), 'Trailing zero is dropped');
        Assert.areEqual('0', LeaveValidator.formatHours(null), 'Blank is zero');
        Assert.isNull(LeaveValidator.key(null, WEEK_START, PLANNED), 'No key without an employee');
        Assert.areEqual(8, LeaveValidator.maxHours('Unknown'), 'Unknown category uses the default maximum');
        Assert.areEqual(0, LeaveValidator.validate(null).size(), 'No rows, no errors');
        String longNotes = PtoRequestService.appendNote('x'.repeat(PtoRequestService.NOTES_MAX), 'newest');
        Assert.areEqual(PtoRequestService.NOTES_MAX, longNotes.length(), 'Notes are capped');
        Assert.isTrue(longNotes.endsWith('newest'), 'Newest text is kept');
    }

    // ---------------------------------------------------------------- helpers

    private static Id submitAsEmployee(List<Map<String, Object>> rows, String notes) {
        PtoController.SubmitResponse response;
        System.runAs(user('PtoEmp')) {
            response = PtoController.submitLeave(null, JSON.serialize(rows), notes);
        }
        Assert.isTrue(response.success, 'Submit failed: ' + response.rowErrors + ' ' + response.warnings);
        return response.requestId;
    }

    private static Map<String, Object> day(Integer offset, String category, Decimal hours) {
        return new Map<String, Object>{
            'date' => String.valueOf(WEEK_START.addDays(offset)),
            'category' => category,
            'hours' => hours
        };
    }

    private static void assertMessage(Exception e, String expected) {
        Assert.isTrue(e.getMessage().contains(expected), 'Expected "' + expected + '", got: ' + e.getMessage());
    }

    // An Employee__c Id that matches no record
    private static Id missingEmployeeId() {
        return Id.valueOf(Employee__c.SObjectType.getDescribe().getKeyPrefix() + '000000000000AAA');
    }

    private static String status(Id requestId) {
        return [SELECT Status__c FROM PTO_Request__c WHERE Id = :requestId].Status__c;
    }

    private static User user(String lastName) {
        return [SELECT Id FROM User WHERE LastName = :lastName LIMIT 1];
    }

    private static Employee__c employee(String lastName) {
        return [SELECT Id FROM Employee__c WHERE Last_Name__c = :lastName LIMIT 1];
    }

    private static Timesheet__c timesheet() {
        return [SELECT Id FROM Timesheet__c WHERE Start_Date__c = :WEEK_START LIMIT 1];
    }

    private static User newUser(String lastName, Id managerId) {
        String unique = lastName + Datetime.now().getTime() + Crypto.getRandomInteger();
        return new User(
            FirstName = 'Test',
            LastName = lastName,
            Alias = lastName.left(8),
            Email = unique + '@example.com',
            Username = unique + '@ptotest.example',
            CommunityNickname = unique.left(40),
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            ManagerId = managerId,
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
    }

    // Package build orgs run tests as an admin without the app's permission sets, and the Employee and
    // timesheet triggers refuse users without them. The running user gets Timesheet HR Admin (unless it already has it)
    // for the setup data; the grant doesn't carry into the test methods, so they act as HR test users instead.
    private static void grantHrAdminToRunningUser() {
        Id me = UserInfo.getUserId();
        Id permissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Timesheet_HR_Admin' LIMIT 1].Id;
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :me AND PermissionSetId = :permissionSetId] == 0) {
            insert new PermissionSetAssignment(AssigneeId = me, PermissionSetId = permissionSetId);
        }
    }

    private static void assign(Id userId, List<String> permissionSetNames) {
        List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
        for (PermissionSet ps : [SELECT Id FROM PermissionSet WHERE Name IN :permissionSetNames]) {
            assignments.add(new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = ps.Id));
        }
        insert assignments;
    }

    private static Employee__c newEmployee(String lastName, Id userId, Id managerId) {
        return new Employee__c(
            Name = '-',
            First_Name__c = 'Test',
            Last_Name__c = lastName,
            User__c = userId,
            Manager__c = managerId,
            Email__c = lastName.toLowerCase() + '.pto@example.com',
            Employment_Type__c = 'Full Time',
            Active__c = true
        );
    }
}
