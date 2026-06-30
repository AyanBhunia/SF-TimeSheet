public inherited sharing class EmployeeSelector {
    
    public static List<Employee__c> getEmployeesByIds(Set<Id> employeeIds) {
        return [SELECT Id, Name, First_Name__c, Last_Name__c, User__c, Manager__c, Active__c,
                       Total_Accrued_Hours__c, Total_Absence_Hours__c
                FROM Employee__c 
                WHERE Id IN :employeeIds
                WITH SECURITY_ENFORCED];
    }

    public static List<Employee__c> getEmployeesByUserId(Id userId) {
        return [SELECT Id, Name, First_Name__c, Last_Name__c, User__c, Manager__c, Active__c
                FROM Employee__c 
                WHERE User__c = :userId
                WITH SECURITY_ENFORCED];
    }
    
    public static List<Project_Employee__c> getEmployeeProjects(Id employeeId) {
        return [SELECT Id, Name, Project__c, Project__r.Name, Employee__c, Hourly_Rate__c, Project__r.Billable__c
                FROM Project_Employee__c 
                WHERE Employee__c = :employeeId
                WITH SECURITY_ENFORCED];
    }
}
