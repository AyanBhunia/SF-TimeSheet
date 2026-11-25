/**
 * @description Service class to calculate timesheet cycle dates (Start Date, End Date, Record Name)
 *              based on configurable settings in Timesheet_Default_Value__mdt (Weekly, Bi-Weekly, Monthly, Custom).
 */
public with sharing class TimesheetCycleService {

    public static final String CYCLE_WEEKLY = 'Weekly';
    public static final String CYCLE_BIWEEKLY = 'Bi-Weekly';
    public static final String CYCLE_MONTHLY = 'Monthly';
    public static final String CYCLE_CUSTOM = 'Custom';

    public static final String DAY_MONDAY = 'Monday';
    public static final String DAY_SUNDAY = 'Sunday';

    @TestVisible
    private static Timesheet_Default_Value__mdt mockSettings;

    public class CycleRequest {
        @InvocableVariable(label='Reference Date' description='Defaults to TODAY if omitted')
        public Date referenceDate;
    }

    public class CycleResult {
        @AuraEnabled
        @InvocableVariable(label='Start Date')
        public Date startDate;

        @AuraEnabled
        @InvocableVariable(label='End Date')
        public Date endDate;

        @AuraEnabled
        @InvocableVariable(label='Record Name')
        public String recordName;

        public CycleResult() {}

        public CycleResult(Date startDt, Date endDt) {
            this.startDate = startDt;
            this.endDate = endDt;
            this.recordName = 'Timesheet for ' + String.valueOf(startDt) + ' to ' + String.valueOf(endDt);
        }
    }

    /**
     * @description Invocable method for Flow integration.
     */
    @InvocableMethod(label='Calculate Timesheet Cycle Dates' description='Calculates Start Date, End Date, and Record Name based on Timesheet Default Value metadata.')
    public static List<CycleResult> calculateCycleDates(List<CycleRequest> requests) {
        List<CycleResult> results = new List<CycleResult>();
        if (requests == null || requests.isEmpty()) {
            results.add(getCycleDates(Date.today()));
            return results;
        }
        for (CycleRequest req : requests) {
            Date refDate = (req != null && req.referenceDate != null) ? req.referenceDate : Date.today();
            results.add(getCycleDates(refDate));
        }
        return results;
    }

    /**
     * @description Returns current cycle dates for today.
     */
    @AuraEnabled(cacheable=true)
    public static CycleResult getCurrentCycleDates() {
        return getCycleDates(Date.today());
    }

    /**
     * @description Calculates cycle dates based on custom metadata and reference date.
     */
    public static CycleResult getCycleDates(Date referenceDate) {
        Date refDate = (referenceDate != null) ? referenceDate : Date.today();
        Timesheet_Default_Value__mdt settings = getSettings();

        String cycleType = (settings != null && String.isNotBlank(settings.Timesheet_Cycle_Type__c))
            ? settings.Timesheet_Cycle_Type__c
            : CYCLE_WEEKLY;

        String startDay = (settings != null && String.isNotBlank(settings.Week_Start_Day__c))
            ? settings.Week_Start_Day__c
            : DAY_MONDAY;

        Decimal durationDays = (settings != null && settings.Timesheet_Duration_Days__c != null && settings.Timesheet_Duration_Days__c > 0)
            ? settings.Timesheet_Duration_Days__c
            : 7;

        Date startDate;
        Date endDate;

        if (cycleType == CYCLE_MONTHLY) {
            startDate = refDate.toStartOfMonth();
            Date nextMonthStart = refDate.addMonths(1).toStartOfMonth();
            endDate = nextMonthStart.addDays(-1);
        } else {
            startDate = calculateWeekStartDate(refDate, startDay);
            if (cycleType == CYCLE_BIWEEKLY) {
                endDate = startDate.addDays(13);
            } else if (cycleType == CYCLE_CUSTOM) {
                endDate = startDate.addDays((Integer)durationDays - 1);
            } else {
                // Default: Weekly (7 days)
                endDate = startDate.addDays(6);
            }
        }

        return new CycleResult(startDate, endDate);
    }

    /**
     * @description Calculates the start date of the week based on the configured start day (Monday or Sunday).
     */
    public static Date calculateWeekStartDate(Date refDate, String weekStartDay) {
        // Known Sunday reference date: 1900-01-07
        Date knownSunday = Date.newInstance(1900, 1, 7);
        Integer dayOfWeek = Math.mod(knownSunday.daysBetween(refDate), 7);
        if (dayOfWeek < 0) {
            dayOfWeek += 7;
        }
        // 0 = Sunday, 1 = Monday, 2 = Tuesday, 3 = Wednesday, 4 = Thursday, 5 = Friday, 6 = Saturday

        if (weekStartDay == DAY_SUNDAY) {
            return refDate.addDays(-dayOfWeek);
        } else {
            // Default to Monday start
            Integer daysBack = (dayOfWeek == 0) ? 6 : (dayOfWeek - 1);
            return refDate.addDays(-daysBack);
        }
    }

    /**
     * @description Fetches custom metadata settings or mock for testing.
     */
    private static Timesheet_Default_Value__mdt getSettings() {
        if (mockSettings != null) {
            return mockSettings;
        }
        Timesheet_Default_Value__mdt s = Timesheet_Default_Value__mdt.getInstance('Default_Values');
        if (s == null) {
            List<Timesheet_Default_Value__mdt> listSettings = [
                SELECT Timesheet_Cycle_Type__c, Week_Start_Day__c, Timesheet_Duration_Days__c
                FROM Timesheet_Default_Value__mdt
                WHERE DeveloperName = 'Default_Values'
                LIMIT 1
            ];
            if (!listSettings.isEmpty()) {
                s = listSettings[0];
            }
        }
        return s;
    }
}
