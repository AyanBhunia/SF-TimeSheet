try {
    DemoDataController.createDemoData();
    System.debug('DEMO_DATA_SUCCESS');
} catch (Exception e) {
    System.debug('DEMO_DATA_FAILED: ' + e.getMessage() + '\n' + e.getStackTraceString());
    // Also, query to see if Project_Employee__c exists
    List<Project_Employee__c> pes = [SELECT Id, Employee__c, Project__c, Hourly_Rate__c FROM Project_Employee__c];
    System.debug('PE Count: ' + pes.size());
    for(Project_Employee__c pe : pes) {
        System.debug('PE: Emp=' + pe.Employee__c + ' Proj=' + pe.Project__c + ' Rate=' + pe.Hourly_Rate__c);
    }
}
