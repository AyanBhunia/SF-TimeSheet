List<Employee__c> emps = [SELECT Id, Name, First_Name__c, Last_Name__c, CreatedDate FROM Employee__c WHERE Last_Name__c LIKE '%Employee%'];
for(Employee__c e : emps) {
    System.debug('EMP: Name=' + e.Name + ', First=' + e.First_Name__c + ', Last=' + e.Last_Name__c + ', Created=' + e.CreatedDate);
}
