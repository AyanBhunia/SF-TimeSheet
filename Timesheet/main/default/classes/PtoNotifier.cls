/**
 * @description Salesforce bell notifications for PTO requests (custom notification type PTO_Request_Update): to the
 *              approver when a request is submitted, to the request owner when it is approved or rejected. Sent from
 *              Apex, so they go out whether or not the Leave Approval process (and its emails) is deployed.
 *              Each notification opens the request in the PTO tab. Nobody is notified of their own action, and a
 *              notification that fails to send never blocks the request.
 */
public without sharing class PtoNotifier {

    private static final String TYPE_NAME = 'PTO_Request_Update';
    private static final Integer TITLE_MAX = 250;
    private static final Integer BODY_MAX = 750;

    private static Id typeId;
    private static Boolean isTypeLoaded = false;

    /**
     * @description Tells each request's approver that it is waiting for them.
     */
    public static void submitted(Set<Id> requestIds) {
        for (PTO_Request__c r : requests(requestIds)) {
            String body = summary(r) + (String.isBlank(r.Notes__c) ? '' : '\nReason: ' + r.Notes__c);
            send(r.Approver__c, 'PTO request ' + r.Name + ' from ' + r.Employee__r.Name + ' needs your approval',
                body, r, 'approve');
        }
    }

    /**
     * @description Tells each request's owner that it was approved or rejected, with the decision note.
     */
    public static void decided(Set<Id> requestIds) {
        for (PTO_Request__c r : requests(requestIds)) {
            Boolean isApproved = r.Status__c == LeaveValidator.STATUS_APPROVED;
            // The newest line of the notes: "Rejected by Mia Manager on 2026-10-28: reason".
            String notes = r.Decision_Notes__c;
            String decision = String.isBlank(notes) ? '' : '\n' + (notes.contains('\n') ? notes.substringAfterLast('\n') : notes);
            send(r.OwnerId, 'Your PTO request ' + r.Name + ' was ' + (isApproved ? 'approved' : 'rejected'),
                summary(r) + decision, r, 'past');
        }
    }

    private static List<PTO_Request__c> requests(Set<Id> requestIds) {
        if (requestIds == null || requestIds.isEmpty() || notificationTypeId() == null) {
            return new List<PTO_Request__c>();
        }
        return [
            SELECT Id, Name, Status__c, OwnerId, Approver__c, Employee__r.Name, Start_Date__c, End_Date__c,
                Day_Count__c, Total_Hours__c, Notes__c, Decision_Notes__c, PTO_Tab_Link__c
            FROM PTO_Request__c
            WHERE Id IN :requestIds
        ];
    }

    // "10/28/2026 to 10/29/2026 · 2 days · 16 hours"
    private static String summary(PTO_Request__c r) {
        Integer days = r.Day_Count__c == null ? 0 : r.Day_Count__c.intValue();
        Decimal hours = r.Total_Hours__c == null ? 0 : r.Total_Hours__c.stripTrailingZeros();
        String dates = r.Start_Date__c == null ? '' : r.Start_Date__c.format()
            + (r.End_Date__c == null || r.End_Date__c == r.Start_Date__c ? '' : ' to ' + r.End_Date__c.format()) + ' · ';
        return dates + days + (days == 1 ? ' day' : ' days') + ' · ' + hours.toPlainString() + (hours == 1 ? ' hour' : ' hours');
    }

    private static void send(Id recipientId, String title, String body, PTO_Request__c r, String section) {
        if (recipientId == null || recipientId == UserInfo.getUserId() || notificationTypeId() == null) {
            return;
        }
        Messaging.CustomNotification n = new Messaging.CustomNotification();
        n.setNotificationTypeId(notificationTypeId());
        n.setTitle(title.abbreviate(TITLE_MAX));
        n.setBody(body.abbreviate(BODY_MAX));
        // The same link as the PTO emails, so both open the PTO tab on the request.
        n.setTargetPageRef(JSON.serialize(new Map<String, Object>{
            'type' => 'standard__webPage',
            'attributes' => new Map<String, Object>{ 'url' => r.PTO_Tab_Link__c + '&c__section=' + section }
        }));
        try {
            n.send(new Set<String>{ recipientId });
        } catch (Exception e) {
            System.debug(LoggingLevel.WARN, 'PTO notification not sent for ' + r.Name + ': ' + e.getMessage());
        }
    }

    private static Id notificationTypeId() {
        if (!isTypeLoaded) {
            isTypeLoaded = true;
            String ns = namespace();
            List<CustomNotificationType> types = [
                SELECT Id FROM CustomNotificationType WHERE DeveloperName = :TYPE_NAME AND NamespacePrefix = :ns LIMIT 1
            ];
            typeId = types.isEmpty() ? null : types[0].Id;
        }
        return typeId;
    }

    // The package namespace ("dbt"), or null when the code runs unpackaged in an org without one.
    private static String namespace() {
        String objectName = PTO_Request__c.SObjectType.getDescribe().getName();
        return objectName.countMatches('__') == 2 ? objectName.substringBefore('__') : null;
    }
}
