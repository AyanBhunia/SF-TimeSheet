
List<Timesheet_Line_Item__c> items = Database.query('SELECT Id, Line_Item_Status__c FROM Timesheet_Line_Item__c LIMIT 1');
if (!items.isEmpty()) {
    System.debug('JSON_SERIALIZED_QUERY:' + JSON.serialize(items[0]));
} else {
    System.debug('NO_DATA');
}
