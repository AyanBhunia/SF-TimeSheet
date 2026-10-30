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

        if (userID == null) {
            throw new AuraHandledException('User ID cannot be null');
        }

        try {
            return [
                select 
                    Date__c, Type__c, Project__r.name,SUM(Duration__c) duration 
                from 
                    Timesheet_Line_Item__c
                where 
                    Employee__c IN (select id from Employee__c where User__c = :userID) 
                    AND 
                    Date__c >= LAST_N_YEARS:5
                WITH SECURITY_ENFORCED
                group by 
                    Date__c, Type__c, Project__r.name
                order by 
                    Date__c DESC
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}