Project_Employee__c pe = [SELECT Id, Project__c, Project__r.Name FROM Project_Employee__c LIMIT 1];
System.debug(JSON.serialize(pe));
