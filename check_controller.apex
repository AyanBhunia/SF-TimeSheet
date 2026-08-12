Id empId = [SELECT Employee__c FROM Project_Employee__c LIMIT 1].Employee__c;
List<Project_Employee__c> projects = WeeklyTimesheetController.getProjects(empId);
System.debug(JSON.serialize(projects));
