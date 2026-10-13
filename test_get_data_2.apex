
Id currentUserId = UserInfo.getUserId();
Timesheet__c ts = new Timesheet__c(Start_Date__c = Date.today(), End_Date__c = Date.today().addDays(6), Manager__c = currentUserId, Status__c = 'New');
insert ts;
Timesheet_Line_Item__c li = new Timesheet_Line_Item__c(Timesheet__c = ts.Id, Date__c = Date.today(), Line_Item_Status__c = 'Submitted', Duration__c = 8, Type__c = 'Absence');
insert li;
TimesheetApprovalController.TimesheetDataResponse res = TimesheetApprovalController.getTimesheetData('All Pending', null, null, new List<Integer>(), new List<String>());
System.debug('OUTPUT_ROWS:' + JSON.serialize(res.rows));
