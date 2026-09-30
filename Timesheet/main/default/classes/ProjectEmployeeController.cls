// All SOQL and DML run in user mode: object, field and sharing access are enforced for the running user.
public with sharing class ProjectEmployeeController {
    
    public class InitialDataWrapper {
        @AuraEnabled public List<Project__c> projects {get; set;}
        @AuraEnabled public List<Group> groups {get; set;}
        @AuraEnabled public List<Employee__c> employees {get; set;}
    }

    // Not cacheable: the button is used rarely, so always read fresh data
    @AuraEnabled
    public static InitialDataWrapper getInitialData() {
        InitialDataWrapper wrapper = new InitialDataWrapper();
        wrapper.projects = [SELECT Id, Name FROM Project__c WHERE Active__c = true WITH USER_MODE ORDER BY Name];
        wrapper.groups = [SELECT Id, Name FROM Group WHERE Type = 'Regular' WITH USER_MODE ORDER BY Name];
        wrapper.employees = [SELECT Id, Name, First_Name__c, Last_Name__c FROM Employee__c WHERE Active__c = true WITH USER_MODE ORDER BY Name];
        return wrapper;
    }

    @AuraEnabled
    public static List<Id> getEmployeesByGroup(Id groupId) {
        List<Id> employeeIds = new List<Id>();
        for(Employee__c emp : [SELECT Id FROM Employee__c WHERE Active__c = true AND User__c IN (SELECT UserOrGroupId FROM GroupMember WHERE GroupId = :groupId) WITH USER_MODE]) {
            employeeIds.add(emp.Id);
        }
        return employeeIds;
    }

    // Returns "projectId_employeeId" keys for combinations that already exist
    @AuraEnabled
    public static List<String> getExistingCombinations(List<Id> projectIds, List<Id> employeeIds) {
        List<String> keys = new List<String>();
        for (Project_Employee__c pe : [SELECT Project__c, Employee__c FROM Project_Employee__c WHERE Project__c IN :projectIds AND Employee__c IN :employeeIds WITH USER_MODE]) {
            keys.add(pe.Project__c + '_' + pe.Employee__c);
        }
        return keys;
    }

    public class ProjectEmployeeSaveWrapper {
        @AuraEnabled public Id projectId {get; set;}
        @AuraEnabled public Id employeeId {get; set;}
        @AuraEnabled public Decimal hourlyRate {get; set;}
    }

    // Returns how many records were inserted; pairs that already exist are skipped
    @AuraEnabled
    public static Integer saveProjectEmployees(List<ProjectEmployeeSaveWrapper> records) {
        List<Project_Employee__c> toInsert = new List<Project_Employee__c>();
        
        Set<Id> pIds = new Set<Id>();
        Set<Id> eIds = new Set<Id>();
        for (ProjectEmployeeSaveWrapper w : records) {
            pIds.add(w.projectId);
            eIds.add(w.employeeId);
        }

        Set<String> existingKeys = new Set<String>();
        for (Project_Employee__c pe : [SELECT Project__c, Employee__c FROM Project_Employee__c WHERE Project__c IN :pIds AND Employee__c IN :eIds WITH USER_MODE]) {
            existingKeys.add(pe.Project__c + '_' + pe.Employee__c);
        }

        for (ProjectEmployeeSaveWrapper w : records) {
            String key = w.projectId + '_' + w.employeeId;
            if (!existingKeys.contains(key)) {
                toInsert.add(new Project_Employee__c(
                    Project__c = w.projectId,
                    Employee__c = w.employeeId,
                    Hourly_Rate__c = w.hourlyRate
                ));
                // Add to existingKeys to prevent duplicates within the same transaction request
                existingKeys.add(key);
            }
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, AccessLevel.USER_MODE);
        }
        return toInsert.size();
    }
}