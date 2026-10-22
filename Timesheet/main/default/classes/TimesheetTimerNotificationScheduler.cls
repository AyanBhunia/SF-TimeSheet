public with sharing class TimesheetTimerNotificationScheduler implements Schedulable {

    private Id lineItemId;
    private Integer stage;

    public TimesheetTimerNotificationScheduler() {}

    public TimesheetTimerNotificationScheduler(Id lineItemId, Integer stage) {
        this.lineItemId = lineItemId;
        this.stage = stage;
    }

    public void execute(SchedulableContext context) {
        TimesheetTimerNotificationService.executeStage(this.lineItemId, this.stage);
    }
}
