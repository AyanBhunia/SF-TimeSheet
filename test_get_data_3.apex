
Map<String, Schema.SObjectField> fieldMap = Schema.SObjectType.Timesheet_Line_Item__c.fields.getMap();
System.debug('FIELDS:' + fieldMap.keySet());
