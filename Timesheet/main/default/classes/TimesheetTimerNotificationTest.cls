@isTest
private class TimesheetTimerNotificationTest {

    private static final Long MS_PER_HOUR = 3600000L;

    @testSetup
    static void setupTestData() {
        Employee__c emp1 = new Employee__c(
            First_Name__c = 'Timer',
            Last_Name__c = 'User1',
            User__c = UserInfo.getUserId(),
            Employment_Type__c = 'Full Time',
            Active__c = true
        );
        insert emp1;

        Project__c proj = new Project__c(
            Name = 'Chained Timer Test Project',
            Active__c = true,
            Billable__c = 'Yes'
        );
        insert proj;

        insert new Project_Employee__c(
            Project__c = proj.Id,
            Employee__c = emp1.Id
        );

        Date today = Date.today();
        Timesheet__c timesheet = new Timesheet__c(
            Name = 'Timesheet Chained Test',
            Employee__c = emp1.Id,
            Start_Date__c = today.addDays(-3),
            End_Date__c = today.addDays(3),
            OwnerId = UserInfo.getUserId()
        );
        insert timesheet;
    }

    private static Timesheet_Line_Item__c createTestItem(Decimal limitBase, Long startMs, Long pausedMs, Boolean isPaused, Boolean autoStopped) {
        return createTestItem(limitBase, startMs, pausedMs, isPaused, autoStopped, 'Development-Coding', Date.today());
    }

    private static Timesheet_Line_Item__c createTestItem(Decimal limitBase, Long startMs, Long pausedMs, Boolean isPaused, Boolean autoStopped, String activity, Date itemDate) {
        Employee__c emp = [SELECT Id FROM Employee__c WHERE First_Name__c = 'Timer' LIMIT 1];
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        Timesheet__c ts = [SELECT Id FROM Timesheet__c LIMIT 1];

        TimesheetTimerController.TimerState state = new TimesheetTimerController.TimerState();
        state.startMs = startMs;
        state.pausedMs = pausedMs != null ? pausedMs : 0L;
        state.pauseStartMs = isPaused ? Datetime.now().getTime() : null;
        state.newItem = true;
        state.limitHours = 8.0;
        state.limitBase = limitBase;
        state.autoStopped = autoStopped;
        state.warning30Sent = false;
        state.stageSent = 0;

        Timesheet_Line_Item__c item = new Timesheet_Line_Item__c(
            Timesheet__c = ts.Id,
            Employee__c = emp.Id,
            Project__c = proj.Id,
            Activity__c = activity != null ? activity : 'Development-Coding',
            Type__c = 'Attendance',
            Date__c = itemDate != null ? itemDate : Date.today(),
            Duration__c = limitBase,
            Timer_Data__c = JSON.serialize(state)
        );
        insert item;
        return item;
    }

    private static void setupMockLimits(Decimal daily, Decimal max) {
        TimesheetTimerNotificationService.MetadataLimits limits = new TimesheetTimerNotificationService.MetadataLimits();
        limits.dailyHours = daily;
        limits.maxHours = max;
        limits.isValid = true;
        TimesheetTimerNotificationService.mockLimits = limits;
        TimesheetTimerNotificationService.sentStagesList.clear();
        TimesheetTimerNotificationService.sentTitlesList.clear();
        TimesheetTimerNotificationService.sentBodiesList.clear();
    }

    // ------------------------------------------------------------------------
    // Scenario 1: Daily Working-Hours Warning (Stage 1)
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario1_Stage1DailyWarningSent() {
        setupMockLimits(8.0, 12.0);
        Long nowMs = Datetime.now().getTime();
        Timesheet_Line_Item__c item = createTestItem(0.0, nowMs - (7.0 * MS_PER_HOUR).longValue(), 0L, false, false);

        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 1);
        Test.stopTest();

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(true, state.isStageSent(1), 'Stage 1 must be marked sent.');
        System.assertEquals(true, state.warning30Sent, 'Stage 1 warning30Sent must be true for backward compatibility.');
        System.assert(TimesheetTimerNotificationService.sentTitlesList.contains('Timesheet Timer Warning'), 'Warning title must be sent.');
        System.assert(TimesheetTimerNotificationService.sentBodiesList.contains('Your timer is still running and after 1 hour it will stop automatically.'), 'Warning body must match.');
    }

    // ------------------------------------------------------------------------
    // Scenario 2: Daily Working-Hours Limit Stop & Notification (Stage 2)
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario2_Stage2DailyLimitStopAndNotification() {
        setupMockLimits(8.0, 12.0);
        Long nowMs = Datetime.now().getTime();
        Timesheet_Line_Item__c item = createTestItem(0.0, nowMs - (8.0 * MS_PER_HOUR).longValue(), 0L, false, false);

        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 2);
        Test.stopTest();

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(true, state.isStageSent(2), 'Stage 2 must be marked sent.');
        System.assertEquals(true, state.autoStopped, 'Timer must be auto-stopped at daily limit.');
        System.assertNotEquals(null, state.pauseStartMs, 'pauseStartMs must be set upon auto-stop.');
        System.assert(TimesheetTimerNotificationService.sentTitlesList.contains('Timesheet Timer Stopped'), 'Stop title must be sent.');
        System.assert(TimesheetTimerNotificationService.sentBodiesList.contains('Your timer is stopped according to the org per day time limit. Still, if you are working, you can continue the timer.'), 'Stop body must match.');
        System.assertEquals(null, state.jobId, 'Stage 3 must NOT be chained automatically before continuation.');
    }

    // ------------------------------------------------------------------------
    // Scenario 3: Maximum Working-Hours Warning (Stage 3)
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario3_Stage3MaximumWarningSent() {
        setupMockLimits(8.0, 12.0);
        Long nowMs = Datetime.now().getTime();
        Timesheet_Line_Item__c item = createTestItem(0.0, nowMs - (11.0 * MS_PER_HOUR).longValue(), 0L, false, false);

        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 3);
        Test.stopTest();

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(true, state.isStageSent(3), 'Stage 3 must be marked sent.');
        System.assert(TimesheetTimerNotificationService.sentTitlesList.contains('Timesheet Timer Warning'), 'Max warning title must be sent.');
        System.assert(TimesheetTimerNotificationService.sentBodiesList.contains('Your timer is still running and after 1 hour it will stop automatically.'), 'Max warning body must match.');
    }

    // ------------------------------------------------------------------------
    // Scenario 4: Maximum Working-Hours Limit Stop & Notification (Stage 4)
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario4_Stage4MaximumLimitStopAndNotification() {
        setupMockLimits(8.0, 12.0);
        Long nowMs = Datetime.now().getTime();
        Timesheet_Line_Item__c item = createTestItem(0.0, nowMs - (12.0 * MS_PER_HOUR).longValue(), 0L, false, false);

        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 4);
        Test.stopTest();

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(true, state.isStageSent(4), 'Stage 4 must be marked sent.');
        System.assertEquals(true, state.autoStopped, 'Timer must be permanently auto-stopped at max limit.');
        System.assertNotEquals(null, state.pauseStartMs, 'pauseStartMs must be set.');
        System.assert(TimesheetTimerNotificationService.sentTitlesList.contains('Timesheet Timer Stopped'), 'Max stop title must be sent.');
        System.assert(TimesheetTimerNotificationService.sentBodiesList.contains('Your timer is stopped according to the org per day max time limit. Please save or discard timer hours.'), 'Max stop body must match.');
        System.assertEquals(null, state.jobId, 'No further jobs chained after Stage 4.');
    }

    // ------------------------------------------------------------------------
    // Scenario 5: Correct Notification Recipient
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario5_CorrectNotificationRecipient() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime() - (7.0 * MS_PER_HOUR).longValue(), 0L, false, false);

        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 1);
        Test.stopTest();

        System.assertEquals(UserInfo.getUserId(), TimesheetTimerNotificationService.lastSentRecipient, 'Recipient must be employee user Id.');
    }

    // ------------------------------------------------------------------------
    // Scenario 6: Correct Notification Type (Timesheet_Timer_Notification)
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario6_CorrectNotificationType() {
        List<CustomNotificationType> types = [
            SELECT Id, DeveloperName
            FROM CustomNotificationType
            WHERE DeveloperName = 'Timesheet_Timer_Notification'
            LIMIT 1
        ];
        System.assert(!types.isEmpty(), 'Timesheet_Timer_Notification CustomNotificationType must exist in org.');
    }

    // ------------------------------------------------------------------------
    // Scenario 7: Correct Target Record
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario7_CorrectTargetRecord() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime() - (7.0 * MS_PER_HOUR).longValue(), 0L, false, false);

        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 1);
        Test.stopTest();

        Timesheet_Line_Item__c reloaded = [SELECT Id FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        System.assertEquals(item.Id, reloaded.Id, 'Target record must match the exact Timesheet Line Item Id.');
    }

    // ------------------------------------------------------------------------
    // Scenario 8: Duplicate Notification Prevention
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario8_DuplicateNotificationPrevention() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime() - (7.0 * MS_PER_HOUR).longValue(), 0L, false, false);

        // First call for Stage 1 sends notification
        TimesheetTimerNotificationService.executeStage(item.Id, 1);
        System.assertEquals(1, TimesheetTimerNotificationService.sentStagesList.size(), 'Stage 1 notification must be sent.');
        System.assertEquals(1, TimesheetTimerNotificationService.sentStagesList[0], 'First sent notification must be Stage 1.');

        // Second call for Stage 1 must be skipped as duplicate
        TimesheetTimerNotificationService.executeStage(item.Id, 1);

        Integer stage1Count = 0;
        for (Integer s : TimesheetTimerNotificationService.sentStagesList) {
            if (s == 1) {
                stage1Count++;
            }
        }
        System.assertEquals(1, stage1Count, 'Duplicate Stage 1 notification must be skipped and sent at most once.');
    }

    // ------------------------------------------------------------------------
    // Scenario 9: Notification Request Failure and Retry
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario9_NotificationFailureAndRetry() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime() - (7.0 * MS_PER_HOUR).longValue(), 0L, false, false);

        // Force failure
        TimesheetTimerNotificationService.forceNotificationFailure = true;
        TimesheetTimerNotificationService.executeStage(item.Id, 1);

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(false, state.isStageSent(1), 'Failed notification must NOT be marked sent.');

        // Retry without failure
        TimesheetTimerNotificationService.forceNotificationFailure = false;
        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 1);
        Test.stopTest();

        updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(true, state.isStageSent(1), 'Notification must succeed on retry.');
    }

    // ------------------------------------------------------------------------
    // Scenario 10: Chained Job Creation
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario10_ChainedJobCreation() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime(), 0L, false, false);

        TimesheetTimerController.TimerState state = new TimesheetTimerController.TimerState();
        state.startMs = Datetime.now().getTime();
        state.limitBase = 0.0;
        state.pausedMs = 0L;

        Test.startTest();
        TimesheetTimerNotificationService.scheduleStage(item.Id, state, 1, 7.0);
        Test.stopTest();

        System.assertNotEquals(null, state.jobId, 'Job ID must be populated.');
        List<CronTrigger> jobs = [SELECT Id, State FROM CronTrigger WHERE Id = :state.jobId];
        System.assertEquals(1, jobs.size(), 'Job must exist in CronTrigger.');
    }

    // ------------------------------------------------------------------------
    // Scenario 11: Chained Job Execution via Schedulable
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario11_ChainedJobExecution() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime() - (7.0 * MS_PER_HOUR).longValue(), 0L, false, false);

        Test.startTest();
        TimesheetTimerNotificationScheduler scheduler = new TimesheetTimerNotificationScheduler(item.Id, 1);
        scheduler.execute(null);
        Test.stopTest();

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(true, state.isStageSent(1), 'Job execution must mark Stage 1 sent.');
    }

    // ------------------------------------------------------------------------
    // Scenario 12: Correct Job Cancellation
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario12_JobCancellation() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime(), 0L, false, false);

        TimesheetTimerController.TimerState state = new TimesheetTimerController.TimerState();
        state.startMs = Datetime.now().getTime();
        state.limitBase = 0.0;
        TimesheetTimerNotificationService.scheduleStage(item.Id, state, 1, 7.0);
        String jobId = state.jobId;
        System.assertNotEquals(null, jobId);

        Test.startTest();
        TimesheetTimerNotificationService.cancelNotificationJob(jobId);
        Test.stopTest();

        List<CronTrigger> jobs = [
            SELECT Id, State
            FROM CronTrigger
            WHERE Id = :jobId
            AND State NOT IN ('DELETED', 'ERROR', 'COMPLETE')
        ];
        System.assertEquals(0, jobs.size(), 'Scheduled job must be aborted.');
    }

    // ------------------------------------------------------------------------
    // Scenario 13: Timer Deleted Before Scheduled Execution
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario13_TimerDeletedBeforeExecution() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime(), 0L, false, false);
        Id itemId = item.Id;
        delete item;

        Test.startTest();
        // Should exit gracefully without throwing exception
        TimesheetTimerNotificationService.executeStage(itemId, 1);
        Test.stopTest();
    }

    // ------------------------------------------------------------------------
    // Scenario 14: Timer Saved or Discarded Before Execution
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario14_TimerSavedOrDiscardedBeforeExecution() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime(), 0L, false, false);
        item.Timer_Data__c = null;
        update item;

        Test.startTest();
        // Should exit cleanly
        TimesheetTimerNotificationService.executeStage(item.Id, 1);
        Test.stopTest();
    }

    // ------------------------------------------------------------------------
    // Scenario 15: Timer Paused Before Execution
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario15_TimerPausedBeforeExecution() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime() - (7.0 * MS_PER_HOUR).longValue(), 0L, true, false);

        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 1);
        Test.stopTest();

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(false, state.isStageSent(1), 'Paused timer must skip notification.');
    }

    // ------------------------------------------------------------------------
    // Scenario 16: Timer Continued and Rescheduled
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario16_TimerContinuedAndRescheduled() {
        setupMockLimits(8.0, 12.0);
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        Test.startTest();
        Map<String, Object> timerMap = TimesheetTimerController.startTimer(proj.Id, 'Development-Coding');
        Id lineItemId = (Id) timerMap.get('id');

        TimesheetTimerController.pauseTimer(lineItemId);
        Timesheet_Line_Item__c pausedItem = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :lineItemId];
        TimesheetTimerController.TimerState pausedState = (TimesheetTimerController.TimerState)
            JSON.deserialize(pausedItem.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(null, pausedState.jobId, 'Job must be cancelled upon pause.');

        TimesheetTimerController.continueTimer(lineItemId);
        Timesheet_Line_Item__c resumedItem = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :lineItemId];
        TimesheetTimerController.TimerState resumedState = (TimesheetTimerController.TimerState)
            JSON.deserialize(resumedItem.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertNotEquals(null, resumedState.jobId, 'Job must be rescheduled upon continuation.');
        Test.stopTest();
    }

    // ------------------------------------------------------------------------
    // Scenario 17: Multiple Employees Running Timers Concurrently
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario17_MultipleEmployeesRunningTimers() {
        setupMockLimits(8.0, 12.0);

        Profile p = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        User u2 = new User(
            Alias = 'u2tst',
            Email = 'user2test' + Datetime.now().getTime() + '@example.com',
            EmailEncodingKey = 'UTF-8',
            LastName = 'Testing2',
            LanguageLocaleKey = 'en_US',
            LocaleSidKey = 'en_US',
            ProfileId = p.Id,
            TimeZoneSidKey = 'America/Los_Angeles',
            UserName = 'user2test' + Datetime.now().getTime() + '@example.com'
        );
        insert u2;

        Employee__c emp2 = new Employee__c(
            First_Name__c = 'Timer',
            Last_Name__c = 'User2',
            User__c = u2.Id,
            Employment_Type__c = 'Full Time',
            Active__c = true
        );
        insert emp2;

        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];
        insert new Project_Employee__c(Project__c = proj.Id, Employee__c = emp2.Id);

        Date today = Date.today();
        Timesheet__c ts2 = new Timesheet__c(
            Name = 'Timesheet Chained Test 2',
            Employee__c = emp2.Id,
            Start_Date__c = today.addDays(-3),
            End_Date__c = today.addDays(3),
            OwnerId = u2.Id
        );
        insert ts2;

        Timesheet_Line_Item__c item1 = createTestItem(0.0, Datetime.now().getTime(), 0L, false, false);

        TimesheetTimerController.TimerState state2 = new TimesheetTimerController.TimerState();
        state2.startMs = Datetime.now().getTime();
        state2.limitBase = 0.0;
        Timesheet_Line_Item__c item2 = new Timesheet_Line_Item__c(
            Timesheet__c = ts2.Id,
            Employee__c = emp2.Id,
            Project__c = proj.Id,
            Activity__c = 'Development-Coding',
            Type__c = 'Attendance',
            Date__c = today,
            Duration__c = 0.0,
            Timer_Data__c = JSON.serialize(state2)
        );
        insert item2;

        Test.startTest();
        TimesheetTimerController.TimerState s1 = new TimesheetTimerController.TimerState();
        s1.startMs = Datetime.now().getTime();
        s1.limitBase = 0.0;
        TimesheetTimerNotificationService.scheduleStage(item1.Id, s1, 1, 7.0);

        TimesheetTimerController.TimerState s2 = new TimesheetTimerController.TimerState();
        s2.startMs = Datetime.now().getTime();
        s2.limitBase = 0.0;
        TimesheetTimerNotificationService.scheduleStage(item2.Id, s2, 1, 7.0);
        Test.stopTest();

        System.assertNotEquals(null, s1.jobId);
        System.assertNotEquals(null, s2.jobId);
        System.assertNotEquals(s1.jobId, s2.jobId, 'Each timer must have its own independent job.');

        // Cancelling one does not affect the other
        TimesheetTimerNotificationService.cancelNotificationJob(s1.jobId);
        List<CronTrigger> remaining = [SELECT Id FROM CronTrigger WHERE Id = :s2.jobId AND State NOT IN ('DELETED', 'ERROR')];
        System.assertEquals(1, remaining.size(), 'Second employee job must remain untouched.');
    }

    // ------------------------------------------------------------------------
    // Scenario 18: Scheduled-Job Limit Failure (100 Jobs Limit)
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario18_ScheduledJobLimitFailure() {
        setupMockLimits(8.0, 12.0);
        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime(), 0L, false, false);

        TimesheetTimerController.TimerState state = new TimesheetTimerController.TimerState();
        state.startMs = Datetime.now().getTime();
        state.limitBase = 0.0;

        // Force governor limit simulation
        TimesheetTimerNotificationService.forceGovernorLimitReached = true;

        Test.startTest();
        TimesheetTimerNotificationService.scheduleStage(item.Id, state, 1, 7.0);
        Test.stopTest();

        System.assertEquals(null, state.jobId, 'Job ID should be null when limit is reached.');
        System.assert(state.schedulingError != null && state.schedulingError.contains('limit reached'), 'schedulingError must be recorded.');
    }

    // ------------------------------------------------------------------------
    // Scenario 19: Invalid Custom Metadata
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario19_InvalidCustomMetadata() {
        TimesheetTimerNotificationService.MetadataLimits invalidLimits = new TimesheetTimerNotificationService.MetadataLimits();
        invalidLimits.dailyHours = -2.0;
        invalidLimits.maxHours = 0.0;
        invalidLimits.isValid = false;
        invalidLimits.errorMessage = 'Working_Hours_Per_Day__c is missing or non-positive in Custom Metadata.';
        TimesheetTimerNotificationService.mockLimits = invalidLimits;

        Timesheet_Line_Item__c item = createTestItem(0.0, Datetime.now().getTime(), 0L, false, false);
        TimesheetTimerController.TimerState state = new TimesheetTimerController.TimerState();
        state.startMs = Datetime.now().getTime();

        Test.startTest();
        TimesheetTimerNotificationService.scheduleNextStage(item.Id, state);
        Test.stopTest();

        System.assertEquals(null, state.jobId, 'Should not schedule when metadata is invalid.');
        System.assertEquals('Working_Hours_Per_Day__c is missing or non-positive in Custom Metadata.', state.schedulingError);
    }

    // ------------------------------------------------------------------------
    // Scenario 20: Different Daily and Maximum Limits (Including Max <= Daily)
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario20_DifferentDailyAndMaxLimits() {
        // Test when max is less than daily: capped safely
        TimesheetTimerNotificationService.MetadataLimits capped = new TimesheetTimerNotificationService.MetadataLimits();
        capped.dailyHours = 8.0;
        capped.maxHours = 6.0;
        capped.isValid = true;
        TimesheetTimerNotificationService.mockLimits = capped;

        TimesheetTimerNotificationService.MetadataLimits resolved = TimesheetTimerNotificationService.getLimits();
        System.assertEquals(8.0, resolved.dailyHours);
        System.assertEquals(8.0, resolved.maxHours, 'Max limit should be safely capped to daily limit.');

        // Test normal distinct limits
        TimesheetTimerNotificationService.mockLimits = null;
        TimesheetTimerNotificationService.MetadataLimits normal = TimesheetTimerNotificationService.getLimits();
        System.assert(normal.isValid, 'Standard metadata limits must be valid.');
    }

    // ------------------------------------------------------------------------
    // Scenario 21: Stage 2 sends notification even if LWC applyLimit() auto-stopped first
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario21_Stage2SentWhenAlreadyAutoStoppedByApplyLimit() {
        setupMockLimits(8.0, 12.0);
        Long nowMs = Datetime.now().getTime();
        // Item already auto-stopped by applyLimit() (pauseStartMs != null, autoStopped = true)
        Timesheet_Line_Item__c item = createTestItem(0.0, nowMs - (8.0 * MS_PER_HOUR).longValue(), 0L, true, true);

        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 2);
        Test.stopTest();

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(true, state.isStageSent(2), 'Stage 2 must send notification even if already autoStopped.');
        System.assert(TimesheetTimerNotificationService.sentTitlesList.contains('Timesheet Timer Stopped'), 'Stage 2 Stop notification must be delivered.');
    }

    // ------------------------------------------------------------------------
    // Scenario 22: Stage 4 sends notification even if LWC applyLimit() auto-stopped first
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario22_Stage4SentWhenAlreadyAutoStoppedByApplyLimit() {
        setupMockLimits(8.0, 12.0);
        Long nowMs = Datetime.now().getTime();
        // Item already auto-stopped by applyLimit() at max limit (pauseStartMs != null, autoStopped = true)
        Timesheet_Line_Item__c item = createTestItem(0.0, nowMs - (12.0 * MS_PER_HOUR).longValue(), 0L, true, true);

        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 4);
        Test.stopTest();

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(true, state.isStageSent(4), 'Stage 4 must send notification even if already autoStopped.');
        System.assert(TimesheetTimerNotificationService.sentTitlesList.contains('Timesheet Timer Stopped'), 'Stage 4 Stop notification must be delivered.');
    }

    // ------------------------------------------------------------------------
    // Scenario 23: Manual pause strictly prevents notifications for Stage 2
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario23_ManualPauseSkipsStage2() {
        setupMockLimits(8.0, 12.0);
        Long nowMs = Datetime.now().getTime();
        // Manually paused timer (pauseStartMs != null, autoStopped = false)
        Timesheet_Line_Item__c item = createTestItem(0.0, nowMs - (7.0 * MS_PER_HOUR).longValue(), 0L, true, false);

        Test.startTest();
        TimesheetTimerNotificationService.executeStage(item.Id, 2);
        Test.stopTest();

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(false, state.isStageSent(2), 'Manual pause must skip Stage 2 notification.');
        System.assertEquals(0, TimesheetTimerNotificationService.sentStagesList.size(), 'No notification should be sent for manually paused timer.');
    }

    // ------------------------------------------------------------------------
    // Scenario 24: Duplicate Execution Prevention for All Four Stages
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario24_DuplicateExecutionAllFourStages() {
        setupMockLimits(8.0, 12.0);
        Long nowMs = Datetime.now().getTime();

        // 1. Duplicate Stage 1
        Timesheet_Line_Item__c item1 = createTestItem(0.0, nowMs - (7.0 * MS_PER_HOUR).longValue(), 0L, false, false, 'Development-Coding', Date.today());
        TimesheetTimerNotificationService.executeStage(item1.Id, 1);
        TimesheetTimerNotificationService.executeStage(item1.Id, 1);
        Integer countStage1 = 0;
        for (Integer s : TimesheetTimerNotificationService.sentStagesList) {
            if (s == 1) countStage1++;
        }
        System.assertEquals(1, countStage1, 'Stage 1 notification must be sent at most once.');

        // 2. Duplicate Stage 2
        Timesheet_Line_Item__c item2 = createTestItem(0.0, nowMs - (8.0 * MS_PER_HOUR).longValue(), 0L, false, false, 'Testing', Date.today());
        TimesheetTimerNotificationService.executeStage(item2.Id, 2);
        TimesheetTimerNotificationService.executeStage(item2.Id, 2);
        Integer countStage2 = 0;
        for (Integer s : TimesheetTimerNotificationService.sentStagesList) {
            if (s == 2) countStage2++;
        }
        System.assertEquals(1, countStage2, 'Stage 2 notification must be sent at most once.');

        // 3. Duplicate Stage 3
        Timesheet_Line_Item__c item3 = createTestItem(0.0, nowMs - (11.0 * MS_PER_HOUR).longValue(), 0L, false, false, 'Documentation / Review', Date.today());
        TimesheetTimerNotificationService.executeStage(item3.Id, 3);
        TimesheetTimerNotificationService.executeStage(item3.Id, 3);
        Integer countStage3 = 0;
        for (Integer s : TimesheetTimerNotificationService.sentStagesList) {
            if (s == 3) countStage3++;
        }
        System.assertEquals(1, countStage3, 'Stage 3 notification must be sent at most once.');

        // 4. Duplicate Stage 4
        Timesheet_Line_Item__c item4 = createTestItem(0.0, nowMs - (12.0 * MS_PER_HOUR).longValue(), 0L, false, false, 'Analysis / Exploration', Date.today());
        TimesheetTimerNotificationService.executeStage(item4.Id, 4);
        TimesheetTimerNotificationService.executeStage(item4.Id, 4);
        Integer countStage4 = 0;
        for (Integer s : TimesheetTimerNotificationService.sentStagesList) {
            if (s == 4) countStage4++;
        }
        System.assertEquals(1, countStage4, 'Stage 4 notification must be sent at most once.');
    }

    // ------------------------------------------------------------------------
    // Scenario 25: Manual Pause Prevents All Four Stages
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario25_ManualPausePreventsAllStages() {
        setupMockLimits(8.0, 12.0);
        Long nowMs = Datetime.now().getTime();
        // Manually paused timer (pauseStartMs != null, autoStopped = false)
        Timesheet_Line_Item__c item = createTestItem(0.0, nowMs - (5.0 * MS_PER_HOUR).longValue(), 0L, true, false);

        // Try executing all 4 stages
        TimesheetTimerNotificationService.executeStage(item.Id, 1);
        TimesheetTimerNotificationService.executeStage(item.Id, 2);
        TimesheetTimerNotificationService.executeStage(item.Id, 3);
        TimesheetTimerNotificationService.executeStage(item.Id, 4);

        System.assertEquals(0, TimesheetTimerNotificationService.sentStagesList.size(), 'Manually paused timer must receive zero notifications.');

        Timesheet_Line_Item__c updated = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :item.Id];
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(updated.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(0, state.stageSent, 'stageSent must remain 0.');
    }

    // ------------------------------------------------------------------------
    // Scenario 26: Independent Stages Verification with Full Payload & Field Validation
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario26_IndependentStagesVerification() {
        setupMockLimits(2.0, 4.0);
        Long nowMs = Datetime.now().getTime();

        // Stage 1 (1 hour into 2h daily limit)
        Timesheet_Line_Item__c s1Item = createTestItem(0.0, nowMs - (1.0 * MS_PER_HOUR).longValue(), 0L, false, false, 'Development-Coding', Date.today());
        TimesheetTimerNotificationService.executeStage(s1Item.Id, 1);
        Timesheet_Line_Item__c s1Updated = [SELECT Id, Timer_Data__c, Employee__r.User__c FROM Timesheet_Line_Item__c WHERE Id = :s1Item.Id];
        TimesheetTimerController.TimerState s1State = (TimesheetTimerController.TimerState)
            JSON.deserialize(s1Updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(1, s1State.stageSent, 'Stage 1 stageSent must be 1.');
        System.assertEquals(false, s1State.autoStopped, 'Stage 1 must not auto-stop.');
        System.assertEquals(null, s1State.pauseStartMs, 'Stage 1 pauseStartMs must be null.');
        System.assertNotEquals(null, s1State.jobId, 'Stage 1 must chain Stage 2 job.');
        System.assertEquals('Timesheet Timer Warning', TimesheetTimerNotificationService.lastSentTitle);
        System.assertEquals('Your timer is still running and after 1 hour it will stop automatically.', TimesheetTimerNotificationService.lastSentBody);
        System.assertEquals(s1Updated.Employee__r.User__c, TimesheetTimerNotificationService.lastSentRecipient);
        System.assertEquals(s1Item.Id, s1Updated.Id, 'Target record ID matches line item ID.');

        // Stage 2 (2 hours reached)
        Timesheet_Line_Item__c s2Item = createTestItem(0.0, nowMs - (2.0 * MS_PER_HOUR).longValue(), 0L, false, false, 'Testing', Date.today());
        TimesheetTimerNotificationService.executeStage(s2Item.Id, 2);
        Timesheet_Line_Item__c s2Updated = [SELECT Id, Timer_Data__c, Employee__r.User__c FROM Timesheet_Line_Item__c WHERE Id = :s2Item.Id];
        TimesheetTimerController.TimerState s2State = (TimesheetTimerController.TimerState)
            JSON.deserialize(s2Updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(2, s2State.stageSent, 'Stage 2 stageSent must be 2.');
        System.assertEquals(true, s2State.autoStopped, 'Stage 2 must auto-stop.');
        System.assertNotEquals(null, s2State.pauseStartMs, 'Stage 2 pauseStartMs must be set.');
        System.assertEquals(null, s2State.jobId, 'Stage 2 must not chain before continue.');
        System.assertEquals('Timesheet Timer Stopped', TimesheetTimerNotificationService.lastSentTitle);
        System.assertEquals('Your timer is stopped according to the org per day time limit. Still, if you are working, you can continue the timer.', TimesheetTimerNotificationService.lastSentBody);
        System.assertEquals(s2Updated.Employee__r.User__c, TimesheetTimerNotificationService.lastSentRecipient);

        // Stage 3 (3 hours reached towards 4h max limit)
        Timesheet_Line_Item__c s3Item = createTestItem(0.0, nowMs - (3.0 * MS_PER_HOUR).longValue(), 0L, false, false, 'Documentation / Review', Date.today());
        TimesheetTimerNotificationService.executeStage(s3Item.Id, 3);
        Timesheet_Line_Item__c s3Updated = [SELECT Id, Timer_Data__c, Employee__r.User__c FROM Timesheet_Line_Item__c WHERE Id = :s3Item.Id];
        TimesheetTimerController.TimerState s3State = (TimesheetTimerController.TimerState)
            JSON.deserialize(s3Updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(3, s3State.stageSent, 'Stage 3 stageSent must be 3.');
        System.assertEquals(false, s3State.autoStopped, 'Stage 3 must not auto-stop.');
        System.assertEquals(null, s3State.pauseStartMs, 'Stage 3 pauseStartMs must be null.');
        System.assertNotEquals(null, s3State.jobId, 'Stage 3 must chain Stage 4 job.');
        System.assertEquals('Timesheet Timer Warning', TimesheetTimerNotificationService.lastSentTitle);
        System.assertEquals('Your timer is still running and after 1 hour it will stop automatically.', TimesheetTimerNotificationService.lastSentBody);
        System.assertEquals(s3Updated.Employee__r.User__c, TimesheetTimerNotificationService.lastSentRecipient);

        // Stage 4 (4 hours reached max limit)
        Timesheet_Line_Item__c s4Item = createTestItem(0.0, nowMs - (4.0 * MS_PER_HOUR).longValue(), 0L, false, false, 'Analysis / Exploration', Date.today());
        TimesheetTimerNotificationService.executeStage(s4Item.Id, 4);
        Timesheet_Line_Item__c s4Updated = [SELECT Id, Timer_Data__c, Employee__r.User__c FROM Timesheet_Line_Item__c WHERE Id = :s4Item.Id];
        TimesheetTimerController.TimerState s4State = (TimesheetTimerController.TimerState)
            JSON.deserialize(s4Updated.Timer_Data__c, TimesheetTimerController.TimerState.class);

        System.assertEquals(4, s4State.stageSent, 'Stage 4 stageSent must be 4.');
        System.assertEquals(true, s4State.autoStopped, 'Stage 4 must auto-stop permanently.');
        System.assertNotEquals(null, s4State.pauseStartMs, 'Stage 4 pauseStartMs must be set.');
        System.assertEquals(null, s4State.jobId, 'Stage 4 must not chain any jobs.');
        System.assertEquals('Timesheet Timer Stopped', TimesheetTimerNotificationService.lastSentTitle);
        System.assertEquals('Your timer is stopped according to the org per day max time limit. Please save or discard timer hours.', TimesheetTimerNotificationService.lastSentBody);
        System.assertEquals(s4Updated.Employee__r.User__c, TimesheetTimerNotificationService.lastSentRecipient);
    }

    // ------------------------------------------------------------------------
    // Scenario 27: Manual Pause and Continue Full Field Verification
    // ------------------------------------------------------------------------
    @isTest
    static void testScenario27_ManualPauseAndContinueVerification() {
        setupMockLimits(2.0, 4.0);
        Project__c proj = [SELECT Id FROM Project__c LIMIT 1];

        // 1. Start Timer
        Map<String, Object> timerMap = TimesheetTimerController.startTimer(proj.Id, 'Development-Coding');
        Id lineItemId = (Id) timerMap.get('id');

        Timesheet_Line_Item__c startedItem = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :lineItemId];
        TimesheetTimerController.TimerState startedState = (TimesheetTimerController.TimerState)
            JSON.deserialize(startedItem.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(false, startedState.autoStopped, 'Started timer must not be autoStopped.');
        System.assertEquals(null, startedState.pauseStartMs, 'Started timer must not have pauseStartMs.');
        System.assertEquals(null, startedState.stageSent, 'Initial stageSent must be null before any stage is sent.');
        System.assertNotEquals(null, startedState.jobId, 'Started timer must have a scheduled jobId.');

        // 2. Manual Pause
        TimesheetTimerController.pauseTimer(lineItemId);
        Timesheet_Line_Item__c pausedItem = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :lineItemId];
        TimesheetTimerController.TimerState pausedState = (TimesheetTimerController.TimerState)
            JSON.deserialize(pausedItem.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(false, pausedState.autoStopped, 'Manually paused timer must have autoStopped = false.');
        System.assertNotEquals(null, pausedState.pauseStartMs, 'Manually paused timer must have pauseStartMs set.');
        System.assertEquals(null, pausedState.stageSent, 'stageSent must remain null upon pause.');
        System.assertEquals(null, pausedState.jobId, 'Scheduled job must be cancelled and jobId set to null upon pause.');

        // 3. Continue Timer after manual pause
        TimesheetTimerController.continueTimer(lineItemId);
        Timesheet_Line_Item__c resumedItem = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :lineItemId];
        TimesheetTimerController.TimerState resumedState = (TimesheetTimerController.TimerState)
            JSON.deserialize(resumedItem.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(false, resumedState.autoStopped, 'Resumed timer must have autoStopped = false.');
        System.assertEquals(null, resumedState.pauseStartMs, 'Resumed timer must have pauseStartMs cleared.');
        System.assertNotEquals(null, resumedState.jobId, 'Resumed timer must reschedule and set jobId.');

        // 4. Simulate Stage 2 Auto-Stop
        TimesheetTimerNotificationService.executeStage(lineItemId, 2);
        Timesheet_Line_Item__c autoStoppedItem = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :lineItemId];
        TimesheetTimerController.TimerState autoStoppedState = (TimesheetTimerController.TimerState)
            JSON.deserialize(autoStoppedItem.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(true, autoStoppedState.autoStopped, 'Auto-stopped timer must have autoStopped = true.');
        System.assertNotEquals(null, autoStoppedState.pauseStartMs, 'Auto-stopped timer must have pauseStartMs set.');
        System.assertEquals(2, autoStoppedState.stageSent, 'stageSent must be 2 after Stage 2.');
        System.assertEquals(null, autoStoppedState.jobId, 'jobId must be null while auto-stopped.');

        // 5. Continue Timer after Stage 2 Auto-Stop
        TimesheetTimerController.continueTimer(lineItemId);
        Timesheet_Line_Item__c postContinueItem = [SELECT Timer_Data__c FROM Timesheet_Line_Item__c WHERE Id = :lineItemId];
        TimesheetTimerController.TimerState postContinueState = (TimesheetTimerController.TimerState)
            JSON.deserialize(postContinueItem.Timer_Data__c, TimesheetTimerController.TimerState.class);
        System.assertEquals(false, postContinueState.autoStopped, 'Continued timer must reset autoStopped to false.');
        System.assertEquals(null, postContinueState.pauseStartMs, 'Continued timer must clear pauseStartMs.');
        System.assertEquals(2, postContinueState.stageSent, 'stageSent remains 2 until stage 3 executes.');
        System.assertNotEquals(null, postContinueState.jobId, 'Continued timer must reschedule next stage (Stage 3).');
    }
}
