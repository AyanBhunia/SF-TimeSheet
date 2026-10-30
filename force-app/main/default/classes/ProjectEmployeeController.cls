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

    public class ExistingProjectEmployee {
        @AuraEnabled public Id id {get; set;}
        @AuraEnabled public Id projectId {get; set;}
        @AuraEnabled public Id employeeId {get; set;}
        @AuraEnabled public Decimal hourlyRate {get; set;}
    }

    // Returns existing combinations with their record Id and current hourly rate
    @AuraEnabled
    public static List<ExistingProjectEmployee> getExistingProjectEmployees(List<Id> projectIds, List<Id> employeeIds) {
        List<ExistingProjectEmployee> result = new List<ExistingProjectEmployee>();
        for (Project_Employee__c pe : [SELECT Id, Project__c, Employee__c, Hourly_Rate__c FROM Project_Employee__c WHERE Project__c IN :projectIds AND Employee__c IN :employeeIds WITH USER_MODE]) {
            ExistingProjectEmployee rec = new ExistingProjectEmployee();
            rec.id = pe.Id;
            rec.projectId = pe.Project__c;
            rec.employeeId = pe.Employee__c;
            rec.hourlyRate = pe.Hourly_Rate__c;
            result.add(rec);
        }
        return result;
    }

    public class ProjectEmployeeSaveWrapper {
        @AuraEnabled public Id projectId {get; set;}
        @AuraEnabled public Id employeeId {get; set;}
        @AuraEnabled public Decimal hourlyRate {get; set;}
        // True for rows the screen showed as already assigned; only these may change an existing rate
        @AuraEnabled public Boolean isExisting {get; set;}
    }

    public class SaveResult {
        @AuraEnabled public Integer created {get; set;}
        @AuraEnabled public Integer updated {get; set;}
    }

    // Inserts new pairs and updates the rate of existing pairs sent as isExisting.
    // Existing records are matched by project and employee; a new row for a pair that already exists is skipped.
    @AuraEnabled
    public static SaveResult saveProjectEmployees(List<ProjectEmployeeSaveWrapper> records) {
        List<Project_Employee__c> toInsert = new List<Project_Employee__c>();
        List<Project_Employee__c> toUpdate = new List<Project_Employee__c>();
        
        Set<Id> pIds = new Set<Id>();
        Set<Id> eIds = new Set<Id>();
        for (ProjectEmployeeSaveWrapper w : records) {
            if (w.projectId != null) pIds.add(w.projectId);
            if (w.employeeId != null) eIds.add(w.employeeId);
        }

        Map<String, Project_Employee__c> existingByCombo = new Map<String, Project_Employee__c>();
        for (Project_Employee__c pe : [SELECT Id, Project__c, Employee__c, Hourly_Rate__c FROM Project_Employee__c WHERE Project__c IN :pIds AND Employee__c IN :eIds WITH USER_MODE]) {
            existingByCombo.put(pe.Project__c + '_' + pe.Employee__c, pe);
        }

        Set<String> processedKeys = new Set<String>();
        for (ProjectEmployeeSaveWrapper w : records) {
            String key = w.projectId + '_' + w.employeeId;
            if (processedKeys.contains(key)) {
                continue;
            }
            processedKeys.add(key);

            Project_Employee__c existing = existingByCombo.get(key);
            if (existing != null) {
                if (w.isExisting == true && existing.Hourly_Rate__c != w.hourlyRate) {
                    toUpdate.add(new Project_Employee__c(
                        Id = existing.Id,
                        Hourly_Rate__c = w.hourlyRate
                    ));
                }
            } else {
                toInsert.add(new Project_Employee__c(
                    Project__c = w.projectId,
                    Employee__c = w.employeeId,
                    Hourly_Rate__c = w.hourlyRate
                ));
            }
        }

        if (!toInsert.isEmpty()) {
            Database.insert(toInsert, AccessLevel.USER_MODE);
        }
        if (!toUpdate.isEmpty()) {
            Database.update(toUpdate, AccessLevel.USER_MODE);
        }
        SaveResult result = new SaveResult();
        result.created = toInsert.size();
        result.updated = toUpdate.size();
        return result;
    }
}