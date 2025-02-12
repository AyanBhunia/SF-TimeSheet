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
                    dbt__Type__c,
                    dbt__Date__c, 
                    SUM(dbt__Duration__c) duration 
                FROM dbt__Timesheet_Line_Item__c 
                WHERE 
                    dbt__Employee__c = :recID 
                    AND dbt__Type__c = 'Attendance' 
                    AND dbt__Date__c >= :startDate 
                    AND dbt__Date__c <= :endDate
                WITH SECURITY_ENFORCED
                GROUP BY 
                    dbt__Type__c,
                    dbt__Date__c 
                ORDER BY 
                    dbt__Date__c
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}