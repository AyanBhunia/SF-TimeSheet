public with sharing class EmployeeTriggerHandler {

    public static void populateClientManager(List<Employee__c> newList) {
        Set<Id> managerIds = new Set<Id>();
        for (Employee__c e : newList) {
            if (e.Manager__c != null && (e.Client_Manager__c == null || e.Client_Manager_email__c == null)) {
                managerIds.add(e.Manager__c);
            }
        }
        if (managerIds.isEmpty()) return;

        Map<Id, User> usersById = new Map<Id, User>(
            [SELECT Id, Email FROM User WHERE Id IN :managerIds]
        );

        for (Employee__c e : newList) {
            if (e.Manager__c != null && (e.Client_Manager__c == null || e.Client_Manager_email__c == null)) {
                User mgr = usersById.get(e.Manager__c);
                if (mgr != null) {
                    e.Client_Manager__c = mgr.Id;
                    e.Client_Manager_email__c = mgr.Email;
                }
            }
        }
    }

    public static void populateEmployeeFields(List<Employee__c> empList) {
        Set<Id> userIds = new Set<Id>();
        for (Employee__c emp : empList) {
            if (emp.User__c != null) {
                userIds.add(emp.User__c);
            	}
        	}  

        if (!userIds.isEmpty()) {
            Map<Id, User> userMap = new Map<Id, User>([
                SELECT Id, FirstName, LastName, ManagerId
                FROM User
                WHERE Id IN :userIds
            ]);

            for (Employee__c emp : empList) {
                if (emp.User__c != null && userMap.containsKey(emp.User__c)) {
                    User u = userMap.get(emp.User__c);
                    // Only map fields from User (not overwriting Name anymore)
                    emp.Manager__c = u.ManagerId;
                    emp.OwnerId   = u.Id;
            	}
        	}
       }
    }
    
    // 🔹 Always set Employee Name = First_Name__c + Last_Name__c
    public static void populateEmployeeName(List<Employee__c> empList) {
        for (Employee__c emp : empList) {
            String firstName = emp.First_Name__c;
            String lastName  = emp.Last_Name__c;

            if (String.isNotBlank(firstName) || String.isNotBlank(lastName)) {
                emp.Name = (String.isNotBlank(firstName) ? firstName : '') +
                           (String.isNotBlank(lastName)  ? ' ' + lastName : '');
            }
        }
    }
    
    public static void checkUserDuplicationForEmployeeBeforeInsert(List<Employee__c	> employees){
        Map<Id, Employee__c> userEmployeeMap = getUserEmployeeMapForBeforeInsert(employees);
        if (userEmployeeMap.size() > 0){
            for(Employee__c	 employee : employees){
            	if(userEmployeeMap.get(employee.User__c) != null){
                	employee.User__c.addError('An Employee with same user already exists');
            	}
        	}  
        }
    }
    
    public static void checkUserDuplicationForEmployeeBeforeUpdate(List<Employee__c> employees){
        Map<Id, Employee__c> userEmployeeMap = getUserEmployeeMapForBeforeUpdate(employees);
        if (userEmployeeMap.size() > 0){
            for(Employee__c	 employee : employees){
            	if(userEmployeeMap.get(employee.User__c) != null && employee.Id != userEmployeeMap.get(employee.User__c).Id  ){
                	employee.User__c.addError('An Employee with same user already exists');
            	}
        	}
       }
    }
    
    private static Map<Id, Employee__c> getUserEmployeeMapForBeforeInsert(List<Employee__c> employees){
        Map<Id, Employee__c> userEmployeeMap = new Map<Id, Employee__c>();
        if(Employee__c.SObjectType.getDescribe().isCreateable() 
            && Schema.SObjectType.Employee__c.fields.User__c.isCreateable()) {
                userEmployeeMap = getUserEmployeeMap(employees);                                  
        } else{
            addError(employees);
        }
        return userEmployeeMap;
    }
    
    private static Map<Id, Employee__c> getUserEmployeeMapForBeforeUpdate(List<Employee__c> employees){
        Map<Id, Employee__c> userEmployeeMap = new Map<Id, Employee__c>();
        if(Employee__c.SObjectType.getDescribe().isUpdateable() 
            && Schema.SObjectType.Employee__c.fields.User__c.isUpdateable()) {
                userEmployeeMap = getUserEmployeeMap(employees);
        } else{
            addError(employees);
        }
        return userEmployeeMap;
    }

    private static Map<Id, Employee__c> getUserEmployeeMap(List<Employee__c> employees){
        Map<Id, Employee__c> userEmployeeMap = new Map<Id, Employee__c>();
        Map<Id, Employee__c> employeeMap = new Map<Id, Employee__c>([SELECT
                                                            Id,
                                                            User__c
                                                            FROM Employee__c
                                                            WHERE User__c = : getUserIds(employees)
                                                            WITH SECURITY_ENFORCED]);
        if(employeeMap != null && employeeMap.size() > 0){
            for(Id id : employeeMap.keySet()){
                userEmployeeMap.put(employeeMap.get(id).User__c, employeeMap.get(id));
            }
        }
        return userEmployeeMap;
    }

    private static List<Id> getUserIds(List<Employee__c> employees){
        List<Id> userIds = new List<Id>();
        for(Employee__c	 employee : employees){
            userIds.add(employee.User__c);
        }
        return userIds;
    }

    private static void addError(List<Employee__c> employees){
        for(Employee__c	 employee : employees){
            employee.addError('You do not have access, Please contact system admin');
        }
    }
}