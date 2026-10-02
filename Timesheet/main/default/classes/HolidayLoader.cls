/**
 * @description Turns the org's Holiday records into approved Type Holiday leave for chosen employees.
 *              Used by the PTO_Holiday_Loader screen flow in two steps:
 *              Preview - one row per holiday date in the year (not per employee) marked New, Exists or
 *                        Needs update, returned as an HTML table for the flow's display text.
 *              Create  - inserts missing rows and updates rows whose hours differ (or that failed earlier).
 *              Weekend dates are skipped. Runs without sharing: only HR Admin can open the flow.
 */
public without sharing class HolidayLoader {

    /** Rows written per transaction. Each leave row can create a line item, which fires the line item
        and timesheet automation, so batches stay small to keep query limits safe. */
    public static final Integer BATCH_SIZE = 200;

    public class Request {
        @InvocableVariable(label='Action' description='Preview or Create' required=true)
        public String action;
        @InvocableVariable(label='Year' required=true)
        public Integer year;
        @InvocableVariable(label='Hours per day')
        public Decimal hours;
        @InvocableVariable(label='Employee Ids' description='Semicolon-separated Employee__c ids')
        public String employeeIds;
        @InvocableVariable(label='All active employees')
        public Boolean allActive;
    }

    public class Response {
        @InvocableVariable(label='Summary (HTML)')
        public String summaryHtml;
        @InvocableVariable(label='Holiday dates')
        public Integer holidayCount;
        @InvocableVariable(label='Employees')
        public Integer employeeCount;
        @InvocableVariable(label='Rows to create')
        public Integer toCreate;
        @InvocableVariable(label='Rows to update')
        public Integer toUpdate;
        @InvocableVariable(label='Created')
        public Integer created;
        @InvocableVariable(label='Updated')
        public Integer updated;
        @InvocableVariable(label='Errors')
        public Integer errorCount;
        @InvocableVariable(label='Message')
        public String message;
    }

    public class HolidayDate {
        public Date day;
        public String name;
        public HolidayDate(Date day, String name) {
            this.day = day;
            this.name = name;
        }
    }

    @InvocableMethod(label='Load Holidays as Leave' description='Previews or creates approved holiday leave for employees.' category='PTO')
    public static List<Response> run(List<Request> requests) {
        if (!PtoController.hasPermission(PtoController.PERM_ADMIN_ALL)) {
            throw new NoAccessException();
        }
        List<Response> responses = new List<Response>();
        for (Request r : requests) {
            responses.add(handle(r));
        }
        return responses;
    }

    private static Response handle(Request r) {
        Response res = new Response();
        res.created = 0;
        res.updated = 0;
        res.errorCount = 0;
        Integer year = r.year == null ? Date.today().year() : r.year;
        Decimal hours = r.hours == null || r.hours <= 0 ? LeaveValidator.maxHours(LeaveValidator.CATEGORY_HOLIDAY) : r.hours;

        List<HolidayDate> holidays = holidayDates(year);
        List<Employee__c> employees = employees(r);
        res.holidayCount = holidays.size();
        res.employeeCount = employees.size();
        if (holidays.isEmpty() || employees.isEmpty()) {
            res.toCreate = 0;
            res.toUpdate = 0;
            res.message = holidays.isEmpty()
                ? 'No weekday holidays found for ' + year + '. Add them in Setup, Holidays.'
                : 'Pick at least one employee.';
            res.summaryHtml = '<p>' + res.message.escapeHtml4() + '</p>';
            return res;
        }

        Map<String, Leave_and_Holiday__c> existing = existing(employees, holidays);
        Plan plan = buildPlan(employees, holidays, hours, existing);
        res.toCreate = plan.inserts.size();
        res.toUpdate = plan.updates.size();

        if (r.action == 'Create') {
            if (plan.inserts.size() + plan.updates.size() > BATCH_SIZE) {
                System.enqueueJob(new Writer(plan.inserts, plan.updates));
                res.message = (plan.inserts.size() + plan.updates.size())
                    + ' rows are being written in the background, ' + BATCH_SIZE + ' at a time. Check back in a few minutes.';
            } else {
                Writer w = new Writer(plan.inserts, plan.updates);
                w.write();
                res.created = w.created;
                res.updated = w.updated;
                res.errorCount = w.errors.size();
                res.message = 'Created ' + w.created + ' and updated ' + w.updated + ' holiday rows.'
                    + (w.errors.isEmpty() ? '' : ' ' + w.errors.size() + ' failed: ' + String.join(firstN(w.errors, 5), ' | '));
            }
            res.summaryHtml = '<p>' + res.message.escapeHtml4() + '</p>';
            return res;
        }

        res.summaryHtml = previewHtml(holidays, employees.size(), hours, existing, plan);
        res.message = res.toCreate + ' rows to create, ' + res.toUpdate + ' to update.';
        return res;
    }

    // ---------------------------------------------------------------- holidays

    /**
     * @description Every weekday date in the year covered by a Holiday record, one-off or recurring.
     */
    public static List<HolidayDate> holidayDates(Integer year) {
        Date first = Date.newInstance(year, 1, 1);
        Date last = Date.newInstance(year, 12, 31);
        Map<Date, HolidayDate> byDay = new Map<Date, HolidayDate>();
        for (Holiday h : [
            SELECT Id, Name, ActivityDate, IsRecurrence, RecurrenceStartDate, RecurrenceEndDateOnly, RecurrenceType,
                RecurrenceInterval, RecurrenceDayOfWeekMask, RecurrenceDayOfMonth, RecurrenceInstance, RecurrenceMonthOfYear
            FROM Holiday
        ]) {
            if (!h.IsRecurrence) {
                if (h.ActivityDate != null && h.ActivityDate >= first && h.ActivityDate <= last) {
                    add(byDay, h.ActivityDate, h.Name);
                }
                continue;
            }
            for (Date d = first; d <= last; d = d.addDays(1)) {
                if (occursOn(h, d)) {
                    add(byDay, d, h.Name);
                }
            }
        }
        List<Date> days = new List<Date>(byDay.keySet());
        days.sort();
        List<HolidayDate> result = new List<HolidayDate>();
        for (Date d : days) {
            result.add(byDay.get(d));
        }
        return result;
    }

    private static void add(Map<Date, HolidayDate> byDay, Date d, String name) {
        Integer weekday = dayOfWeek(d);
        if (weekday == 0 || weekday == 6) {
            return;
        }
        if (byDay.containsKey(d)) {
            byDay.get(d).name += ' / ' + name;
        } else {
            byDay.put(d, new HolidayDate(d, name));
        }
    }

    @TestVisible
    private static Boolean occursOn(Holiday h, Date d) {
        if (h.RecurrenceStartDate != null && d < h.RecurrenceStartDate) {
            return false;
        }
        if (h.RecurrenceEndDateOnly != null && d > h.RecurrenceEndDateOnly) {
            return false;
        }
        Date start = h.RecurrenceStartDate == null ? h.ActivityDate : h.RecurrenceStartDate;
        Integer interval = h.RecurrenceInterval == null || h.RecurrenceInterval < 1 ? 1 : h.RecurrenceInterval;
        Integer weekday = dayOfWeek(d);
        Integer mask = h.RecurrenceDayOfWeekMask == null ? 0 : h.RecurrenceDayOfWeekMask;
        Boolean inMask = (mask & (1 << weekday)) != 0;
        Integer months = start == null ? 0 : (d.year() - start.year()) * 12 + d.month() - start.month();
        switch on h.RecurrenceType {
            when 'RecursDaily' {
                return start != null && Math.mod(start.daysBetween(d), interval) == 0;
            }
            when 'RecursEveryWeekday' {
                return weekday >= 1 && weekday <= 5;
            }
            when 'RecursWeekly' {
                if (!inMask || start == null) {
                    return false;
                }
                Integer weeks = mondayOf(start).daysBetween(mondayOf(d)) / 7;
                return Math.mod(weeks, interval) == 0;
            }
            when 'RecursMonthly' {
                return d.day() == h.RecurrenceDayOfMonth && Math.mod(months, interval) == 0;
            }
            when 'RecursMonthlyNth' {
                return inMask && isNth(d, h.RecurrenceInstance) && Math.mod(months, interval) == 0;
            }
            when 'RecursYearly' {
                return d.month() == monthNumber(h.RecurrenceMonthOfYear) && d.day() == h.RecurrenceDayOfMonth;
            }
            when 'RecursYearlyNth' {
                return d.month() == monthNumber(h.RecurrenceMonthOfYear) && inMask && isNth(d, h.RecurrenceInstance);
            }
        }
        return false;
    }

    private static Boolean isNth(Date d, String instance) {
        switch on instance {
            when 'First' { return d.day() <= 7; }
            when 'Second' { return d.day() > 7 && d.day() <= 14; }
            when 'Third' { return d.day() > 14 && d.day() <= 21; }
            when 'Fourth' { return d.day() > 21 && d.day() <= 28; }
            when 'Last' { return d.addDays(7).month() != d.month(); }
        }
        return false;
    }

    private static Integer monthNumber(String month) {
        List<String> names = new List<String>{ 'January', 'February', 'March', 'April', 'May', 'June', 'July',
            'August', 'September', 'October', 'November', 'December' };
        Integer index = names.indexOf(month);
        return index < 0 ? -1 : index + 1;
    }

    /**
     * @description 0 = Sunday ... 6 = Saturday, independent of the user's locale.
     */
    private static Integer dayOfWeek(Date d) {
        Integer value = Math.mod(Date.newInstance(1900, 1, 7).daysBetween(d), 7); // 1900-01-07 was a Sunday
        return value < 0 ? value + 7 : value;
    }

    private static Date mondayOf(Date d) {
        Integer weekday = dayOfWeek(d);
        return d.addDays(weekday == 0 ? -6 : 1 - weekday);
    }

    // ---------------------------------------------------------------- plan and write

    private class Plan {
        List<Leave_and_Holiday__c> inserts = new List<Leave_and_Holiday__c>();
        List<Leave_and_Holiday__c> updates = new List<Leave_and_Holiday__c>();
        Map<Date, Integer> existsByDay = new Map<Date, Integer>();
        Map<Date, Integer> updateByDay = new Map<Date, Integer>();
    }

    private static List<Employee__c> employees(Request r) {
        if (r.allActive == true) {
            return [SELECT Id, Name, User__c, User__r.IsActive FROM Employee__c WHERE Active__c = true ORDER BY Name LIMIT 5000];
        }
        Set<Id> ids = new Set<Id>();
        if (String.isNotBlank(r.employeeIds)) {
            for (String part : r.employeeIds.split(';')) {
                if (String.isNotBlank(part)) {
                    ids.add(Id.valueOf(part.trim()));
                }
            }
        }
        return [SELECT Id, Name, User__c, User__r.IsActive FROM Employee__c WHERE Id IN :ids ORDER BY Name];
    }

    private static Map<String, Leave_and_Holiday__c> existing(List<Employee__c> employees, List<HolidayDate> holidays) {
        Set<Id> employeeIds = new Map<Id, Employee__c>(employees).keySet();
        Date firstDay = holidays[0].day;
        Date lastDay = holidays[holidays.size() - 1].day;
        Map<String, Leave_and_Holiday__c> result = new Map<String, Leave_and_Holiday__c>();
        for (Leave_and_Holiday__c l : [
            SELECT Id, Unique_Key__c, Duration__c, Status__c, Notes__c
            FROM Leave_and_Holiday__c
            WHERE Employee__c IN :employeeIds
            AND Date__c >= :firstDay AND Date__c <= :lastDay
            AND Absence_Category__c = :LeaveValidator.CATEGORY_HOLIDAY
        ]) {
            result.put(l.Unique_Key__c, l);
        }
        return result;
    }

    private static Plan buildPlan(List<Employee__c> employees, List<HolidayDate> holidays, Decimal hours,
        Map<String, Leave_and_Holiday__c> existing) {
        Plan plan = new Plan();
        for (HolidayDate h : holidays) {
            plan.existsByDay.put(h.day, 0);
            plan.updateByDay.put(h.day, 0);
            for (Employee__c e : employees) {
                Leave_and_Holiday__c ex = existing.get(LeaveValidator.key(e.Id, h.day, LeaveValidator.CATEGORY_HOLIDAY));
                if (ex == null) {
                    plan.inserts.add(new Leave_and_Holiday__c(
                        Employee__c = e.Id,
                        Date__c = h.day,
                        Type__c = LeaveValidator.TYPE_HOLIDAY,
                        Absence_Category__c = LeaveValidator.CATEGORY_HOLIDAY,
                        Status__c = LeaveValidator.STATUS_APPROVED,
                        Duration__c = hours,
                        Notes__c = h.name.left(255),
                        OwnerId = (e.User__c != null && e.User__r.IsActive) ? e.User__c : UserInfo.getUserId()
                    ));
                } else if (ex.Duration__c != hours || ex.Status__c != LeaveValidator.STATUS_APPROVED) {
                    plan.updates.add(new Leave_and_Holiday__c(Id = ex.Id, Duration__c = hours, Status__c = LeaveValidator.STATUS_APPROVED));
                    plan.updateByDay.put(h.day, plan.updateByDay.get(h.day) + 1);
                } else {
                    plan.existsByDay.put(h.day, plan.existsByDay.get(h.day) + 1);
                }
            }
        }
        return plan;
    }

    public class Writer implements Queueable {
        List<Leave_and_Holiday__c> inserts;
        List<Leave_and_Holiday__c> updates;
        public Integer created = 0;
        public Integer updated = 0;
        public List<String> errors = new List<String>();

        public Writer(List<Leave_and_Holiday__c> inserts, List<Leave_and_Holiday__c> updates) {
            this.inserts = inserts;
            this.updates = updates;
        }

        /**
         * @description Writes the next BATCH_SIZE rows and queues the rest.
         */
        public void execute(QueueableContext context) {
            List<Leave_and_Holiday__c> nextInserts = new List<Leave_and_Holiday__c>();
            List<Leave_and_Holiday__c> nextUpdates = new List<Leave_and_Holiday__c>();
            List<Leave_and_Holiday__c> nowInserts = new List<Leave_and_Holiday__c>();
            List<Leave_and_Holiday__c> nowUpdates = new List<Leave_and_Holiday__c>();
            Integer room = BATCH_SIZE;
            for (Leave_and_Holiday__c l : updates) {
                if (room > 0) {
                    nowUpdates.add(l);
                    room--;
                } else {
                    nextUpdates.add(l);
                }
            }
            for (Leave_and_Holiday__c l : inserts) {
                if (room > 0) {
                    nowInserts.add(l);
                    room--;
                } else {
                    nextInserts.add(l);
                }
            }
            inserts = nowInserts;
            updates = nowUpdates;
            write();
            if (!nextInserts.isEmpty() || !nextUpdates.isEmpty()) {
                System.enqueueJob(new Writer(nextInserts, nextUpdates));
            }
        }

        public void write() {
            if (!inserts.isEmpty()) {
                List<Database.SaveResult> results = Database.insert(inserts, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        created++;
                    } else {
                        errors.add(String.valueOf(inserts[i].Date__c) + ': ' + results[i].getErrors()[0].getMessage());
                    }
                }
            }
            if (!updates.isEmpty()) {
                List<Database.SaveResult> results = Database.update(updates, false);
                for (Integer i = 0; i < results.size(); i++) {
                    if (results[i].isSuccess()) {
                        updated++;
                    } else {
                        errors.add(results[i].getErrors()[0].getMessage());
                    }
                }
            }
        }
    }

    private static String previewHtml(List<HolidayDate> holidays, Integer employeeCount, Decimal hours,
        Map<String, Leave_and_Holiday__c> existing, Plan plan) {
        String html = '<p>' + holidays.size() + ' holiday dates for ' + employeeCount + ' employees, '
            + LeaveValidator.formatHours(hours) + ' hours each. '
            + plan.inserts.size() + ' rows will be created and ' + plan.updates.size() + ' updated.</p>';
        html += '<table style="border-collapse:collapse;width:100%"><thead><tr>'
            + th('Date') + th('Holiday') + th('Status') + th('Employees') + '</tr></thead><tbody>';
        for (HolidayDate h : holidays) {
            Integer exists = plan.existsByDay.get(h.day);
            Integer toUpdate = plan.updateByDay.get(h.day);
            Integer toCreate = employeeCount - exists - toUpdate;
            String status = toCreate == employeeCount ? 'New'
                : (exists == employeeCount ? 'Exists' : (toUpdate > 0 ? 'Needs update' : 'Partly new'));
            String detail = exists + ' have it';
            if (toUpdate > 0) {
                detail += ', ' + toUpdate + ' to update';
            }
            if (toCreate > 0) {
                detail += ', ' + toCreate + ' to create';
            }
            html += '<tr>' + td(String.valueOf(h.day)) + td(h.name) + td(status) + td(detail) + '</tr>';
        }
        return html + '</tbody></table>';
    }

    private static String th(String text) {
        return '<th style="text-align:left;border-bottom:1px solid #c9c7c5;padding:4px 8px">' + text.escapeHtml4() + '</th>';
    }

    private static String td(String text) {
        return '<td style="border-bottom:1px solid #e5e5e5;padding:4px 8px">' + (text == null ? '' : text.escapeHtml4()) + '</td>';
    }

    private static List<String> firstN(List<String> items, Integer n) {
        List<String> result = new List<String>();
        for (Integer i = 0; i < Math.min(n, items.size()); i++) {
            result.add(items[i]);
        }
        return result;
    }
}
