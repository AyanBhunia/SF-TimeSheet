public with sharing class ProjectController {
    
    @AuraEnabled
    public static List<Project_Employee__c> getProjects(String empId){
        try {
            if(Project_Employee__c.SObjectType.getDescribe().isAccessible() 
                && Schema.SObjectType.Project_Employee__c.fields.Id.isAccessible() 
                && Schema.SObjectType.Project_Employee__c.fields.Project__c.isAccessible() 
                && Schema.SObjectType.Project_Employee__c.fields.Employee__c.isAccessible()){
                    return [select Id,
                                            Name, 
                                            Project__c, 
                                            Project__r.Name, 
                                            Employee__c 
                                            from Project_Employee__c 
                                            Where Employee__c =: empId
                                            with SECURITY_ENFORCED];
            } else{
                throw new AuraHandledException('You do not have access, please contact System Admin');
            }
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }
}