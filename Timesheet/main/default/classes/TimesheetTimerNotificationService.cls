/**
 * @description Service class managing the 4-stage Chained Scheduled Apex notifications for Timesheet Timers.
 *              Handles stage calculations, job creation, chaining, cancellation, state validation, and Custom Notifications.
 */
public with sharing class TimesheetTimerNotificationService {

    private static final Long MS_PER_HOUR = 3600000L;
    private static final String NOTIFICATION_DEV_NAME = 'Timesheet_Timer_Notification';

    private static Id cachedNotificationTypeId;

    @TestVisible
    private static Boolean forceScheduleFailure = false;
    @TestVisible
    private static Boolean forceNotificationFailure = false;
    @TestVisible
    private static Boolean forceGovernorLimitReached = false;
    @TestVisible
    private static MetadataLimits mockLimits;
    @TestVisible
    private static Integer lastSentStage;
    @TestVisible
    private static String lastSentTitle;
    @TestVisible
    private static String lastSentBody;
    @TestVisible
    private static Id lastSentRecipient;
    @TestVisible
    private static List<Integer> sentStagesList = new List<Integer>();
    @TestVisible
    private static List<String> sentTitlesList = new List<String>();
    @TestVisible
    private static List<String> sentBodiesList = new List<String>();

    public class MetadataLimits {
        public Decimal dailyHours;
        public Decimal maxHours;
        public Boolean isValid;
        public String errorMessage;
    }

    /**
     * @description Dynamically retrieves daily and maximum working hours from Custom Metadata.
     *              Does not use hardcoded 8h or 24h fallbacks. Handles missing or invalid metadata safely.
     */
    public static MetadataLimits getLimits() {
        MetadataLimits limits;
        if (mockLimits != null) {
            limits = mockLimits;
        } else {
            limits = new MetadataLimits();
            Timesheet_Default_Value__mdt settings = LeaveValidator.settings();

            Decimal daily = settings != null ? settings.Working_Hours_Per_Day__c : null;
            Decimal max = settings != null ? settings.Maximum_Working_Hrs_Per_Day__c : null;

            if (daily == null || daily <= 0) {
                limits.isValid = false;
                limits.errorMessage = 'Working_Hours_Per_Day__c is missing or non-positive in Custom Metadata.';
                return limits;
            }
            limits.dailyHours = daily;

            if (max == null || max <= 0) {
                limits.isValid = false;
                limits.errorMessage = 'Maximum_Working_Hrs_Per_Day__c is missing or non-positive in Custom Metadata.';
                return limits;
            }
            limits.maxHours = max;
            limits.isValid = true;
        }

        // If maximum limit is less than daily limit, handle safely by capping maximum to daily limit
        if (limits.isValid && limits.dailyHours != null && limits.maxHours != null && limits.maxHours < limits.dailyHours) {
            limits.maxHours = limits.dailyHours;
        }

        return limits;
    }

    /**
     * @description Schedules the next applicable stage for a running timer.
     *              Called during startTimer() and continueTimer().
     */
    public static void scheduleNextStage(Id lineItemId, TimesheetTimerController.TimerState state) {
        if (lineItemId == null || state == null || state.pauseStartMs != null || state.autoStopped == true) {
            return;
        }

        MetadataLimits limits = getLimits();
        if (!limits.isValid) {
            state.schedulingError = limits.errorMessage;
            System.debug(LoggingLevel.WARN, 'TimesheetTimerNotificationService: ' + limits.errorMessage);
            return;
        }

        Decimal limitBase = state.limitBase != null ? state.limitBase : 0.0;
        Long pausedMs = state.pausedMs != null ? state.pausedMs : 0L;
        Long elapsedMs = Math.max(0L, Datetime.now().getTime() - state.startMs - pausedMs);
        Decimal activeHours = Decimal.valueOf(elapsedMs) / MS_PER_HOUR;
        Decimal totalHours = limitBase + activeHours;

        // Determine next stage
        Integer nextStage = null;
        Decimal targetTotalHours = null;

        if (totalHours < limits.dailyHours && !state.isStageSent(2)) {
            // First leg: approaching or at daily limit
            if (limits.dailyHours > 1.0 && totalHours < (limits.dailyHours - 1.0) && !state.isStageSent(1)) {
                nextStage = 1;
                targetTotalHours = limits.dailyHours - 1.0;
            } else {
                nextStage = 2;
                targetTotalHours = limits.dailyHours;
            }
        } else if (limits.maxHours > limits.dailyHours) {
            // Second leg: timer continued past daily limit towards maximum limit
            if (limits.maxHours > (limits.dailyHours + 1.0) && totalHours < (limits.maxHours - 1.0) && !state.isStageSent(3)) {
                nextStage = 3;
                targetTotalHours = limits.maxHours - 1.0;
            } else if (totalHours < limits.maxHours && !state.isStageSent(4)) {
                nextStage = 4;
                targetTotalHours = limits.maxHours;
            }
        }

        if (nextStage != null && targetTotalHours != null) {
            scheduleStage(lineItemId, state, nextStage, targetTotalHours);
        } else {
            // No further stages needed
            state.jobId = null;
        }
    }

    /**
     * @description Schedules a specific stage job at the exact calculated target timestamp.
     */
    public static void scheduleStage(Id lineItemId, TimesheetTimerController.TimerState state, Integer stage, Decimal targetTotalHours) {
        if (lineItemId == null || state == null) {
            return;
        }

        // Cancel previous pending job for this timer if present
        if (String.isNotBlank(state.jobId)) {
            cancelNotificationJob(state.jobId);
            state.jobId = null;
        }

        // Check platform governor limit (100 scheduled jobs)
        Integer activeJobCount = 0;
        try {
            activeJobCount = [
                SELECT COUNT()
                FROM CronTrigger
                WHERE State NOT IN ('DELETED', 'ERROR', 'COMPLETE')
            ];
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'Could not query CronTrigger count: ' + ex.getMessage());
        }

        if (activeJobCount >= 100 || forceGovernorLimitReached) {
            String errorMsg = 'Scheduled jobs org limit reached (' + activeJobCount + '/100). Notification job skipped safely.';
            System.debug(LoggingLevel.ERROR, 'TimesheetTimerNotificationService: ' + errorMsg);
            state.schedulingError = errorMsg;
            return;
        }

        if (forceScheduleFailure) {
            state.schedulingError = 'Simulated scheduling failure for testing.';
            return;
        }

        Decimal limitBase = state.limitBase != null ? state.limitBase : 0.0;
        Long pausedMs = state.pausedMs != null ? state.pausedMs : 0L;
        Long targetMs = state.startMs + pausedMs + ((targetTotalHours - limitBase) * MS_PER_HOUR).longValue();
        Long nowMs = Datetime.now().getTime();

        Datetime fireTime;
        if (targetMs <= nowMs + 1000L) {
            // Target is already reached or within 1 second; schedule to fire 2 seconds in future
            fireTime = Datetime.now().addSeconds(2);
        } else {
            fireTime = Datetime.newInstance(targetMs);
        }

        String cronExp = fireTime.second() + ' ' +
                         fireTime.minute() + ' ' +
                         fireTime.hour() + ' ' +
                         fireTime.day() + ' ' +
                         fireTime.month() + ' ? ' +
                         fireTime.year();

        String jobName = 'Timer_' + lineItemId + '_S' + stage + '_' + fireTime.getTime();

        try {
            String jobId = System.schedule(
                jobName,
                cronExp,
                new TimesheetTimerNotificationScheduler(lineItemId, stage)
            );
            state.jobId = jobId;
            state.schedulingError = null;
            System.debug(LoggingLevel.INFO, 'TimesheetTimerNotificationService: Scheduled ' + jobName + ' [JobId: ' + jobId + ']');
        } catch (AsyncException ae) {
            System.debug(LoggingLevel.ERROR, 'TimesheetTimerNotificationService: AsyncException: ' + ae.getMessage());
            state.schedulingError = ae.getMessage();
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'TimesheetTimerNotificationService: Scheduling exception: ' + ex.getMessage());
            state.schedulingError = ex.getMessage();
        }
    }

    /**
     * @description Cancels only the specific scheduled job associated with the provided CronTrigger Id.
     *              Never cancels another employee's timer job or unrelated scheduled jobs.
     */
    public static void cancelNotificationJob(String jobId) {
        if (String.isBlank(jobId)) {
            return;
        }

        try {
            List<CronTrigger> jobs = [
                SELECT Id, State
                FROM CronTrigger
                WHERE Id = :jobId
                AND State NOT IN ('DELETED', 'ERROR', 'COMPLETE')
                LIMIT 1
            ];
            if (!jobs.isEmpty()) {
                System.abortJob(jobs[0].Id);
                System.debug(LoggingLevel.INFO, 'TimesheetTimerNotificationService: Successfully aborted job ' + jobs[0].Id);
            }
        } catch (Exception ex) {
            System.debug(LoggingLevel.WARN, 'TimesheetTimerNotificationService: Could not abort job ' + jobId + ': ' + ex.getMessage());
        }
    }

    /**
     * @description Executes the logic for a specific stage when its scheduled job fires.
     *              Re-queries record FOR UPDATE, revalidates state, dispatches Custom Notification,
     *              and chains the next stage.
     */
    public static void executeStage(Id lineItemId, Integer stage) {
        if (lineItemId == null || stage == null) {
            return;
        }

        List<Timesheet_Line_Item__c> items = [
            SELECT Id, Duration__c, Timer_Data__c, Employee__c, Employee__r.User__c,
                   Project__r.Name, Activity__c
            FROM Timesheet_Line_Item__c
            WHERE Id = :lineItemId
            FOR UPDATE
        ];

        if (items.isEmpty()) {
            System.debug(LoggingLevel.INFO, 'TimesheetTimerNotificationService: Line item ' + lineItemId + ' deleted. Skipping execution.');
            return;
        }

        Timesheet_Line_Item__c item = items[0];
        if (String.isBlank(item.Timer_Data__c)) {
            System.debug(LoggingLevel.INFO, 'TimesheetTimerNotificationService: Timer_Data__c is blank (saved or discarded). Skipping.');
            return;
        }

        TimesheetTimerController.TimerState state;
        try {
            state = (TimesheetTimerController.TimerState) JSON.deserialize(
                item.Timer_Data__c,
                TimesheetTimerController.TimerState.class
            );
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'TimesheetTimerNotificationService: Failed to parse Timer_Data__c: ' + ex.getMessage());
            return;
        }

        if (state == null) {
            return;
        }

        // Revalidate: Manual pause stops all stages; auto-stop only skips warning stages (1 and 3)
        Boolean isManuallyPaused = (state.pauseStartMs != null && state.autoStopped != true);
        if (isManuallyPaused) {
            System.debug(LoggingLevel.INFO, 'TimesheetTimerNotificationService: Timer is manually paused. Skipping stage ' + stage);
            return;
        }
        if ((stage == 1 || stage == 3) && (state.pauseStartMs != null || state.autoStopped == true)) {
            System.debug(LoggingLevel.INFO, 'TimesheetTimerNotificationService: Timer is paused or auto-stopped. Skipping warning stage ' + stage);
            return;
        }

        // Check if stage already processed
        if (state.isStageSent(stage)) {
            System.debug(LoggingLevel.INFO, 'TimesheetTimerNotificationService: Stage ' + stage + ' already sent. Skipping duplicate.');
            return;
        }

        MetadataLimits limits = getLimits();
        if (!limits.isValid) {
            System.debug(LoggingLevel.WARN, 'TimesheetTimerNotificationService: Invalid metadata limits during stage execution.');
            return;
        }

        String title;
        String body;

        switch on stage {
            when 1 {
                title = 'Timesheet Timer Warning';
                body = 'Your timer is still running and after 1 hour it will stop automatically.';
            }
            when 2 {
                title = 'Timesheet Timer Stopped';
                body = 'Your timer is stopped according to the org per day time limit. Still, if you are working, you can continue the timer.';
            }
            when 3 {
                title = 'Timesheet Timer Warning';
                body = 'Your timer is still running and after 1 hour it will stop automatically.';
            }
            when 4 {
                title = 'Timesheet Timer Stopped';
                body = 'Your timer is stopped according to the org per day max time limit. Please save or discard timer hours.';
            }
            when else {
                System.debug(LoggingLevel.WARN, 'TimesheetTimerNotificationService: Unknown stage ' + stage);
                return;
            }
        }

        // Dispatch Custom Notification
        Boolean notificationSent = false;
        Id recipientUserId = item.Employee__r != null ? item.Employee__r.User__c : null;
        Id notifTypeId = getNotificationTypeId();

        if (recipientUserId != null && notifTypeId != null && !forceNotificationFailure) {
            try {
                Messaging.CustomNotification notif = new Messaging.CustomNotification();
                notif.setNotificationTypeId(notifTypeId);
                notif.setTargetId(item.Id);
                notif.setTitle(title);
                notif.setBody(body);
                notif.send(new Set<String>{ String.valueOf(recipientUserId) });
                notificationSent = true;

                lastSentStage = stage;
                lastSentTitle = title;
                lastSentBody = body;
                lastSentRecipient = recipientUserId;
                sentStagesList.add(stage);
                sentTitlesList.add(title);
                sentBodiesList.add(body);
                System.debug(LoggingLevel.INFO, 'TimesheetTimerNotificationService: Custom notification sent for stage ' + stage + ' to user ' + recipientUserId);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'TimesheetTimerNotificationService: Failed to send Custom Notification: ' + ex.getMessage());
                // Do not mark stage as sent so it remains retryable
            }
        } else if (forceNotificationFailure) {
            System.debug(LoggingLevel.WARN, 'TimesheetTimerNotificationService: Simulated notification failure.');
        } else {
            System.debug(LoggingLevel.WARN, 'TimesheetTimerNotificationService: Missing recipient user or notification type.');
        }

        if (notificationSent) {
            state.markStageSent(stage);
        }

        // Stage execution actions & chaining
        Decimal limitBase = state.limitBase != null ? state.limitBase : (item.Duration__c != null ? item.Duration__c : 0.0);
        Long workStartMs = state.startMs + (state.pausedMs != null ? state.pausedMs : 0L);

        if (stage == 1) {
            // Chain Stage 2
            scheduleStage(item.Id, state, 2, limits.dailyHours);
        } else if (stage == 2) {
            // Auto-stop at daily limit. Reuse existing auto-stop logic. Do not chain Stage 3!
            Long stopMs = workStartMs + ((limits.dailyHours - limitBase) * MS_PER_HOUR).longValue();
            state.pauseStartMs = Math.max(stopMs, workStartMs);
            state.autoStopped = true;
            state.jobId = null;
        } else if (stage == 3) {
            // Chain Stage 4
            scheduleStage(item.Id, state, 4, limits.maxHours);
        } else if (stage == 4) {
            // Final auto-stop at maximum limit. Permanent stop.
            Long stopMs = workStartMs + ((limits.maxHours - limitBase) * MS_PER_HOUR).longValue();
            state.pauseStartMs = Math.max(stopMs, workStartMs);
            state.autoStopped = true;
            state.jobId = null;
        }

        // Persist updated timer state
        item.Timer_Data__c = JSON.serialize(state);
        try {
            update item;
            System.debug(LoggingLevel.INFO, 'TimesheetTimerNotificationService: Successfully updated Timer_Data__c for stage ' + stage);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'TimesheetTimerNotificationService: Failed to update line item: ' + ex.getMessage());
        }
    }

    private static Id getNotificationTypeId() {
        if (cachedNotificationTypeId == null) {
            List<CustomNotificationType> types = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = :NOTIFICATION_DEV_NAME
                LIMIT 1
            ];
            if (!types.isEmpty()) {
                cachedNotificationTypeId = types[0].Id;
            }
        }
        return cachedNotificationTypeId;
    }
}
