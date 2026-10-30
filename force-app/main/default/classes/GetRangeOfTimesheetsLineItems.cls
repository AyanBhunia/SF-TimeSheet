/**
 * @description Class to retrieve aggregated timesheet line items within a specified date range
 * @author Ayan
 */
public with sharing class GetRangeOfTimesheetsLineItems {
    
    /**
     * @description Retrieves aggregated timesheet line items for a specific employee within a date range
     * @param recID The ID of the employee record
     * @param startDate The start date of the range
     * @param endDate The end date of the range
     * @return List<AggregateResult> Aggregated timesheet line items data
     * @throws AuraHandledException if insufficient permissions or other errors occur
     */
    @AuraEnabled
    public static List<AggregateResult> getTimesheetsLineItems(Id recID, Date startDate, Date endDate) {
        try {
            // Input validation
            if (recID == null) {
                throw new AuraHandledException('Employee ID cannot be null');
            }
            if (startDate == null || endDate == null) {
                throw new AuraHandledException('Start date and end date must be specified');
            }
            if (startDate > endDate) {
                throw new AuraHandledException('Start date cannot be after end date');
            }

            return [
                SELECT 
                    Type__c,
                    Date__c, 
                    SUM(Duration__c) duration 
                FROM Timesheet_Line_Item__c 
                WHERE 
                    Employee__c = :recID 
                    AND Type__c = 'Attendance' 
                    AND Date__c >= :startDate 
                    AND Date__c <= :endDate
                WITH SECURITY_ENFORCED
                GROUP BY 
                    Type__c,
                    Date__c 
                ORDER BY 
                    Date__c
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}