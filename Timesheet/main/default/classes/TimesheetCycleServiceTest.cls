@IsTest
private class TimesheetCycleServiceTest {

    @IsTest
    static void testWeeklyMondayCycle() {
        Timesheet_Default_Value__mdt mock = new Timesheet_Default_Value__mdt(
            Timesheet_Cycle_Type__c = TimesheetCycleService.CYCLE_WEEKLY,
            Week_Start_Day__c = TimesheetCycleService.DAY_MONDAY,
            Timesheet_Duration_Days__c = 7
        );
        TimesheetCycleService.mockSettings = mock;

        // 2026-11-18 is Wednesday
        Date wednesday = Date.newInstance(2026, 11, 18);
        TimesheetCycleService.CycleResult res = TimesheetCycleService.getCycleDates(wednesday);

        System.assertEquals(Date.newInstance(2026, 11, 16), res.startDate, 'Start should be Monday Nov 16');
        System.assertEquals(Date.newInstance(2026, 11, 22), res.endDate, 'End should be Sunday Nov 22');
        System.assert(res.recordName.contains('2026-11-16'), 'Name should include start date');

        // Test on Sunday (2026-11-22)
        Date sunday = Date.newInstance(2026, 11, 22);
        TimesheetCycleService.CycleResult resSun = TimesheetCycleService.getCycleDates(sunday);
        System.assertEquals(Date.newInstance(2026, 11, 16), resSun.startDate, 'Sunday should map to previous Monday');
        System.assertEquals(Date.newInstance(2026, 11, 22), resSun.endDate, 'End should be Sunday Nov 22');
    }

    @IsTest
    static void testWeeklySundayCycle() {
        Timesheet_Default_Value__mdt mock = new Timesheet_Default_Value__mdt(
            Timesheet_Cycle_Type__c = TimesheetCycleService.CYCLE_WEEKLY,
            Week_Start_Day__c = TimesheetCycleService.DAY_SUNDAY,
            Timesheet_Duration_Days__c = 7
        );
        TimesheetCycleService.mockSettings = mock;

        // 2026-11-18 is Wednesday
        Date wednesday = Date.newInstance(2026, 11, 18);
        TimesheetCycleService.CycleResult res = TimesheetCycleService.getCycleDates(wednesday);

        System.assertEquals(Date.newInstance(2026, 11, 15), res.startDate, 'Start should be Sunday Nov 15');
        System.assertEquals(Date.newInstance(2026, 11, 21), res.endDate, 'End should be Saturday Nov 21');
    }

    @IsTest
    static void testBiWeeklyCycle() {
        Timesheet_Default_Value__mdt mock = new Timesheet_Default_Value__mdt(
            Timesheet_Cycle_Type__c = TimesheetCycleService.CYCLE_BIWEEKLY,
            Week_Start_Day__c = TimesheetCycleService.DAY_MONDAY,
            Timesheet_Duration_Days__c = 14
        );
        TimesheetCycleService.mockSettings = mock;

        Date monday = Date.newInstance(2026, 11, 16);
        TimesheetCycleService.CycleResult res = TimesheetCycleService.getCycleDates(monday);

        System.assertEquals(Date.newInstance(2026, 11, 16), res.startDate);
        System.assertEquals(Date.newInstance(2026, 11, 29), res.endDate, 'Bi-weekly should be 14 days (Nov 16 to Nov 29)');
    }

    @IsTest
    static void testMonthlyCycle() {
        Timesheet_Default_Value__mdt mock = new Timesheet_Default_Value__mdt(
            Timesheet_Cycle_Type__c = TimesheetCycleService.CYCLE_MONTHLY
        );
        TimesheetCycleService.mockSettings = mock;

        Date midMonth = Date.newInstance(2026, 11, 18);
        TimesheetCycleService.CycleResult res = TimesheetCycleService.getCycleDates(midMonth);

        System.assertEquals(Date.newInstance(2026, 11, 1), res.startDate, 'Start should be 1st of month');
        System.assertEquals(Date.newInstance(2026, 11, 30), res.endDate, 'End should be last day of November');

        // Test December month end transition
        Date decDate = Date.newInstance(2026, 12, 10);
        TimesheetCycleService.CycleResult resDec = TimesheetCycleService.getCycleDates(decDate);
        System.assertEquals(Date.newInstance(2026, 12, 1), resDec.startDate);
        System.assertEquals(Date.newInstance(2026, 12, 31), resDec.endDate);
    }

    @IsTest
    static void testCustomDurationCycle() {
        Timesheet_Default_Value__mdt mock = new Timesheet_Default_Value__mdt(
            Timesheet_Cycle_Type__c = TimesheetCycleService.CYCLE_CUSTOM,
            Week_Start_Day__c = TimesheetCycleService.DAY_MONDAY,
            Timesheet_Duration_Days__c = 10
        );
        TimesheetCycleService.mockSettings = mock;

        Date monday = Date.newInstance(2026, 11, 16);
        TimesheetCycleService.CycleResult res = TimesheetCycleService.getCycleDates(monday);

        System.assertEquals(Date.newInstance(2026, 11, 16), res.startDate);
        System.assertEquals(Date.newInstance(2026, 11, 25), res.endDate, 'Custom 10 days');
    }

    @IsTest
    static void testInvocableAndAuraEnabled() {
        TimesheetCycleService.mockSettings = null; // Uses metadata or fallback

        // Test getCurrentCycleDates
        TimesheetCycleService.CycleResult currentRes = TimesheetCycleService.getCurrentCycleDates();
        System.assertNotEquals(null, currentRes.startDate);
        System.assertNotEquals(null, currentRes.endDate);

        // Test calculateCycleDates with empty list
        List<TimesheetCycleService.CycleResult> emptyResults = TimesheetCycleService.calculateCycleDates(new List<TimesheetCycleService.CycleRequest>());
        System.assertEquals(1, emptyResults.size());

        // Test calculateCycleDates with explicit request
        TimesheetCycleService.CycleRequest req = new TimesheetCycleService.CycleRequest();
        req.referenceDate = Date.newInstance(2026, 11, 17);
        List<TimesheetCycleService.CycleResult> results = TimesheetCycleService.calculateCycleDates(new List<TimesheetCycleService.CycleRequest>{ req });
        System.assertEquals(1, results.size());
        System.assertNotEquals(null, results[0].startDate);
    }
}
