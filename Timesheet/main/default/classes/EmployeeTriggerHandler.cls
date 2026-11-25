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
    
    public static void checkUserDuplicationForEmployeeBeforeInsert(List<Employee__c> employees){
        List<Id> userIds = getUserIds(employees);
        if (userIds.isEmpty()) {
            return;
        }
        Map<Id, Employee__c> userEmployeeMap = getUserEmployeeMap(employees);
        if (!userEmployeeMap.isEmpty()){
            for(Employee__c employee : employees){
            	if(employee.User__c != null && userEmployeeMap.get(employee.User__c) != null){
                	employee.User__c.addError('An Employee with same user already exists');
            	}
        	}  
        }
    }
    
    public static void checkUserDuplicationForEmployeeBeforeUpdate(List<Employee__c> employees){
        List<Id> userIds = getUserIds(employees);
        if (userIds.isEmpty()) {
            return;
        }
        Map<Id, Employee__c> userEmployeeMap = getUserEmployeeMap(employees);
        if (!userEmployeeMap.isEmpty()){
            for(Employee__c employee : employees){
            	if(employee.User__c != null && userEmployeeMap.get(employee.User__c) != null && employee.Id != userEmployeeMap.get(employee.User__c).Id){
                	employee.User__c.addError('An Employee with same user already exists');
            	}
        	}
       }
    }
    
    private static Map<Id, Employee__c> getUserEmployeeMapForBeforeInsert(List<Employee__c> employees){
        return getUserEmployeeMap(employees);
    }
    
    private static Map<Id, Employee__c> getUserEmployeeMapForBeforeUpdate(List<Employee__c> employees){
        return getUserEmployeeMap(employees);
    }

    private static Map<Id, Employee__c> getUserEmployeeMap(List<Employee__c> employees){
        Map<Id, Employee__c> userEmployeeMap = new Map<Id, Employee__c>();
        List<Id> userIds = getUserIds(employees);
        if (userIds.isEmpty()) {
            return userEmployeeMap;
        }
        Map<Id, Employee__c> employeeMap = new Map<Id, Employee__c>([SELECT
                                                            Id,
                                                            User__c
                                                            FROM Employee__c
                                                            WHERE User__c IN : userIds]);
        if(employeeMap != null && employeeMap.size() > 0){
            for(Id id : employeeMap.keySet()){
                userEmployeeMap.put(employeeMap.get(id).User__c, employeeMap.get(id));
            }
        }
        return userEmployeeMap;
    }

    private static List<Id> getUserIds(List<Employee__c> employees){
        List<Id> userIds = new List<Id>();
        for(Employee__c employee : employees){
            if (employee.User__c != null) {
                userIds.add(employee.User__c);
            }
        }
        return userIds;
    }
}