/**
 * @description Class to querry timesheet line item for dashboard related operations
 * @author Ayan
 */
public with sharing class GetDashboardTimesheetLineItems {
    
    /**
     * @description Retrieves aggregated timesheet line items for dashboard display
     * @param userID The ID of the user to fetch timesheet data for
     * @return List<AggregateResult> Aggregated timesheet line items data
     * @throws AuraHandledException if insufficient permissions or other errors occur
     */
    @AuraEnabled(cacheable=true)
    public static List<AggregateResult> getDashboardTimesheetLineItemsDetails(Id userID){

        // For testing userId is '005fK000000xxC9QAI'
        userID = Id.valueOf('005fK000000xxC9QAI');

        try {
            return [
                select 
                    dbt__Date__c, dbt__Type__c, dbt__Project__r.name,SUM(dbt__Duration__c) duration 
                from 
                    dbt__Timesheet_Line_Item__c
                where 
                    dbt__Employee__c IN (select id from dbt__Employee__c where dbt__User__c = :userID) 
                    AND 
                    dbt__Date__c >= LAST_N_YEARS:5
                WITH SECURITY_ENFORCED
                group by 
                    dbt__Date__c, dbt__Type__c, dbt__Project__r.name
                order by 
                    dbt__Date__c DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}