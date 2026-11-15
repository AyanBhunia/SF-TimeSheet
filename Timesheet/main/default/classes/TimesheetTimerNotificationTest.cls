@isTest
private class TimesheetTimerNotificationTest {

    private static final Long MS_PER_HOUR = 3600000L;
    private static final List<String> ACTIVITIES = new List<String>{
        'Documentation / Review', 'Testing', 'Analysis / Exploration', 'Development-Admin',
        'Development-Coding', 'Meeting', 'Collaboration', 'Mentoring / Training', 'Certification', 'Other'
    };

    @testSetup
    static void setupTestData() {
        // Package builds run tests as a user without access to the app's objects, and a permission
        // set assigned in a test only applies inside System.runAs.
        System.runAs(me()) {
            grantHrAdmin();
        }
        System.runAs(me()) {
            Employee__c emp = new Employee__c(
                First_Name__c = 'Timer',
                Last_Name__c = 'User1',
                User__c = UserInfo.getUserId(),
                Employment_Type__c = 'Full Time',
                Active__c = true
            );
            insert emp;

            Project__c proj = new Project__c(Name = 'Timer Notification Project', Active__c = true, Billable__c = 'Yes');
            insert proj;
            insert new Project_Employee__c(Project__c = proj.Id, Employee__c = emp.Id);

            Date today = Date.today();
            insert new Timesheet__c(
                Name = 'Timer Notification Timesheet',
                Employee__c = emp.Id,
                Start_Date__c = today.addDays(-3),
                End_Date__c = today.addDays(3),
                OwnerId = UserInfo.getUserId()
            );
        }
    }

    private static User me() {
        return new User(Id = UserInfo.getUserId());
    }

    private static void grantHrAdmin() {
        Id hrAdmin = [SELECT Id FROM PermissionSet WHERE Name = 'Timesheet_HR_Admin' LIMIT 1].Id;
        if ([SELECT COUNT() FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId() AND PermissionSetId = :hrAdmin] == 0) {
            insert new PermissionSetAssignment(AssigneeId = UserInfo.getUserId(), PermissionSetId = hrAdmin);
        }
    }

    private static Decimal workday() {
        return LeaveValidator.settings().Working_Hours_Per_Day__c;
    }

    private static Decimal cap() {
        return LeaveValidator.settings().Maximum_Working_Hrs_Per_Day__c;
    }

    // A timer whose current run started `hoursAgo` hours ago and stops at limitHours.
    private static TimesheetTimerController.TimerState runningState(Decimal hoursAgo, Decimal limitHours, Decimal limitBase, Integer stageSent) {
        TimesheetTimerController.TimerState state = new TimesheetTimerController.TimerState();
        state.startMs = Datetime.now().getTime() - (hoursAgo * MS_PER_HOUR).longValue();
        state.pausedMs = 0;
        state.newItem = true;
        state.limitHours = limitHours;
        state.limitBase = limitBase;
        state.autoStopped = false;
        state.stageSent = stageSent;
        return state;
    }

    private static Timesheet_Line_Item__c template;

    // Saves the state on a new row the way the controller does.
    private static Timesheet_Line_Item__c insertDue(TimesheetTimerController.TimerState state, Decimal rowHours, Integer index) {
        Timesheet_Line_Item__c item = newRow(state, rowHours, index);
        insert item;
        return item;
    }

    private static Timesheet_Line_Item__c newRow(TimesheetTimerController.TimerState state, Decimal rowHours, Integer index) {
        if (template == null) {
            template = new Timesheet_Line_Item__c(
                Timesheet__c = [SELECT Id FROM Timesheet__c LIMIT 1].Id,
                Employee__c = [SELECT Id FROM Employee__c LIMIT 1].Id,
                Project__c = [SELECT Id FROM Project__c LIMIT 1].Id
            );
        }
        Timesheet_Line_Item__c item = new Timesheet_Line_Item__c(
            Timesheet__c = template.Timesheet__c,
            Employee__c = template.Employee__c,
            Project__c = template.Project__c,
            Activity__c = ACTIVITIES[Math.mod(index, ACTIVITIES.size())],
            Type__c = 'Attendance',
            Date__c = Date.today().addDays(-(index / ACTIVITIES.size())),
            Duration__c = rowHours
        );
        TimesheetTimerController.setState(item, state, rowHours);
        return item;
    }

    // Datetime fields keep whole seconds.
    private static Long seconds(Long ms) {
        return ms / 1000;
    }

    private static Timesheet_Line_Item__c reload(Id itemId) {
        return [SELECT Timer_Data__c, Next_Notify_At__c FROM Timesheet_Line_Item__c WHERE Id = :itemId];
    }

    private static TimesheetTimerController.TimerState stateOf(Timesheet_Line_Item__c item) {
        return (TimesheetTimerController.TimerState) JSON.deserialize(item.Timer_Data__c, TimesheetTimerController.TimerState.class);
    }

    @isTest
    static void startSchedulesTheWarningAnHourBeforeTheWorkday() {
        System.runAs(me()) {
            TimesheetTimerController.TimerState state = runningState(0, workday(), 0, null);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);

            Timesheet_Line_Item__c saved = reload(item.Id);
            Long expected = state.startMs + ((workday() - 1) * MS_PER_HOUR).longValue();
            System.assertEquals(seconds(expected), seconds(saved.Next_Notify_At__c.getTime()), 'Warning is due an hour before the stop.');
        }
    }

    @isTest
    static void warningIsSentAndTheStopIsScheduled() {
        System.runAs(me()) {
            TimesheetTimerController.TimerState state = runningState(workday() - 1, workday(), 0, null);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);
            update new Timesheet_Line_Item__c(Id = item.Id, Next_Notify_At__c = Datetime.now());

            Test.startTest();
            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });
            Test.stopTest();

            Timesheet_Line_Item__c saved = reload(item.Id);
            System.assertEquals(1, TimesheetTimerNotificationService.sent.size(), 'The warning is sent.');
            System.assertEquals(1, stateOf(saved).stageSent);
            System.assertEquals(seconds(state.startMs + (workday() * MS_PER_HOUR).longValue()), seconds(saved.Next_Notify_At__c.getTime()));
            System.assertEquals(null, stateOf(saved).pauseStartMs, 'A warning does not stop the timer.');
        }
    }

    @isTest
    static void stopNotifiesAndStopsAtTheLimit() {
        System.runAs(me()) {
            TimesheetTimerController.TimerState state = runningState(workday(), workday(), 0, 1);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);
            Long stopMs = state.startMs + (workday() * MS_PER_HOUR).longValue();

            Test.startTest();
            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });
            Test.stopTest();

            Timesheet_Line_Item__c saved = reload(item.Id);
            TimesheetTimerController.TimerState after = stateOf(saved);
            System.assertEquals(1, TimesheetTimerNotificationService.sent.size());
            System.assertEquals(true, after.autoStopped);
            System.assertEquals(stopMs, after.pauseStartMs, 'Stopped at the limit, not when the flow ran.');
            System.assertEquals(2, after.stageSent);
            System.assertEquals(null, saved.Next_Notify_At__c, 'Nothing is due while stopped.');
        }
    }

    @isTest
    static void warningIsSkippedWhenTheLastHourHasStarted() {
        System.runAs(me()) {
            TimesheetTimerController.TimerState state = runningState(workday() - 0.5, workday(), 0, null);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);
            Long stopMs = state.startMs + (workday() * MS_PER_HOUR).longValue();
            System.assertEquals(seconds(stopMs), seconds(reload(item.Id).Next_Notify_At__c.getTime()), 'Goes straight to the stop.');
        }
    }

    @isTest
    static void secondRunWarnsAndStopsAtTheMaximum() {
        System.runAs(me()) {
            // Continued after the workday stop: limitBase is the row's saved hours.
            TimesheetTimerController.TimerState state = runningState(cap() - workday() - 1, cap(), workday(), 2);
            Timesheet_Line_Item__c item = insertDue(state, workday(), 0);
            update new Timesheet_Line_Item__c(Id = item.Id, Next_Notify_At__c = Datetime.now());

            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });
            Timesheet_Line_Item__c afterWarning = reload(item.Id);
            System.assertEquals(3, stateOf(afterWarning).stageSent);
            System.assertEquals(TimesheetTimerNotificationService.bodyOf(1), TimesheetTimerNotificationService.bodyOf(3));

            // The maximum is reached.
            TimesheetTimerController.TimerState atCap = stateOf(afterWarning);
            atCap.startMs -= 2 * MS_PER_HOUR;
            update new Timesheet_Line_Item__c(Id = item.Id, Timer_Data__c = JSON.serialize(atCap), Next_Notify_At__c = Datetime.now());
            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });

            Timesheet_Line_Item__c stopped = reload(item.Id);
            System.assertEquals(true, stateOf(stopped).autoStopped);
            System.assertEquals(4, stateOf(stopped).stageSent);
            System.assertEquals(null, stopped.Next_Notify_At__c);
            System.assertEquals(2, TimesheetTimerNotificationService.sent.size());
        }
    }

    @isTest
    static void stopIsStillNotifiedWhenTheControllerStoppedItFirst() {
        System.runAs(me()) {
            TimesheetTimerController.TimerState state = runningState(workday() + 1, workday(), 0, 1);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);
            // applyLimit stopped it and kept the due time.
            TimesheetTimerController.stopAtLimit(state, 0);
            update new Timesheet_Line_Item__c(Id = item.Id, Timer_Data__c = JSON.serialize(state));

            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });

            Timesheet_Line_Item__c saved = reload(item.Id);
            System.assertEquals(1, TimesheetTimerNotificationService.sent.size());
            System.assertEquals(2, stateOf(saved).stageSent);
            System.assertEquals(null, saved.Next_Notify_At__c);
        }
    }

    @isTest
    static void lateWarningOnAStoppedTimerSendsTheStopInstead() {
        System.runAs(me()) {
            // The warning was still due when the controller stopped the timer at its limit.
            TimesheetTimerController.TimerState state = runningState(workday() + 1, workday(), 0, null);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);
            TimesheetTimerController.stopAtLimit(state, 0);
            update new Timesheet_Line_Item__c(Id = item.Id, Timer_Data__c = JSON.serialize(state),
                Next_Notify_At__c = Datetime.now().addHours(-2));

            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });

            Timesheet_Line_Item__c saved = reload(item.Id);
            System.assertEquals(1, TimesheetTimerNotificationService.sent.size(), 'The stop is still notified.');
            System.assertEquals(2, stateOf(saved).stageSent);
            System.assertEquals(null, saved.Next_Notify_At__c);
        }
    }

    @isTest
    static void earlyWakeUpSendsNothingAndRestoresTheDueTime() {
        System.runAs(me()) {
            TimesheetTimerController.TimerState state = runningState(1, workday(), 0, null);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);
            Datetime dueAt = reload(item.Id).Next_Notify_At__c;
            update new Timesheet_Line_Item__c(Id = item.Id, Next_Notify_At__c = Datetime.now());

            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });

            System.assertEquals(0, TimesheetTimerNotificationService.sent.size(), 'The warning is not due yet.');
            System.assertEquals(dueAt, reload(item.Id).Next_Notify_At__c, 'The real due time is written back.');
        }
    }

    @isTest
    static void unreadableRowDoesNotBlockTheOthers() {
        System.runAs(me()) {
            List<Timesheet_Line_Item__c> rows = new List<Timesheet_Line_Item__c>{
                newRow(runningState(workday(), workday(), 0, 1), 0, 0),
                newRow(runningState(workday(), workday(), 0, 1), 0, 1)
            };
            insert rows;
            update new Timesheet_Line_Item__c(Id = rows[0].Id, Timer_Data__c = '{not json');

            TimesheetTimerNotificationService.processDue(new List<Id>{ rows[0].Id, rows[1].Id });

            System.assertEquals(1, TimesheetTimerNotificationService.sent.size(), 'The good timer is still notified.');
            System.assertEquals(true, stateOf(reload(rows[1].Id)).autoStopped);
            System.assertEquals(null, reload(rows[0].Id).Next_Notify_At__c, 'The bad row is not retried.');
        }
    }

    @isTest
    static void movedLaterIsLeftForTheNewTime() {
        System.runAs(me()) {
            TimesheetTimerController.TimerState state = runningState(1, workday(), 0, null);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);
            Datetime dueAt = reload(item.Id).Next_Notify_At__c;

            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });

            System.assertEquals(0, TimesheetTimerNotificationService.sent.size());
            System.assertEquals(dueAt, reload(item.Id).Next_Notify_At__c);
        }
    }

    @isTest
    static void alreadySentStageIsNotSentAgain() {
        System.runAs(me()) {
            TimesheetTimerController.TimerState state = runningState(workday() - 1, workday(), 0, 1);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);
            update new Timesheet_Line_Item__c(Id = item.Id, Next_Notify_At__c = Datetime.now());

            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });

            System.assertEquals(0, TimesheetTimerNotificationService.sent.size());
            System.assertEquals(1, stateOf(reload(item.Id)).stageSent);
        }
    }

    @isTest
    static void failedNotificationStillStopsTheTimer() {
        System.runAs(me()) {
            TimesheetTimerController.TimerState state = runningState(workday(), workday(), 0, 1);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);
            TimesheetTimerNotificationService.forceNotificationFailure = true;

            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });

            Timesheet_Line_Item__c saved = reload(item.Id);
            System.assertEquals(true, stateOf(saved).autoStopped);
            System.assertEquals(1, stateOf(saved).stageSent, 'Not marked as sent.');
            System.assertEquals(null, saved.Next_Notify_At__c);
        }
    }

    @isTest
    static void savedOrDiscardedTimerIsIgnored() {
        System.runAs(me()) {
            TimesheetTimerController.TimerState state = runningState(workday(), workday(), 0, 1);
            Timesheet_Line_Item__c item = insertDue(state, 0, 0);
            update new Timesheet_Line_Item__c(Id = item.Id, Timer_Data__c = null);

            TimesheetTimerNotificationService.processDue(new List<Id>{ item.Id });

            System.assertEquals(0, TimesheetTimerNotificationService.sent.size());
        }
    }

    @isTest
    static void manyDueTimersAreProcessedInOneCall() {
        System.runAs(me()) {
            List<Timesheet_Line_Item__c> rows = new List<Timesheet_Line_Item__c>();
            for (Integer i = 0; i < 40; i++) {
                rows.add(newRow(runningState(workday(), workday(), 0, 1), 0, i));
            }
            insert rows;
            List<Id> ids = new List<Id>(new Map<Id, Timesheet_Line_Item__c>(rows).keySet());

            Test.startTest();
            TimesheetTimerNotificationService.processDue(ids);
            Integer queries = Limits.getQueries();
            Test.stopTest();

            System.assertEquals(40, TimesheetTimerNotificationService.sent.size());
            System.assertEquals(40, [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Id IN :ids AND Next_Notify_At__c = null]);
            // Including the line item triggers; one query per timer would be 40+.
            System.assert(queries < 25, 'Queries must not grow with the number of timers: ' + queries);
        }
    }

    @isTest
    static void controllerActionsSetAndClearTheDueTime() {
        System.runAs(me()) {
            Id projectId = [SELECT Id FROM Project__c LIMIT 1].Id;

            Map<String, Object> started = TimesheetTimerController.startTimer(projectId, 'Testing');
            Id itemId = (Id) started.get('id');
            System.assertNotEquals(null, reload(itemId).Next_Notify_At__c, 'Start schedules the warning.');

            TimesheetTimerController.pauseTimer(itemId);
            System.assertEquals(null, reload(itemId).Next_Notify_At__c, 'Pause cancels it.');

            TimesheetTimerController.continueTimer(itemId);
            System.assertNotEquals(null, reload(itemId).Next_Notify_At__c, 'Continue schedules again.');

            // Save after an hour of work.
            TimesheetTimerController.pauseTimer(itemId);
            Timesheet_Line_Item__c running = reload(itemId);
            TimesheetTimerController.TimerState worked = stateOf(running);
            worked.startMs -= MS_PER_HOUR;
            worked.pauseStartMs = null;
            update new Timesheet_Line_Item__c(Id = itemId, Timer_Data__c = JSON.serialize(worked));
            TimesheetTimerController.saveTimer(itemId, null);
            Timesheet_Line_Item__c saved = reload(itemId);
            System.assertEquals(null, saved.Timer_Data__c);
            System.assertEquals(null, saved.Next_Notify_At__c, 'Save cancels it.');

            // A new timer on the same row, which now has hours: discard keeps the row.
            itemId = (Id) TimesheetTimerController.startTimer(projectId, 'Testing').get('id');
            System.assertNotEquals(null, reload(itemId).Next_Notify_At__c);
            update new Timesheet_Line_Item__c(Id = itemId, Duration__c = 1);
            TimesheetTimerController.discardTimer(itemId);
            Timesheet_Line_Item__c discarded = reload(itemId);
            System.assertEquals(null, discarded.Timer_Data__c);
            System.assertEquals(null, discarded.Next_Notify_At__c, 'Discard cancels it.');
        }
    }
}
