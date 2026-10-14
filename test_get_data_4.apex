
Id currentUserId = UserInfo.getUserId();
TimesheetApprovalController.TimesheetDataResponse res = TimesheetApprovalController.getTimesheetData('All Pending', null, null, new List<Integer>(), new List<String>());
System.debug('TEST_OUTPUT:' + JSON.serialize(res.rows));
