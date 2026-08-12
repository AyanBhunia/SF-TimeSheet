System.debug('PROJECTS: ' + [SELECT Id, Name FROM Project__c]);
System.debug('TEST PROJECTS: ' + [SELECT Id, Name FROM Project__c WHERE Name LIKE 'Test Project%']);
