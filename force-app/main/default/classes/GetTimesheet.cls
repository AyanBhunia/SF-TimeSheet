/**
 * @description Class to retrieve detailed timesheet records including related timesheet entries
 * @author [author Name]
 */
public with sharing class GetTimesheet {
    
    /**
     * @description Retrieves a timesheet record with related information including employee details and timesheet entries
     * @param recID The ID of the timesheet record to fetch
     * @return Timesheet__c Timesheet record with related data
     * @throws AuraHandledException if insufficient permissions or other errors occur
     */
    @AuraEnabled
    public static Timesheet__c getTimesheetRecords(Id recID) {
        try {
            // Input validation
            if (recID == null) {
                throw new AuraHandledException('Timesheet ID cannot be null');
            }

            return [
                SELECT 
                    Employee__r.Name,
                    Start_Date__c,
                    End_Date__c,
                    Employee__r.Client_Manager__r.Name,
                    Employee__r.Client_Manager_email__c,
                    Billable_Hours__c,
                    Non_Billable_Hours__c,
                    Total_Hours__c,
                    (
                        SELECT 
                            Duration__c,
                            Type__c,
                            Date__c 
                        FROM Timesheets__r
                    )
                FROM Timesheet__c 
                WHERE Id = :recID
                WITH SECURITY_ENFORCED
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}