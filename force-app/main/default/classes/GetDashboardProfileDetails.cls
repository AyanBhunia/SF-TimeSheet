/**
 * @description Class to retrieve dashboard profile details including employee and timesheet information
 * @author Ayan
 */
public with sharing class GetDashboardProfileDetails {
    
    /**
     * @description Retrieves employee details and timesheet summary for dashboard display
     * @param userID The ID of the user to fetch profile details for
     * @return Map<String, Object> Contains employee details and timesheet summary
     * @throws AuraHandledException if insufficient permissions or other errors occur
     */
    @AuraEnabled(cacheable=true)
    public static Map<String, Object> getEmployeeDetails(Id userID) {
        try {
            // For testing userId is '005fK000000xxC9QAI'
            userID = Id.valueOf('005fK000000xxC9QAI');
            
            Map<String, Object> resultData = new Map<String, Object>();
            
            // Fetch Employee Details
            dbt__Employee__c employeeRecord = getEmployeeRecord(userID);
            populateEmployeeDetails(resultData, employeeRecord);
            
            // Fetch Timesheet Hours Summary
            AggregateResult timesheetSummary = getTimesheetSummary(userID);
            populateTimesheetSummary(resultData, timesheetSummary);
            
            return resultData;
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
    
    /**
     * @description Retrieves employee record with related project information
     * @param userID The ID of the user
     * @return dbt__Employee__c Employee record with related data
     */
    private static dbt__Employee__c getEmployeeRecord(Id userID) {
        return [
            SELECT Id, Name, Client_Manager__r.Name, Client_Manager_email__c,
                (SELECT dbt__Project_Name__c FROM dbt__Project_Employees__r)
            FROM dbt__Employee__c
            WHERE dbt__User__c = :userID
            WITH SECURITY_ENFORCED
            LIMIT 1
        ];
    }
    
    /**
     * @description Retrieves timesheet summary aggregated data
     * @param userID The ID of the user
     * @return AggregateResult Aggregated timesheet data
     */
    private static AggregateResult getTimesheetSummary(Id userID) {
        return [
            SELECT 
                SUM(dbt__Billable_Hours__c) TotalBillableHours, 
                SUM(dbt__Non_Billable_Hours__c) TotalNonBillableHours, 
                SUM(dbt__Absence_Hours__c) TotalAbsenceHours, 
                SUM(dbt__Total_Hours__c) TotalHours
            FROM dbt__Timesheet__c
            WHERE dbt__Employee__c IN (SELECT id FROM dbt__Employee__c WHERE dbt__User__c = :userID)
            WITH SECURITY_ENFORCED
        ];
    }
    
    /**
     * @description Populates employee details in the result map
     * @param resultData Map to store the results
     * @param emp Employee record to process
     */
    private static void populateEmployeeDetails(Map<String, Object> resultData, dbt__Employee__c emp) {
        resultData.put('Name', emp.Name);
        resultData.put('ClientManager', emp.Client_Manager__r?.Name);
        resultData.put('ClientManagerEmail', emp.Client_Manager_email__c);
        
        List<String> projectNames = new List<String>();
        for (dbt__Project_Employee__c proj : emp.dbt__Project_Employees__r) {
            projectNames.add(proj.dbt__Project_Name__c);
        }
        resultData.put('Projects', String.join(projectNames, ', '));
    }
    
    /**
     * @description Populates timesheet summary in the result map
     * @param resultData Map to store the results
     * @param hours AggregateResult containing timesheet summary
     */
    private static void populateTimesheetSummary(Map<String, Object> resultData, AggregateResult hours) {
        resultData.put('TotalBillableHours', (Decimal) hours.get('TotalBillableHours'));
        resultData.put('TotalNonBillableHours', (Decimal) hours.get('TotalNonBillableHours'));
        resultData.put('TotalAbsenceHours', (Decimal) hours.get('TotalAbsenceHours'));
        resultData.put('TotalHours', (Decimal) hours.get('TotalHours'));
    }
}