/**
 * Bell notifications for running timers. TimesheetTimerController.setState writes when the next
 * one is due (Next_Notify_At__c); the record-triggered flow
 * Timesheet_Timer_Notification waits for that time on a scheduled path and calls processDue.
 * No scheduled Apex jobs are used, so any number of timers can run at once.
 *
 * Stage 1 warns an hour before the workday hours and stage 2 stops the timer there; stages 3
 * and 4 do the same for the daily maximum. A stage the controller has already stopped
 * (applyLimit) is still notified; a pause, save or discard clears the due time instead.
 *
 * Without sharing: the scheduled path runs as the Automated Process user for every employee's
 * timer, and only touches the rows the flow handed over.
 */
public without sharing class TimesheetTimerNotificationService {

    private static final String NOTIFICATION_TYPE = 'Timesheet_Timer_Notification';
    private static final Long EARLY_TOLERANCE_MS = 60000L; // flow wake-ups are never this early

    @TestVisible
    private static List<Messaging.CustomNotification> sent = new List<Messaging.CustomNotification>();
    @TestVisible
    private static Boolean forceNotificationFailure = false;

    @InvocableMethod(label='Process Due Timer Notifications' description='Sends due timer notifications and stops timers at their limit.')
    public static void processDue(List<Id> lineItemIds) {
        Long nowMs = Datetime.now().getTime();
        List<Timesheet_Line_Item__c> changed = new List<Timesheet_Line_Item__c>();

        for (Timesheet_Line_Item__c item : [
            SELECT Id, Duration__c, Timer_Data__c, Next_Notify_At__c, Employee__r.User__c
            FROM Timesheet_Line_Item__c
            WHERE Id IN :lineItemIds AND Timer_Data__c != null AND Next_Notify_At__c != null
            FOR UPDATE
        ]) {
            // One unreadable row must not stop the notifications of the other timers in the batch.
            try {
                changed.add(process(item, nowMs));
            } catch (Exception e) {
                System.debug(LoggingLevel.ERROR, 'Timer notification skipped for ' + item.Id + ': ' + e.getMessage());
                changed.add(new Timesheet_Line_Item__c(Id = item.Id, Next_Notify_At__c = null));
            }
        }

        // One row failing (e.g. a validation rule) must not block the other timers.
        for (Database.SaveResult result : Database.update(changed, false)) {
            if (!result.isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'Timer notification update failed for ' + result.getId() + ': ' + result.getErrors()[0].getMessage());
            }
        }
    }

    // Sends what the timer's state says is due and returns the row to update. Next_Notify_At__c
    // only wakes the flow; the stage and its time come from Timer_Data__c, and the due time is
    // written again from the state so a wrong value re-arms the flow at the right time.
    private static Timesheet_Line_Item__c process(Timesheet_Line_Item__c item, Long nowMs) {
        TimesheetTimerController.TimerState state = (TimesheetTimerController.TimerState)
            JSON.deserialize(item.Timer_Data__c, TimesheetTimerController.TimerState.class);
        TimesheetTimerController.Notification due = TimesheetTimerController.dueNotification(state, item.Duration__c);
        // Not due yet (e.g. moved later after this wake-up was queued): send nothing.
        if (due != null && due.dueMs <= nowMs + EARLY_TOLERANCE_MS) {
            if (notify(item, due.stage)) {
                state.markStageSent(due.stage);
            }
            if (due.stage == 2 || due.stage == 4) {
                TimesheetTimerController.stopAtLimit(state, item.Duration__c);
            }
        }
        Timesheet_Line_Item__c row = new Timesheet_Line_Item__c(Id = item.Id);
        TimesheetTimerController.setState(row, state, item.Duration__c);
        return row;
    }

    private static Boolean notify(Timesheet_Line_Item__c item, Integer stage) {
        Id recipient = item.Employee__r?.User__c;
        Id typeId = notificationTypeId();
        if (recipient == null || typeId == null || forceNotificationFailure) {
            System.debug(LoggingLevel.WARN, 'Timer notification ' + stage + ' not sent for ' + item.Id + ': no recipient or notification type.');
            return false;
        }
        Messaging.CustomNotification notification = new Messaging.CustomNotification();
        notification.setNotificationTypeId(typeId);
        notification.setTargetId(item.Id);
        notification.setTitle(stage == 2 || stage == 4 ? 'Timesheet Timer Stopped' : 'Timesheet Timer Warning');
        notification.setBody(bodyOf(stage));
        try {
            notification.send(new Set<String>{ recipient });
            sent.add(notification);
            return true;
        } catch (Exception e) {
            System.debug(LoggingLevel.ERROR, 'Timer notification ' + stage + ' failed for ' + item.Id + ': ' + e.getMessage());
            return false;
        }
    }

    @TestVisible
    private static String bodyOf(Integer stage) {
        if (stage == 2) {
            return 'Your timer is stopped according to the org per day time limit. Still, if you are working, you can continue the timer.';
        }
        if (stage == 4) {
            return 'Your timer is stopped according to the org per day max time limit. Please save or discard timer hours.';
        }
        return 'Your timer is still running and after 1 hour it will stop automatically.';
    }

    private static Id cachedTypeId;
    private static Boolean typeLookedUp = false;

    private static Id notificationTypeId() {
        if (!typeLookedUp) {
            List<CustomNotificationType> types = [SELECT Id FROM CustomNotificationType WHERE DeveloperName = :NOTIFICATION_TYPE LIMIT 1];
            cachedTypeId = types.isEmpty() ? null : types[0].Id;
            typeLookedUp = true;
        }
        return cachedTypeId;
    }
}
