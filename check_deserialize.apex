String jsonWithDbt = '[{"dbt__Project__c": "a05di00000NXJmgAAH"}]';
String jsonWithoutDbt = '[{"Project__c": "a05di00000NXJmgAAH"}]';
try {
    List<Timesheet_Line_Item__c> linesWith = (List<Timesheet_Line_Item__c>)JSON.deserialize(jsonWithDbt, List<Timesheet_Line_Item__c>.class);
    System.debug('WITH: ' + linesWith[0].Project__c);
} catch(Exception e) {
    System.debug('WITH FAIL');
}
try {
    List<Timesheet_Line_Item__c> linesWithout = (List<Timesheet_Line_Item__c>)JSON.deserialize(jsonWithoutDbt, List<Timesheet_Line_Item__c>.class);
    System.debug('WITHOUT: ' + linesWithout[0].Project__c);
} catch(Exception e) {
    System.debug('WITHOUT FAIL');
}
