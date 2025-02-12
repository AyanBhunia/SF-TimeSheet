/**
 * @description Class to retrieve detailed timesheet records including related timesheet entries
 * @author [author Name]
 */
public with sharing class GetTimesheet {
    
    /**
     * @description Retrieves a timesheet record with related information including employee details and timesheet entries
     * @param recID The ID of the timesheet record to fetch
     * @return dbt__Timesheet__c Timesheet record with related data
     * @throws AuraHandledException if insufficient permissions or other errors occur
     */
    @AuraEnabled
    public static dbt__Timesheet__c getTimesheetRecords(Id recID) {
        try {
            // Input validation
            if (recID == null) {
                throw new AuraHandledException('Timesheet ID cannot be null');
            }

            return [
                SELECT 
                    dbt__Employee__r.Name,
                    dbt__Start_Date__c,
                    dbt__End_Date__c,
                    dbt__Employee__r.Client_Manager__r.Name,
                    dbt__Employee__r.Client_Manager_email__c,
                    dbt__Billable_Hours__c,
                    dbt__Non_Billable_Hours__c,
                    dbt__Total_Hours__c,
                    (
                        SELECT 
                            dbt__Duration__c,
                            dbt__Type__c,
                            dbt__Date__c 
                        FROM dbt__Timesheets__r
                    )
                FROM dbt__Timesheet__c 
                WHERE Id = :recID
                WITH SECURITY_ENFORCED
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}