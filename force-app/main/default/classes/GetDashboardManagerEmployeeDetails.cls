/**
 * @description Class to query employees managed by a specific manager
 * @author Ayan
 */
public with sharing class GetDashboardManagerEmployeeDetails {

    /**
     * @description Retrieves a list of employees who report to the given manager
     * @param managerId The ID of the manager (User ID) to fetch employees for
     * @return List of Employee__c records managed by the specified manager
     * @throws AuraHandledException if insufficient permissions or other errors occur
     */
    @AuraEnabled(cacheable=true)
    public static List<Employee__c> getManagerEmployeeDetails(Id managerId) {
        try {

            // Validate the managerId parameter
            if (managerId == null) {
                throw new AuraHandledException('Manager ID cannot be null.');
            }

            // Perform the SOQL query to retrieve employees managed by the specified manager
            List<Employee__c> employees = [
                SELECT
                    Id,
                    Name,
                    Manager__c,
                    User__c
                FROM
                    Employee__c
                WHERE
                    Manager__c = :managerId
                    AND
                    Active__c =true 
                WITH SECURITY_ENFORCED
            ];

            return employees;
        } catch (Exception e) {
            // Handle exceptions and throw an AuraHandledException to provide user-friendly error messages
            throw new AuraHandledException('Error retrieving employees: ' + e.getMessage());
        }
    }
}