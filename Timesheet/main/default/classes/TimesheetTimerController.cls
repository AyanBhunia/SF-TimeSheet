/**
 * Timesheet timer. A running timer is a normal Timesheet_Line_Item__c for today's
 * project + activity whose Timer_Data__c holds the timer state as JSON. The clock shows the
 * row's Duration__c plus the timer's time; it stops by itself at the workday hours and can
 * be continued up to the daily maximum. Saving adds the timer's time to Duration__c of that
 * row only and clears Timer_Data__c.
 */
public with sharing class TimesheetTimerController {

    private static final Long MS_PER_HOUR = 1000L * 60 * 60;
    private static final Decimal DEFAULT_WORKDAY_HOURS = 8;
    private static final Decimal MAX_DAY_HOURS = 24;

    // Timer state kept in Timer_Data__c.
    public class TimerState {
        public Long startMs;         // when the timer was started
        public Long pausedMs;        // total time spent paused
        public Long pauseStartMs;    // set while paused
        public Boolean newItem;      // the timer created the line item (discard deletes it)
        public Decimal limitHours;   // row total at which the current run stops by itself
        public Decimal limitBase;    // row hours when this run started or continued
        public Boolean autoStopped;  // the pause was caused by reaching limitHours
        public Boolean warning30Sent;
        public String jobId;         // active CronTrigger Id
        public Integer stageSent;    // highest notification stage sent (1 to 4)
        public transient String schedulingError; // in-memory only status

        public Boolean isStageSent(Integer stage) {
            if (stage == 1) return (stageSent != null && stageSent >= 1) || warning30Sent == true;
            if (stage == 2) return stageSent != null && stageSent >= 2;
            if (stage == 3) return stageSent != null && stageSent >= 3;
            if (stage == 4) return stageSent != null && stageSent >= 4;
            return false;
        }

        public void markStageSent(Integer stage) {
            if (stageSent == null || stage > stageSent) {
                stageSent = stage;
            }
            if (stage == 1) {
                warning30Sent = true;
            }
        }
    }

    @AuraEnabled
    public static Map<String, Object> getTimerInitData() {
        try {
            Id employeeId = currentEmployeeId();
            if (employeeId == null) {
                throw error('No Employee record found for the current user.');
            }

            List<Map<String, Object>> projectOptions = new List<Map<String, Object>>();
            for (Project_Employee__c pe : [
                SELECT Project__c, Project__r.Name
                FROM Project_Employee__c
                WHERE Employee__c = :employeeId AND Project__r.Active__c = true
                WITH SECURITY_ENFORCED
                ORDER BY Project__r.Name
            ]) {
                projectOptions.add(new Map<String, Object>{ 'label' => pe.Project__r.Name, 'value' => pe.Project__c });
            }

            List<Timesheet_Line_Item__c> running = [
                SELECT Id FROM Timesheet_Line_Item__c
                WHERE Employee__c = :employeeId AND Timer_Data__c != null
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            return new Map<String, Object>{
                'employeeId' => employeeId,
                'projects' => projectOptions,
                'activeTimer' => running.isEmpty() ? null : toTimerMap(ownedTimer(running[0].Id))
            };
        } catch (Exception e) {
            throw error(messageOf(e));
        }
    }

    @AuraEnabled
    public static Map<String, Object> startTimer(Id projectId, String activity) {
        try {
            Id employeeId = currentEmployeeId();
            if (employeeId == null) {
                throw error('No Employee record found for the current user.');
            }
            if (runningTimerCount() > 0) {
                throw error('A timer is already running, so a new one was not started.');
            }
            if ([SELECT Id FROM Project_Employee__c WHERE Employee__c = :employeeId AND Project__c = :projectId AND Project__r.Active__c = true WITH SECURITY_ENFORCED LIMIT 1].isEmpty()) {
                throw error('This project is not active or not assigned to you.');
            }

            Date today = Date.today();
            Timesheet__c timesheet = timesheetFor(employeeId, today);

            // The duplicate rule allows one row per project + activity + day, so reuse it.
            List<Timesheet_Line_Item__c> existing = [
                SELECT Id, Duration__c FROM Timesheet_Line_Item__c
                WHERE Timesheet__c = :timesheet.Id AND Project__c = :projectId
                AND Activity__c = :activity AND Date__c = :today
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            Decimal baseHours = existing.isEmpty() ? 0 : nz(existing[0].Duration__c);
            assertBelowCap(baseHours);

            TimerState state = new TimerState();
            state.startMs = Datetime.now().getTime();
            state.pausedMs = 0;
            state.limitHours = nextLimit(baseHours);
            state.limitBase = baseHours;
            state.autoStopped = false;

            Timesheet_Line_Item__c item;
            if (!existing.isEmpty()) {
                state.newItem = false;
                item = new Timesheet_Line_Item__c(Id = existing[0].Id, Timer_Data__c = JSON.serialize(state));
                update Security.stripInaccessible(AccessType.UPDATABLE, new List<Timesheet_Line_Item__c>{ item }).getRecords();
            } else {
                state.newItem = true;
                item = new Timesheet_Line_Item__c(
                    Timesheet__c = timesheet.Id,
                    Employee__c = employeeId,
                    Project__c = projectId,
                    Activity__c = activity,
                    Type__c = 'Attendance',
                    Date__c = today,
                    Duration__c = 0, // field default is 8
                    Timer_Data__c = JSON.serialize(state)
                );
                List<SObject> inserted = Security.stripInaccessible(AccessType.CREATABLE, new List<Timesheet_Line_Item__c>{ item }).getRecords();
                insert inserted;
                item.Id = inserted[0].Id;
            }

            TimesheetTimerNotificationService.scheduleNextStage(item.Id, state);
            if (state.jobId != null) {
                update Security.stripInaccessible(AccessType.UPDATABLE, new List<Timesheet_Line_Item__c>{
                    new Timesheet_Line_Item__c(Id = item.Id, Timer_Data__c = JSON.serialize(state))
                }).getRecords();
            }

            return toTimerMap(ownedTimer(item.Id));
        } catch (Exception e) {
            // Two starts at once (double click, two tabs): the loser hits the duplicate rule.
            if (e instanceof DmlException && runningTimerCount() > 0) {
                throw error('A timer is already running, so a new one was not started.');
            }
            throw error(messageOf(e));
        }
    }

    @AuraEnabled
    public static Map<String, Object> pauseTimer(Id lineItemId) {
        try {
            Timesheet_Line_Item__c item = ownedTimer(lineItemId);
            TimerState state = applyLimit(item, stateOf(item));
            if (state.pauseStartMs == null) {
                state.pauseStartMs = Datetime.now().getTime();
                TimesheetTimerNotificationService.cancelNotificationJob(state.jobId);
                state.jobId = null;
                saveState(item.Id, state);
            }
            return toTimerMap(ownedTimer(item.Id));
        } catch (Exception e) {
            throw error(messageOf(e));
        }
    }

    @AuraEnabled
    public static Map<String, Object> continueTimer(Id lineItemId) {
        try {
            Timesheet_Line_Item__c item = ownedTimer(lineItemId);
            TimerState state = applyLimit(item, stateOf(item));
            if (state.pauseStartMs != null) {
                // All of a timer's hours go on its start day's row.
                if (item.Date__c != Date.today()) {
                    throw error('This timer was started on ' + item.Date__c.format() + ' and can only be saved or discarded now.');
                }
                Decimal total = nz(item.Duration__c) + workedHours(state);
                assertBelowCap(total);
                state.pausedMs = nz(state.pausedMs) + (Datetime.now().getTime() - state.pauseStartMs);
                state.pauseStartMs = null;
                state.limitHours = nextLimit(total);
                state.limitBase = nz(item.Duration__c);
                state.autoStopped = false;
                TimesheetTimerNotificationService.cancelNotificationJob(state.jobId);
                state.jobId = null;
                TimesheetTimerNotificationService.scheduleNextStage(item.Id, state);
                saveState(item.Id, state);
            }
            return toTimerMap(ownedTimer(item.Id));
        } catch (Exception e) {
            throw error(messageOf(e));
        }
    }

    // Adds the timer's time to this row only. The 24h daily limit is left to the
    // existing validation; its message is shown if the save is rejected.
    @AuraEnabled
    public static void saveTimer(Id lineItemId, String description) {
        try {
            Timesheet_Line_Item__c item = ownedTimer(lineItemId);
            assertEditable(item.Timesheet__r.Status__c);
            if (item.Project__r.Active__c != true) {
                throw error('Project ' + item.Project__r.Name + ' is no longer active. Discard the timer instead.');
            }

            TimerState state = applyLimit(item, stateOf(item));
            TimesheetTimerNotificationService.cancelNotificationJob(state.jobId);
            Timesheet_Line_Item__c row = new Timesheet_Line_Item__c(
                Id = item.Id,
                Duration__c = nz(item.Duration__c) + workedHours(state).setScale(2),
                Timer_Data__c = null
            );
            if (description != null) {
                row.Description__c = description;
            }
            update Security.stripInaccessible(AccessType.UPDATABLE, new List<Timesheet_Line_Item__c>{ row }).getRecords();
        } catch (Exception e) {
            throw error(messageOf(e));
        }
    }

    @AuraEnabled
    public static void discardTimer(Id lineItemId) {
        try {
            Timesheet_Line_Item__c item = ownedTimer(lineItemId);
            TimerState state = stateOf(item);
            TimesheetTimerNotificationService.cancelNotificationJob(state.jobId);
            // Duration__c is only changed on save, so discarding just undoes the start.
            if (state.newItem == true && nz(item.Duration__c) == 0
                && Schema.SObjectType.Timesheet_Line_Item__c.isDeletable()) {
                delete item;
            } else {
                update Security.stripInaccessible(AccessType.UPDATABLE, new List<Timesheet_Line_Item__c>{
                    new Timesheet_Line_Item__c(Id = item.Id, Timer_Data__c = null)
                }).getRecords();
            }
        } catch (Exception e) {
            throw error(messageOf(e));
        }
    }

    // Stops a running timer at the moment the row total reached limitHours. Worked out
    // whenever the timer is read, so no scheduled job is needed. Uses the row hours from
    // when the run started, so an edit while running never cuts time already worked.
    private static TimerState applyLimit(Timesheet_Line_Item__c item, TimerState state) {
        if (state.pauseStartMs != null) {
            return state;
        }
        Decimal limitHours = state.limitHours != null ? state.limitHours : workdayHours();
        Decimal limitBase = state.limitBase != null ? state.limitBase : nz(item.Duration__c);
        Long workStartMs = state.startMs + nz(state.pausedMs);
        Long stopMs = workStartMs + ((limitHours - limitBase) * MS_PER_HOUR).longValue();
        if (Datetime.now().getTime() >= stopMs) {
            state.pauseStartMs = Math.max(stopMs, workStartMs);
            state.autoStopped = true;
            saveState(item.Id, state);
        }
        return state;
    }

    // The first run stops at the workday hours; once those are reached, at the daily maximum.
    private static Decimal nextLimit(Decimal totalHours) {
        return totalHours >= workdayHours() ? capHours() : workdayHours();
    }

    private static void assertBelowCap(Decimal totalHours) {
        if (totalHours >= capHours()) {
            throw error('This line item already has ' + totalHours.setScale(2) + 'h, the most allowed for one day.');
        }
    }

    private static Decimal workdayHours() {
        Decimal value = LeaveValidator.settings().Working_Hours_Per_Day__c;
        value = value == null || value <= 0 ? DEFAULT_WORKDAY_HOURS : value;
        return Math.min(value, capHours());
    }

    private static Decimal capHours() {
        Decimal value = LeaveValidator.settings().Maximum_Working_Hrs_Per_Day__c;
        return value == null || value <= 0 ? MAX_DAY_HOURS : Math.min(value, MAX_DAY_HOURS);
    }

    // Time this timer has run, in hours, up to now or the pause.
    private static Decimal workedHours(TimerState state) {
        Long endMs = state.pauseStartMs != null ? state.pauseStartMs : Datetime.now().getTime();
        return Decimal.valueOf(Math.max(0L, endMs - state.startMs - nz(state.pausedMs))) / MS_PER_HOUR;
    }

    private static Integer runningTimerCount() {
        Id employeeId = currentEmployeeId();
        return [SELECT COUNT() FROM Timesheet_Line_Item__c WHERE Employee__c = :employeeId AND Timer_Data__c != null WITH SECURITY_ENFORCED];
    }

    // Timesheets are created by the weekly flow; the timer only attaches to them.
    private static Timesheet__c timesheetFor(Id employeeId, Date day) {
        List<Timesheet__c> timesheets = [
            SELECT Id, Status__c FROM Timesheet__c
            WHERE Employee__c = :employeeId AND Start_Date__c <= :day AND End_Date__c >= :day
            WITH SECURITY_ENFORCED
            ORDER BY Start_Date__c DESC, CreatedDate DESC // overlapping timesheets: use the latest
            LIMIT 1
        ];
        if (timesheets.isEmpty()) {
            throw error('No timesheet exists for ' + day.format() + '. Please contact your manager or HR to create it.');
        }
        assertEditable(timesheets[0].Status__c);
        return timesheets[0];
    }

    // Hours must not change once a timesheet is submitted or approved.
    private static void assertEditable(String timesheetStatus) {
        if (timesheetStatus == 'Submitted' || timesheetStatus == 'Approved') {
            throw error('This timesheet is already ' + timesheetStatus.toLowerCase() + ', so the timer cannot change it. Discard the timer instead.');
        }
    }

    private static Id currentEmployeeId() {
        List<Employee__c> employees = [SELECT Id FROM Employee__c WHERE User__c = :UserInfo.getUserId() WITH SECURITY_ENFORCED LIMIT 1];
        return employees.isEmpty() ? null : employees[0].Id;
    }

    // The running timer, only if it belongs to the current user.
    private static Timesheet_Line_Item__c ownedTimer(Id lineItemId) {
        Id userId = UserInfo.getUserId();
        List<Timesheet_Line_Item__c> items = [
            SELECT Id, Date__c, Duration__c, Description__c, Activity__c, Employee__c, Timer_Data__c,
                   Project__c, Project__r.Name, Project__r.Active__c, Timesheet__r.Status__c
            FROM Timesheet_Line_Item__c
            WHERE Id = :lineItemId AND Employee__r.User__c = :userId AND Timer_Data__c != null
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
        if (items.isEmpty()) {
            throw error('This timer is no longer running. It was saved, discarded or deleted somewhere else.');
        }
        return items[0];
    }

    private static TimerState stateOf(Timesheet_Line_Item__c item) {
        return (TimerState) JSON.deserialize(item.Timer_Data__c, TimerState.class);
    }

    private static void saveState(Id lineItemId, TimerState state) {
        update Security.stripInaccessible(AccessType.UPDATABLE, new List<Timesheet_Line_Item__c>{
            new Timesheet_Line_Item__c(Id = lineItemId, Timer_Data__c = JSON.serialize(state))
        }).getRecords();
    }

    // Plain keys so the LWC never deals with namespace prefixes.
    private static Map<String, Object> toTimerMap(Timesheet_Line_Item__c item) {
        TimerState state = applyLimit(item, stateOf(item));
        return new Map<String, Object>{
            'id' => item.Id,
            'projectId' => item.Project__c,
            'projectName' => item.Project__r.Name,
            'activity' => item.Activity__c,
            'description' => item.Description__c,
            'timerDate' => item.Date__c,
            'serverToday' => Date.today(), // the user's Salesforce time zone, not the browser's
            'startMs' => state.startMs,
            'pausedMs' => nz(state.pausedMs),
            'pauseStartMs' => state.pauseStartMs,
            'baseHours' => nz(item.Duration__c),
            'limitHours' => state.limitHours != null ? state.limitHours : workdayHours(),
            'limitBase' => state.limitBase != null ? state.limitBase : nz(item.Duration__c),
            'workdayHours' => workdayHours(),
            'capHours' => capHours(),
            'autoStopped' => state.autoStopped == true,
            'serverNowMs' => Datetime.now().getTime()
        };
    }

    private static Long nz(Long value) {
        return value == null ? 0 : value;
    }

    private static Decimal nz(Decimal value) {
        return value == null ? 0 : value;
    }

    // Validation rule text instead of the raw DML error.
    private static String messageOf(Exception e) {
        return e instanceof DmlException ? ((DmlException) e).getDmlMessage(0) : e.getMessage();
    }

    // AuraHandledException.getMessage() is not readable unless setMessage is called,
    // which matters because the catch blocks re-wrap exceptions.
    private static AuraHandledException error(String message) {
        AuraHandledException e = new AuraHandledException(message);
        e.setMessage(message);
        return e;
    }
}
