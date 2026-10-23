@isTest
private class TimesheetTimerControllerTest {

    private static final String ACTIVITY = 'Development-Coding';

    @testSetup
    static void setupTestData() {
        Employee__c emp = new Employee__c(
            First_Name__c = 'Test',
            Last_Name__c = 'User',
            User__c = UserInfo.getUserId(),
            Employment_Type__c = 'Full Time',
            Active__c = true
        );
        insert emp;

        Project__c proj = new Project__c(Name = 'Test Project', Active__c = true, Billable__c = 'Yes');
        insert proj;

        insert new Project_Employee__c(Project__c = proj.Id, Employee__c = emp.Id);

        // The weekly flow normally creates this; the timer only attaches to it.
        insert newTimesheet(emp.Id);
    }

    private static Timesheet__c newTimesheet(Id employeeId) {
        Date startDate = Date.today().addDays(-3);
        Date endDate = Date.today().addDays(3);
        return new Timesheet__c(
            Name = 'Timesheet for ' + startDate + ' to ' + endDate,
            Employee__c = employeeId,
            Start_Date__c = startDate,
            End_Date__c = endDate,
            OwnerId = UserInfo.getUserId()
        );
    }

    private static Employee__c employee() {
        return [SELECT Id FROM Employee__c WHERE User__c = :UserInfo.getUserId() LIMIT 1];
    }

    private static Project__c project() {
        return [SELECT Id FROM Project__c LIMIT 1];
    }

    private static Timesheet__c timesheet() {
        return [SELECT Id FROM Timesheet__c WHERE Employee__c = :employee().Id LIMIT 1];
    }

    private static Id start() {
        return (Id) TimesheetTimerController.startTimer(project().Id, ACTIVITY).get('id');
    }

    private static Long at(Date day, Integer hour, Integer minute) {
        return Datetime.newInstance(day, Time.newInstance(hour, minute, 0, 0)).getTime();
    }

    // Puts a timer into a known state so the hour maths is exact.
    private static void setState(Id lineItemId, Long startMs, Long pausedMs, Long pauseStartMs, Boolean newItem) {
        TimesheetTimerController.TimerState state = new TimesheetTimerController.TimerState();
        state.startMs = startMs;
        state.pausedMs = pausedMs;
        state.pauseStartMs = pauseStartMs;
        state.newItem = newItem;
        update new Timesheet_Line_Item__c(Id = lineItemId, Timer_Data__c = JSON.serialize(state));
    }

    private static Timesheet_Line_Item__c row(Id lineItemId) {
        return [SELECT Duration__c, Timer_Data__c, Description__c FROM Timesheet_Line_Item__c WHERE Id = :lineItemId];
    }

    private static Map<String, Object> activeTimer() {
        return (Map<String, Object>) TimesheetTimerController.getTimerInitData().get('activeTimer');
    }

    private static void assertFails(String expected, Exception e) {
        Assert.isTrue(e.getMessage().contains(expected), 'Unexpected message: ' + e.getMessage());
    }

    @isTest
    static void initListsProjectsWithoutTimer() {
        Map<String, Object> result = TimesheetTimerController.getTimerInitData();

        Assert.areEqual(employee().Id, result.get('employeeId'));
        List<Map<String, Object>> projects = (List<Map<String, Object>>) result.get('projects');
        Assert.areEqual(1, projects.size());
        Assert.areEqual('Test Project', projects[0].get('label'));
        Assert.isNull(result.get('activeTimer'));
    }

    @isTest
    static void startCreatesZeroHourRowAndInitReturnsIt() {
        Test.startTest();
        Id lineItemId = start();
        Map<String, Object> timer = (Map<String, Object>) TimesheetTimerController.getTimerInitData().get('activeTimer');
        Test.stopTest();

        Timesheet_Line_Item__c item = row(lineItemId);
        Assert.areEqual(0, item.Duration__c.intValue(), 'A new timer row starts at 0 hours, not the field default');
        Assert.isNotNull(item.Timer_Data__c, 'Timer state is stored on the row');
        Assert.areEqual(lineItemId, timer.get('id'));
        Assert.areEqual(ACTIVITY, timer.get('activity'));
        Assert.isNull(timer.get('pauseStartMs'), 'A started timer is running');
    }

    @isTest
    static void startReusesExistingRow() {
        Timesheet_Line_Item__c existing = new Timesheet_Line_Item__c(
            Timesheet__c = timesheet().Id, Project__c = project().Id, Activity__c = ACTIVITY,
            Type__c = 'Attendance', Date__c = Date.today(), Duration__c = 2
        );
        insert existing;

        Test.startTest();
        Id lineItemId = start();
        Test.stopTest();

        Assert.areEqual(existing.Id, lineItemId, 'The timer runs on the existing row');
        Assert.areEqual(1, [SELECT COUNT() FROM Timesheet_Line_Item__c], 'No second row is created');
        Assert.areEqual(2, row(lineItemId).Duration__c.intValue(), 'Hours are untouched until save');
    }

    @isTest
    static void pauseContinueAndSaveAddsWorkedHours() {
        Id lineItemId = start();

        Test.startTest();
        Map<String, Object> paused = TimesheetTimerController.pauseTimer(lineItemId);
        Map<String, Object> resumed = TimesheetTimerController.continueTimer(lineItemId);
        // 09:00 start, 30 minutes of breaks, paused at 10:30 -> 1 worked hour.
        setState(lineItemId, at(Date.today(), 9, 0), 30L * 60 * 1000, at(Date.today(), 10, 30), true);
        TimesheetTimerController.saveTimer(lineItemId, 'Built the timer');
        Test.stopTest();

        Assert.isNotNull(paused.get('pauseStartMs'), 'Pause records when it started');
        Assert.isNull(resumed.get('pauseStartMs'), 'Continue clears the pause');
        Timesheet_Line_Item__c item = row(lineItemId);
        Assert.areEqual(1.00, item.Duration__c.setScale(2));
        Assert.isNull(item.Timer_Data__c, 'Saving stops the timer');
        Assert.areEqual('Built the timer', item.Description__c);
    }

    @isTest
    static void saveAcrossMidnightKeepsAllHoursOnStartRow() {
        Date yesterday = Date.today().addDays(-1);
        Timesheet_Line_Item__c item = new Timesheet_Line_Item__c(
            Timesheet__c = timesheet().Id, Project__c = project().Id, Activity__c = ACTIVITY,
            Type__c = 'Attendance', Date__c = yesterday, Duration__c = 0
        );
        insert item;
        // 22:00 yesterday until a pause at 01:00 today.
        setState(item.Id, at(yesterday, 22, 0), 0, at(Date.today(), 1, 0), true);

        Test.startTest();
        TimesheetTimerController.saveTimer(item.Id, 'Late night');
        Test.stopTest();

        Assert.areEqual(3.00, row(item.Id).Duration__c.setScale(2), 'All hours go on the start day row');
        Assert.areEqual(0, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Date__c = :Date.today()], 'No row is created for the next day');
    }

    @isTest
    static void clockStartsFromExistingHoursAndSaveAddsToEditedHours() {
        Timesheet_Line_Item__c existing = new Timesheet_Line_Item__c(
            Timesheet__c = timesheet().Id, Project__c = project().Id, Activity__c = ACTIVITY,
            Type__c = 'Attendance', Date__c = Date.today(), Duration__c = 5
        );
        insert existing;

        Test.startTest();
        Map<String, Object> started = TimesheetTimerController.startTimer(project().Id, ACTIVITY);
        // Someone edits the hours while the timer runs; the timer then ran one hour.
        update new Timesheet_Line_Item__c(Id = existing.Id, Duration__c = 6);
        Map<String, Object> reloaded = activeTimer();
        setState(existing.Id, at(Date.today(), 9, 0), 0, at(Date.today(), 10, 0), false);
        TimesheetTimerController.saveTimer(existing.Id, null);
        Test.stopTest();

        Assert.areEqual(5, ((Decimal) started.get('baseHours')).intValue(), 'The clock starts from the saved hours');
        Assert.areEqual(6, ((Decimal) reloaded.get('baseHours')).intValue(), 'A manual edit shows on the next load');
        Assert.areEqual(7.00, row(existing.Id).Duration__c.setScale(2), 'Save adds to the current hours');
    }

    @isTest
    static void stopsByItselfAtWorkdayHoursAndContinuesToCap() {
        Id lineItemId = start();
        Decimal workday = (Decimal) activeTimer().get('workdayHours');
        Decimal cap = (Decimal) activeTimer().get('capHours');
        Long nowMs = Datetime.now().getTime();
        Long startMs = nowMs - ((workday + 1) * 3600000).longValue();
        setState(lineItemId, startMs, 0, null, true);

        Test.startTest();
        Map<String, Object> stopped = activeTimer();
        Map<String, Object> resumed = TimesheetTimerController.continueTimer(lineItemId);
        Test.stopTest();

        Assert.isTrue((Boolean) stopped.get('autoStopped'), 'The timer stops by itself');
        Assert.areEqual(startMs + (workday * 3600000).longValue(), (Long) stopped.get('pauseStartMs'), 'It stops when the workday hours were reached, not when it was looked at');
        Assert.isNull(resumed.get('pauseStartMs'), 'It can be continued');
        Assert.areEqual(cap, (Decimal) resumed.get('limitHours'), 'After the workday hours it runs up to the daily maximum');
        Assert.isFalse((Boolean) resumed.get('autoStopped'));

        TimesheetTimerController.saveTimer(lineItemId, null);
        Assert.areEqual(workday.setScale(2), row(lineItemId).Duration__c.setScale(2), 'Save counts only up to the stop');
    }

    @isTest
    static void cannotStartOrContinueAtDailyMaximum() {
        Id lineItemId = start();
        Decimal cap = (Decimal) activeTimer().get('capHours');
        Long nowMs = Datetime.now().getTime();
        TimesheetTimerController.TimerState state = new TimesheetTimerController.TimerState();
        state.startMs = nowMs - ((cap + 1) * 3600000).longValue();
        state.pausedMs = 0;
        state.newItem = true;
        state.limitHours = cap;
        update new Timesheet_Line_Item__c(Id = lineItemId, Timer_Data__c = JSON.serialize(state));

        Test.startTest();
        Map<String, Object> stopped = activeTimer();
        try {
            TimesheetTimerController.continueTimer(lineItemId);
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            assertFails('most allowed', e);
        }
        TimesheetTimerController.discardTimer(lineItemId);
        insert new Timesheet_Line_Item__c(
            Timesheet__c = timesheet().Id, Project__c = project().Id, Activity__c = ACTIVITY,
            Type__c = 'Attendance', Date__c = Date.today(), Duration__c = cap
        );
        try {
            start();
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            assertFails('most allowed', e);
        }
        Test.stopTest();

        Assert.isTrue((Boolean) stopped.get('autoStopped'), 'The timer stops at the daily maximum');
    }

    @isTest
    static void editingHoursWhileRunningKeepsWorkedTime() {
        Id lineItemId = start();
        Long nowMs = Datetime.now().getTime();
        // Ran for 2 hours from a 0-hour row, then someone puts 9 hours on the row.
        TimesheetTimerController.TimerState state = new TimesheetTimerController.TimerState();
        state.startMs = nowMs - 2L * 3600000;
        state.pausedMs = 0;
        state.newItem = true;
        state.limitHours = 8;
        state.limitBase = 0;
        update new Timesheet_Line_Item__c(Id = lineItemId, Timer_Data__c = JSON.serialize(state));
        update new Timesheet_Line_Item__c(Id = lineItemId, Duration__c = 9);

        Test.startTest();
        Map<String, Object> timer = activeTimer();
        TimesheetTimerController.pauseTimer(lineItemId);
        TimesheetTimerController.saveTimer(lineItemId, null);
        Test.stopTest();

        Assert.isNull(timer.get('pauseStartMs'), 'The edit does not stop the run early');
        Assert.areEqual(9, ((Decimal) timer.get('baseHours')).intValue(), 'The clock shows the edited hours');
        Assert.areEqual(11.00, row(lineItemId).Duration__c.setScale(1), 'The 2 worked hours are kept on top of the edit');
    }

    @isTest
    static void cannotContinueOnALaterDay() {
        Date yesterday = Date.today().addDays(-1);
        Timesheet_Line_Item__c item = new Timesheet_Line_Item__c(
            Timesheet__c = timesheet().Id, Project__c = project().Id, Activity__c = ACTIVITY,
            Type__c = 'Attendance', Date__c = yesterday, Duration__c = 0
        );
        insert item;
        setState(item.Id, at(yesterday, 9, 0), 0, at(yesterday, 10, 0), true);

        Test.startTest();
        try {
            TimesheetTimerController.continueTimer(item.Id);
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            assertFails('can only be saved or discarded', e);
        }
        Test.stopTest();
    }

    @isTest
    static void rowAlreadyPastWorkdayRunsToCap() {
        insert new Timesheet_Line_Item__c(
            Timesheet__c = timesheet().Id, Project__c = project().Id, Activity__c = ACTIVITY,
            Type__c = 'Attendance', Date__c = Date.today(), Duration__c = 23
        );
        Test.startTest();
        start();
        Map<String, Object> timer = activeTimer();
        Test.stopTest();

        Decimal workday = (Decimal) timer.get('workdayHours');
        Decimal expected = 23 >= workday ? (Decimal) timer.get('capHours') : workday;
        Assert.areEqual(expected, (Decimal) timer.get('limitHours'));
        Assert.isNull(timer.get('pauseStartMs'), 'Still running below the daily maximum');
    }

    @isTest
    static void discardDeletesNewRowButKeepsExistingRow() {
        Id newRowId = start();
        TimesheetTimerController.discardTimer(newRowId);
        Assert.areEqual(0, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Id = :newRowId], 'A row the timer created is removed');

        Timesheet_Line_Item__c existing = new Timesheet_Line_Item__c(
            Timesheet__c = timesheet().Id, Project__c = project().Id, Activity__c = ACTIVITY,
            Type__c = 'Attendance', Date__c = Date.today(), Duration__c = 3
        );
        insert existing;

        Test.startTest();
        start();
        TimesheetTimerController.discardTimer(existing.Id);
        Test.stopTest();

        Timesheet_Line_Item__c kept = row(existing.Id);
        Assert.areEqual(3, kept.Duration__c.intValue(), 'Existing hours are unchanged');
        Assert.isNull(kept.Timer_Data__c, 'The timer is cleared');
    }

    @isTest
    static void timesheetCannotBeSubmittedOrApprovedWhileATimerRuns() {
        Id lineItemId = start();
        for (String status : new List<String>{ 'Submitted', 'Approved' }) {
            try {
                update new Timesheet__c(Id = timesheet().Id, Status__c = status);
                Assert.fail('Expected the timesheet to stay open');
            } catch (DmlException e) {
                Assert.isTrue(e.getMessage().contains('timer is still running'), e.getMessage());
            }
        }
        TimesheetTimerController.discardTimer(lineItemId);
        update new Timesheet__c(Id = timesheet().Id, Status__c = 'Submitted');
        Assert.areEqual('Submitted', [SELECT Status__c FROM Timesheet__c WHERE Id = :timesheet().Id].Status__c, 'Allowed once the timer is gone');
    }

    @isTest
    static void approvingASubmittedWeekIsNeverBlockedByALeftOverTimer() {
        Id lineItemId = start();
        // A week that was submitted while a timer existed (race, old data): the approver cannot clear the timer.
        String timerData = row(lineItemId).Timer_Data__c;
        update new Timesheet_Line_Item__c(Id = lineItemId, Timer_Data__c = null);
        update new Timesheet__c(Id = timesheet().Id, Status__c = 'Submitted');
        update new Timesheet_Line_Item__c(Id = lineItemId, Timer_Data__c = timerData);

        update new Timesheet__c(Id = timesheet().Id, Status__c = 'Approved');
        Assert.areEqual('Approved', [SELECT Status__c FROM Timesheet__c WHERE Id = :timesheet().Id].Status__c, 'The manager can approve');
    }

    @isTest
    static void cannotStartOnASubmittedTimesheet() {
        update new Timesheet__c(Id = timesheet().Id, Status__c = 'Submitted');
        try {
            start();
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            assertFails('already submitted', e);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Timer_Data__c != null], 'No timer row is created');
    }

    @isTest
    static void rejectedSaveTellsToEnterTheHoursByHand() {
        Id lineItemId = start();
        Long now = Datetime.now().getTime();
        setState(lineItemId, now - 5 * 3600000L, 0L, now, true); // paused after 5 h
        insert new Timesheet_Line_Item__c(
            Timesheet__c = timesheet().Id, Project__c = project().Id, Activity__c = 'Meeting',
            Date__c = Date.today(), Duration__c = 20, Type__c = 'Attendance'
        );
        try {
            TimesheetTimerController.saveTimer(lineItemId, null);
            Assert.fail('Expected the 24 h day limit to refuse the save');
        } catch (AuraHandledException e) {
            assertFails('Type these hours into that project and activity row', e);
            assertFails('measured 5', e);
        }
        Assert.isNotNull(row(lineItemId).Timer_Data__c, 'The timer is kept so its hours are not lost');
    }

    @isTest
    static void startNeedsATimesheet() {
        delete [SELECT Id FROM Timesheet__c];
        try {
            start();
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            assertFails('No timesheet exists', e);
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Timesheet__c], 'The timer must not create timesheets');
    }

    @isTest
    static void submittedTimesheetCannotChange() {
        Id lineItemId = start();
        // Submitting with a running timer is refused now; this recreates a week that was closed some other way.
        String timerData = row(lineItemId).Timer_Data__c;
        update new Timesheet_Line_Item__c(Id = lineItemId, Timer_Data__c = null);
        update new Timesheet__c(Id = timesheet().Id, Status__c = 'Submitted');
        update new Timesheet_Line_Item__c(Id = lineItemId, Timer_Data__c = timerData);
        try {
            TimesheetTimerController.saveTimer(lineItemId, null);
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            assertFails('already submitted', e);
        }
    }

    @isTest
    static void onlyOneRunningTimer() {
        start();
        try {
            start();
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            assertFails('already running', e);
        }
    }

    @isTest
    static void inactiveProjectIsReported() {
        Id lineItemId = start();
        update new Project__c(Id = project().Id, Active__c = false);
        try {
            TimesheetTimerController.saveTimer(lineItemId, null);
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            assertFails('no longer active', e);
        }
        TimesheetTimerController.discardTimer(lineItemId);
        try {
            start();
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            assertFails('not active', e);
        }
    }

    @isTest
    static void cannotTouchAnotherEmployeesTimer() {
        Employee__c other = new Employee__c(First_Name__c = 'Other', Last_Name__c = 'Person', Employment_Type__c = 'Full Time', Active__c = true);
        insert other;
        Timesheet__c otherSheet = newTimesheet(other.Id);
        insert otherSheet;
        Timesheet_Line_Item__c foreign = new Timesheet_Line_Item__c(
            Timesheet__c = otherSheet.Id, Project__c = project().Id, Activity__c = ACTIVITY,
            Type__c = 'Attendance', Date__c = Date.today(), Duration__c = 0
        );
        insert foreign;
        setState(foreign.Id, at(Date.today(), 9, 0), 0, null, true);

        try {
            TimesheetTimerController.discardTimer(foreign.Id);
            Assert.fail('Expected an error');
        } catch (AuraHandledException e) {
            assertFails('no longer running', e);
        }
        Assert.areEqual(1, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Id = :foreign.Id], 'The other timer survives');
    }
}
