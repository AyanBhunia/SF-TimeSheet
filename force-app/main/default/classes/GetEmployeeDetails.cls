/**
 * @description Class to retrieve detailed employee information including related project assignments
 * @author Ayan
 */
public with sharing class GetEmployeeDetails {
    
    /**
     * @description Retrieves employee record with related project employee information
     * @param recID The ID of the employee record to fetch
     * @return Employee__c Employee record with related project assignments
     * @throws AuraHandledException if insufficient permissions or other errors occur
     */
    @AuraEnabled
    public static Employee__c getEmployee(Id recID) {
        
        try {
            if (recID == null) {
                throw new AuraHandledException('Employee ID cannot be null');
            }

            return [
                SELECT 
                    Id,
                    Name, 
                    Client_Manager__r.Name, 
                    Client_Manager_email__c,
                    (
                        SELECT 
                            Id, 
                            Employee__r.Name, 
                            Project_Name__c 
                        FROM Project_Employees__r
                    )
                FROM Employee__c 
                WHERE Id = :recID
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}