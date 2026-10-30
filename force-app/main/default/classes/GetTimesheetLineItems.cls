/**
 * @description Class to retrieve aggregated timesheet line items for a specific timesheet
 * @author [author Name]
 */
public with sharing class GetTimesheetLineItems {
    
    /**
     * @description Retrieves aggregated attendance records from timesheet line items
     * @param recId The ID of the timesheet record
     * @return List<AggregateResult> Aggregated timesheet line items data grouped by date
     * @throws AuraHandledException if insufficient permissions or other errors occur
     */
    @AuraEnabled
    public static List<AggregateResult> getTimesheetLineItemsRecords(Id recId) {
        try {
            // Input validation
            if (recId == null) {
                throw new AuraHandledException('Timesheet ID cannot be null');
            }

            return [
                SELECT 
                    Date__c, 
                    SUM(Duration__c) duration 
                FROM Timesheet_Line_Item__c
                WHERE 
                    Timesheet__c = :recId
                    AND Type__c = 'Attendance'
                WITH SECURITY_ENFORCED
                GROUP BY 
                    Date__c
                ORDER BY 
                    Date__c
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}