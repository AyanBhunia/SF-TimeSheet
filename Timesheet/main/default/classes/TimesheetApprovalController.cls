public with sharing class TimesheetApprovalController {
    public class TimesheetWrapper {
        @AuraEnabled public String id { get; set; }
        @AuraEnabled public String timesheetId { get; set; }
        @AuraEnabled public String timesheetName { get; set; }
        @AuraEnabled public String employeeId { get; set; }
        @AuraEnabled public String employeeName { get; set; }
        @AuraEnabled public String projectId { get; set; }
        @AuraEnabled public String projectName { get; set; }
        @AuraEnabled public Integer employeeLineItemCount { get; set; }
        @AuraEnabled public Decimal employeeTotalDuration { get; set; }
        @AuraEnabled public Integer projectLineItemCount { get; set; }
        @AuraEnabled public Decimal projectTotalDuration { get; set; }
        @AuraEnabled public Integer employeeProjectLineItemCount { get; set; }
        @AuraEnabled public Decimal employeeProjectTotalDuration { get; set; }
        @AuraEnabled public Decimal duration { get; set; }
        @AuraEnabled public String timesheetPeriod { get; set; }
        @AuraEnabled public String timesheetStatus { get; set; }
        @AuraEnabled public Date startDate { get; set; }
        @AuraEnabled public Boolean isPartialAllowed { get; set; }
        @AuraEnabled public List<Timesheet_Line_Item__c> lineItems { get; set; }

        // Initializes the timesheet wrapper.
        public TimesheetWrapper(
        String id,
        String timesheetId,
        String timesheetName,
        String employeeId,
        String employeeName,
        String projectId,
        String projectName,
        String timesheetPeriod,
        String timesheetStatus,
        Date startDate
        ) {
            this.id = id;
            this.timesheetId = timesheetId;
            this.timesheetName = timesheetName;
            this.employeeId = employeeId;
            this.employeeName = employeeName;
            this.projectId = projectId;
            this.projectName = projectName;
            this.timesheetPeriod = timesheetPeriod;
            this.timesheetStatus = timesheetStatus;
            this.startDate = startDate;
            this.duration = 0;
            this.lineItems = new List<Timesheet_Line_Item__c>();
        }
}
public class GroupedRow {
    @AuraEnabled public String groupKey { get; set; }
    @AuraEnabled public Integer level { get; set; }
    @AuraEnabled public String groupValue { get; set; }
    @AuraEnabled public Integer rowCount { get; set; }
    @AuraEnabled public Decimal totalDuration { get; set; }
    @AuraEnabled public Integer projectCount { get; set; }
    @AuraEnabled public Date minDate { get; set; }
    @AuraEnabled public Date maxDate { get; set; }
    @AuraEnabled public Integer activityCount { get; set; }
    @AuraEnabled public List<String> statuses { get; set; }
    @AuraEnabled public List<String> lineItemIds { get; set; }

    // Initializes a grouped row.
    public GroupedRow() {
        this.lineItemIds = new List<String>();
        this.statuses = new List<String>();
        this.rowCount = 0;
        this.totalDuration = 0;
        this.projectCount = 0;
        this.activityCount = 0;
    }
}
public class TimesheetDataResponse {
    @AuraEnabled public List<TimesheetWrapper> rows { get; set; }
    @AuraEnabled public List<GroupedRow> groupedRows { get; set; }
    @AuraEnabled public List<String> timesheetNames { get; set; }

    // Initializes the timesheet data response.
    public TimesheetDataResponse() {
        this.rows = new List<TimesheetWrapper>();
        this.groupedRows = new List<GroupedRow>();
    }
}
// Returns the value for the selected grouping column.
private static String getGroupValue(
TimesheetWrapper row,
Integer columnIndex
) {
    switch on columnIndex {
        when 0 {
            return row.employeeName;
        }
    when 1 {
        return row.startDate != null
        ? String.valueOf(row.startDate)
        : '';
    }
when 2 {
    return row.projectName;
}
when 3 {
    if (row.lineItems != null && !row.lineItems.isEmpty()) {
        return row.lineItems[0].Activity__c;
    }
return '';
}
when 4 {
    return row.duration != null
    ? String.valueOf(row.duration)
    : '';
}
when else {
    return '';
}
}
}
// Returns the value for the selected column.
private static String getGroupValueByColumnId(
TimesheetWrapper row,
String columnId
) {
    if (row == null || String.isBlank(columnId)) {
        return '';
    }
switch on columnId {
    when 'employeeName' {
        return row.employeeName;
    }
when 'date' {
    return row.startDate != null
    ? String.valueOf(row.startDate)
    : '';
}
when 'projectName' {
    return row.projectName;
}
when 'activityName' {
    if (row.lineItems != null && !row.lineItems.isEmpty()) {
        return row.lineItems[0].Activity__c;
    }
return '';
}
when 'duration' {
    return row.duration != null
    ? String.valueOf(row.duration)
    : '';
}
when 'status' {
    return row.timesheetStatus;
}
when else {
    return '';
}
}
}
// Builds grouped rows from the selected grouping levels.
private static List<GroupedRow> buildGroupedRows(
List<TimesheetWrapper> rows,
List<Integer> groupingIndexes,
List<String> columnOrder
) {
    List<GroupedRow> result = new List<GroupedRow>();
    if (rows == null || rows.isEmpty()) {
        return result;
    }
if (groupingIndexes == null || groupingIndexes.isEmpty()) {
    return result;
}
Integer maxLevels = Math.min(groupingIndexes.size(), 5);
Map<String, GroupedRow> groupedMap =
new Map<String, GroupedRow>();
for (TimesheetWrapper row : rows) {
    String groupKey = '';
    for (Integer level = 0; level < maxLevels; level++) {
        Integer columnIndex = groupingIndexes[level];
        String columnId =
        columnOrder != null &&
        columnIndex < columnOrder.size()
        ? columnOrder[columnIndex]
        : null;
        String value =
        getGroupValueByColumnId(row, columnId);
        groupKey +=
        '|L' +
        String.valueOf(level) +
        ':' +
        String.valueOf(value);
    }
if (!groupedMap.containsKey(groupKey)) {
    GroupedRow grouped = new GroupedRow();
    grouped.groupKey = groupKey;
    grouped.level = maxLevels - 1;
    Integer lastColumnIndex =
    groupingIndexes[maxLevels - 1];
    String lastColumnId =
    columnOrder != null &&
    lastColumnIndex < columnOrder.size()
    ? columnOrder[lastColumnIndex]
    : null;
    grouped.groupValue =
    getGroupValueByColumnId(
    row,
    lastColumnId
);
groupedMap.put(
groupKey,
grouped
);
}
GroupedRow existing =
groupedMap.get(groupKey);
existing.rowCount++;
if (row.duration != null) {
    existing.totalDuration += row.duration;
}
if (row.lineItems != null) {
    for (
    Timesheet_Line_Item__c lineItem :
    row.lineItems
    ) {
        if (lineItem.Id != null) {
            existing.lineItemIds.add(
            String.valueOf(lineItem.Id)
        );
    }
}
}
}
result.addAll(groupedMap.values());
return result;
}
// Builds grouped summaries.
private static List<GroupedRow> getGroupedRowsFromSOQL(
Set<Id> timesheetIds,
Date startDate,
Date endDate,
List<Integer> groupingIndexes,
List<String> columnOrder
) {
    List<GroupedRow> result = new List<GroupedRow>();

    if (
    timesheetIds == null ||
    timesheetIds.isEmpty() ||
    groupingIndexes == null ||
    groupingIndexes.isEmpty() ||
    columnOrder == null ||
    columnOrder.isEmpty()
    ) {
        return result;
    }
Integer maxLevels =
Math.min(
Math.min(groupingIndexes.size(), 5),
columnOrder.size()
);

/*
* Duration__c cannot be used in SOQL GROUP BY.
* Therefore, whenever Duration is part of the current grouping
* prefix, the grouping level is built from the line-item query
* in Apex instead of adding Duration__c to GROUP BY.
*/
String statusQuery =
'SELECT Id, ' +
'Line_Item_Status__c, ' +
'Timesheet__r.Employee__c, ' +
'Date__c, ' +
'Project__c, ' +
'Activity__c, ' +
'Duration__c ' +
'FROM Timesheet_Line_Item__c ' +
'WHERE Timesheet__c IN :timesheetIds ' +
'AND Line_Item_Status__c IN ' +
'(\'Submitted\') ';

if (startDate != null && endDate != null) {
    statusQuery +=
    'AND Date__c >= :startDate ' +
    'AND Date__c <= :endDate ';
}
statusQuery += ' ORDER BY Date__c ASC';

List<Timesheet_Line_Item__c> statusItems =
Database.query(statusQuery);

for (Integer level = 0; level < maxLevels; level++) {

    Boolean durationInPrefix = false;

    for (Integer prefixLevel = 0; prefixLevel <= level; prefixLevel++) {
        Integer prefixIndex = groupingIndexes[prefixLevel];

        if (prefixIndex >= columnOrder.size()) {
            continue;
        }
    if (columnOrder[prefixIndex] == 'duration') {
        durationInPrefix = true;
        break;
    }
}
/*
* Duration grouping is handled completely from the line items.
* This avoids Duration__c in GROUP BY while still creating the
* same position-based grouping hierarchy expected by LWC.
*/
if (durationInPrefix) {

    Map<String, GroupedRow> durationGroups =
    new Map<String, GroupedRow>();

    Map<String, Set<String>> durationProjectSets =
    new Map<String, Set<String>>();

    Map<String, Set<String>> durationActivitySets =
    new Map<String, Set<String>>();

    Map<String, Set<String>> durationStatusSets =
    new Map<String, Set<String>>();

    Map<String, List<Date>> durationDates =
    new Map<String, List<Date>>();

    for (Timesheet_Line_Item__c item : statusItems) {

        String groupKey = '';

        for (
        Integer currentLevel = 0;
        currentLevel <= level;
        currentLevel++
        ) {

            Integer columnIndex =
            groupingIndexes[currentLevel];

            String columnId =
            columnIndex < columnOrder.size()
            ? columnOrder[columnIndex]
            : null;

            String keyValue;

            switch on columnId {

                when 'employeeName' {
                    keyValue =
                    item.Timesheet__r.Employee__c != null
                    ? String.valueOf(
                    item.Timesheet__r.Employee__c
                    )
                    : '(Blank)';
                }
            when 'date' {
                keyValue =
                item.Date__c != null
                ? String.valueOf(item.Date__c)
                : '(Blank)';
            }
        when 'projectName' {
            keyValue =
            item.Project__c != null
            ? String.valueOf(item.Project__c)
            : '(Blank)';
        }
    when 'activityName' {
        keyValue =
        item.Activity__c != null
        ? String.valueOf(item.Activity__c)
        : '(Blank)';
    }
when 'duration' {
    keyValue =
    item.Duration__c != null
    ? String.valueOf(
    item.Duration__c.setScale(6)
    )
    : '(Blank)';
}
when else {
    keyValue = '(Blank)';
}
}
groupKey +=
'|L' +
String.valueOf(currentLevel) +
':' +
keyValue;
}
if (!durationGroups.containsKey(groupKey)) {

    GroupedRow grouped =
    // Initializes the grouped row.
    new GroupedRow();

    grouped.level = level;
    grouped.groupKey = groupKey;

    durationGroups.put(
    groupKey,
    grouped
);

durationProjectSets.put(
groupKey,
new Set<String>()
);

durationActivitySets.put(
groupKey,
new Set<String>()
);

durationStatusSets.put(
groupKey,
new Set<String>()
);

durationDates.put(
groupKey,
new List<Date>()
);
}
GroupedRow existing =
durationGroups.get(groupKey);

existing.rowCount++;

if (item.Duration__c != null) {
    existing.totalDuration += item.Duration__c;
}
if (item.Project__c != null) {
    durationProjectSets
    .get(groupKey)
    .add(String.valueOf(item.Project__c));
}
if (item.Activity__c != null) {
    durationActivitySets
    .get(groupKey)
    .add(String.valueOf(item.Activity__c));
}
if (item.Date__c != null) {
    durationDates
    .get(groupKey)
    .add(item.Date__c);
}
if (!String.isBlank(item.Line_Item_Status__c)) {
    durationStatusSets
    .get(groupKey)
    .add(item.Line_Item_Status__c);
}
String finalValue = '';

Integer finalColumnIndex =
groupingIndexes[level];

String finalColumnId =
finalColumnIndex < columnOrder.size()
? columnOrder[finalColumnIndex]
: null;

switch on finalColumnId {

    when 'employeeName' {
        finalValue =
        item.Timesheet__r.Employee__c != null
        ? String.valueOf(
        item.Timesheet__r.Employee__c
        )
        : '(Blank)';
    }
when 'date' {
    finalValue =
    item.Date__c != null
    ? String.valueOf(item.Date__c)
    : '(Blank)';
}
when 'projectName' {
    finalValue =
    item.Project__c != null
    ? String.valueOf(item.Project__c)
    : '(Blank)';
}
when 'activityName' {
    finalValue =
    item.Activity__c != null
    ? String.valueOf(item.Activity__c)
    : '(Blank)';
}
when 'duration' {
    finalValue =
    item.Duration__c != null
    ? String.valueOf(
    item.Duration__c.setScale(6)
    )
    : '(Blank)';
}
when else {
    finalValue = '(Blank)';
}
}
existing.groupValue = finalValue;
}
for (String key : durationGroups.keySet()) {

    GroupedRow grouped =
    durationGroups.get(key);

    grouped.projectCount =
    durationProjectSets.get(key).size();

    grouped.activityCount =
    durationActivitySets.get(key).size();

    grouped.statuses.addAll(
    durationStatusSets.get(key)
);

List<Date> dates =
durationDates.get(key);

if (dates != null && !dates.isEmpty()) {

    Date minDate = dates[0];
    Date maxDate = dates[0];

    for (Date d : dates) {
        if (d < minDate) {
            minDate = d;
        }
    if (d > maxDate) {
        maxDate = d;
    }
}
grouped.minDate = minDate;
grouped.maxDate = maxDate;
}
result.add(grouped);
}
continue;
}
/*
* Normal SOQL grouping for Employee, Date, Project and Activity.
* Duration is never added to GROUP BY.
*/
List<String> selectFields =
new List<String>();

List<String> groupFields =
new List<String>();

for (Integer i = 0; i <= level; i++) {

    Integer columnIndex =
    groupingIndexes[i];

    String columnId =
    columnIndex < columnOrder.size()
    ? columnOrder[columnIndex]
    : null;

    switch on columnId {

        when 'employeeName' {
            selectFields.add(
            'Timesheet__r.Employee__c employeeId'
        );

        groupFields.add(
        'Timesheet__r.Employee__c'
    );
}
when 'date' {
    selectFields.add(
    'Date__c groupDate'
);

groupFields.add(
'Date__c'
);
}
when 'projectName' {
    selectFields.add(
    'Project__c projectId'
);

groupFields.add(
'Project__c'
);
}
when 'activityName' {
    selectFields.add(
    'Activity__c groupActivity'
);

groupFields.add(
'Activity__c'
);
}
when 'duration' {
    // Never add Duration__c to GROUP BY.
}
when else {
    // Unsupported grouping column.
}
}
}
if (groupFields.isEmpty()) {
    continue;
}
List<String> aggregateFields =
new List<String>();

aggregateFields.add(
'COUNT(Id) rowCount'
);

aggregateFields.add(
'SUM(Duration__c) totalDuration'
);

Boolean employeeIsGrouped = false;
Boolean dateIsGrouped = false;
Boolean projectIsGrouped = false;
Boolean activityIsGrouped = false;

for (
Integer groupedLevel = 0;
groupedLevel <= level;
groupedLevel++
) {

    Integer groupedIndex =
    groupingIndexes[groupedLevel];

    if (groupedIndex >= columnOrder.size()) {
        continue;
    }
String groupedColumnId =
columnOrder[groupedIndex];

switch on groupedColumnId {

    when 'employeeName' {
        employeeIsGrouped = true;
    }
when 'date' {
    dateIsGrouped = true;
}
when 'projectName' {
    projectIsGrouped = true;
}
when 'activityName' {
    activityIsGrouped = true;
}
when else {
}
}
}
if (!dateIsGrouped) {
    aggregateFields.add(
    'MIN(Date__c) minDate'
);

aggregateFields.add(
'MAX(Date__c) maxDate'
);
}
if (!projectIsGrouped) {
    aggregateFields.add(
    'COUNT_DISTINCT(Project__c) projectCount'
);
}
if (!activityIsGrouped) {
    aggregateFields.add(
    'COUNT_DISTINCT(Activity__c) activityCount'
);
}
String query =
'SELECT ' +
String.join(selectFields, ', ') +
', ' +
String.join(aggregateFields, ', ') +
' FROM Timesheet_Line_Item__c ' +
'WHERE Timesheet__c IN :timesheetIds ' +
'AND Line_Item_Status__c IN ' +
'(\'Submitted\') ';

if (startDate != null && endDate != null) {
    query +=
    'AND Date__c >= :startDate ' +
    'AND Date__c <= :endDate ';
}
query +=
'GROUP BY ' +
String.join(groupFields, ', ');

List<AggregateResult> aggregateResults =
Database.query(query);

for (AggregateResult ar : aggregateResults) {

    GroupedRow grouped =
    // Initializes the grouped row.
    new GroupedRow();

    grouped.level = level;

    grouped.rowCount =
    ar.get('rowCount') != null
    ? (Integer) ar.get('rowCount')
    : 0;

    grouped.totalDuration =
    ar.get('totalDuration') != null
    ? (Decimal) ar.get('totalDuration')
    : 0;

    if (!projectIsGrouped) {
        grouped.projectCount =
        ar.get('projectCount') != null
        ? (Integer) ar.get('projectCount')
        : 0;
    }
if (!dateIsGrouped) {
    grouped.minDate =
    ar.get('minDate') != null
    ? (Date) ar.get('minDate')
    : null;

    grouped.maxDate =
    ar.get('maxDate') != null
    ? (Date) ar.get('maxDate')
    : null;
}
if (!activityIsGrouped) {
    grouped.activityCount =
    ar.get('activityCount') != null
    ? (Integer) ar.get('activityCount')
    : 0;
}
String groupKey = '';

for (
Integer currentLevel = 0;
currentLevel <= level;
currentLevel++
) {

    Integer columnIndex =
    groupingIndexes[currentLevel];

    String columnId =
    columnIndex < columnOrder.size()
    ? columnOrder[columnIndex]
    : null;

    Object value;
    String keyValue;

    switch on columnId {

        when 'employeeName' {
            value = ar.get('employeeId');

            keyValue =
            value != null
            ? String.valueOf(value)
            : '(Blank)';
        }
    when 'date' {
        value = ar.get('groupDate');

        keyValue =
        value != null
        ? String.valueOf(value)
        : '(Blank)';
    }
when 'projectName' {
    value = ar.get('projectId');

    keyValue =
    value != null
    ? String.valueOf(value)
    : '(Blank)';
}
when 'activityName' {
    value = ar.get('groupActivity');

    keyValue =
    value != null
    ? String.valueOf(value)
    : '(Blank)';
}
when 'duration' {
    // This branch is reached only when Duration is
    // represented by the duration-safe path above.
    value = null;
    keyValue = '(Blank)';
}
when else {
    value = null;
    keyValue = '(Blank)';
}
}
groupKey +=
'|L' +
String.valueOf(currentLevel) +
':' +
keyValue;

if (currentLevel == level) {
    grouped.groupValue = keyValue;
}
}
grouped.groupKey = groupKey;

Set<String> statusSet =
new Set<String>();

for (
Timesheet_Line_Item__c statusItem :
statusItems
) {

    if (
    String.isBlank(
    statusItem.Line_Item_Status__c
    )
    ) {
        continue;
    }
String statusKey = '';

for (
Integer statusLevel = 0;
statusLevel <= level;
statusLevel++
) {

    Integer statusColumnIndex =
    groupingIndexes[statusLevel];

    String statusColumnId =
    statusColumnIndex < columnOrder.size()
    ? columnOrder[statusColumnIndex]
    : null;

    switch on statusColumnId {

        when 'employeeName' {
            statusKey +=
            '|L' +
            String.valueOf(statusLevel) +
            ':' +
            (
            statusItem.Timesheet__r.Employee__c != null
            ? String.valueOf(
            statusItem.Timesheet__r.Employee__c
            )
            : '(Blank)'
        );
    }
when 'date' {
    statusKey +=
    '|L' +
    String.valueOf(statusLevel) +
    ':' +
    (
    statusItem.Date__c != null
    ? String.valueOf(
    statusItem.Date__c
    )
    : '(Blank)'
);
}
when 'projectName' {
    statusKey +=
    '|L' +
    String.valueOf(statusLevel) +
    ':' +
    (
    statusItem.Project__c != null
    ? String.valueOf(
    statusItem.Project__c
    )
    : '(Blank)'
);
}
when 'activityName' {
    statusKey +=
    '|L' +
    String.valueOf(statusLevel) +
    ':' +
    (
    statusItem.Activity__c != null
    ? String.valueOf(
    statusItem.Activity__c
    )
    : '(Blank)'
);
}
when else {
    statusKey +=
    '|L' +
    String.valueOf(statusLevel) +
    ':(Blank)';
}
}
}
if (statusKey == groupKey) {
    statusSet.add(
    statusItem.Line_Item_Status__c
);
}
}
grouped.statuses.addAll(statusSet);

result.add(grouped);
}
}
return result;
}
// Retrieves pending timesheet data for manager approval.
@AuraEnabled
// Retrieves TimesheetData data.
public static TimesheetDataResponse getTimesheetData(
String dateRange,
Date customStartDate,
Date customEndDate,
List<Integer> groupingIndexes,
List<String> columnOrder
) {
    Date startDate;
    Date endDate;
    if (dateRange == 'Current Week') {
        startDate = Date.today().toStartOfWeek();
        endDate = startDate.addDays(6);
    } else if (dateRange == 'Last Week') {
    startDate = Date.today().toStartOfWeek().addDays(-7);
    endDate = startDate.addDays(6);
} else if (dateRange == 'Current Month') {
startDate = Date.today().toStartOfMonth();
endDate = startDate.addMonths(1).addDays(-1);
} else if (dateRange == 'Last Month') {
startDate = Date.today().toStartOfMonth().addMonths(-1);
endDate = Date.today().toStartOfMonth().addDays(-1);
} else if (dateRange == 'Custom') {
startDate = customStartDate;
endDate = customEndDate;
} else if (dateRange == 'All Pending') {
startDate = null;
endDate = null;
}
String userId = UserInfo.getUserId();
String query =
'SELECT Id, Name, Employee__c,Employee__r.Name, Start_Date__c, End_Date__c, Status__c, Is_Partial_Allowed__c, Total_Hours__c, ' +
'(SELECT Id, Date__c, Duration__c, Project__c, Project__r.Name, ' +
'Type__c, Description__c, Billable__c, Line_Item_Status__c, ' +
'Rejection_Notes__c, Activity__c, Absence_Category__c ' +
'FROM Timesheets__r ';
if (startDate != null && endDate != null) {
    query +=
    'WHERE Line_Item_Status__c IN (\'Submitted\') ' +
    'AND Date__c >= :startDate ' +
    'AND Date__c <= :endDate ';
} else {
query +=
'WHERE Line_Item_Status__c IN (\'Submitted\') ';
}
query +=
'ORDER BY Date__c ASC) ' +
'FROM Timesheet__c ' +
'WHERE Manager__c = :userId ' ;
List<Timesheet__c> timesheets =
Database.query(query);
Set<String> timesheetNameSet = new Set<String>();

for (Timesheet__c ts : timesheets) {
    if (
        ts.Status__c == 'Submitted' &&
        !String.isBlank(ts.Name)
    ) {
        timesheetNameSet.add(ts.Name);
    }
}
Set<Id> timesheetIds = new Set<Id>();
for (Timesheet__c ts : timesheets) {
    if (ts.Timesheets__r != null && !ts.Timesheets__r.isEmpty()) {
        timesheetIds.add(ts.Id);
    }
}
Map<Id, AggregateResult> employeeAggregates =
new Map<Id, AggregateResult>();
String employeeAggregateQuery =
'SELECT Timesheet__r.Employee__c employeeId, ' +
'COUNT(Id) lineItemCount, ' +
'SUM(Duration__c) totalDuration ' +
'FROM Timesheet_Line_Item__c ' +
'WHERE Timesheet__c IN :timesheetIds ' +
'AND Line_Item_Status__c IN (\'Submitted\') ';
if (startDate != null && endDate != null) {
    employeeAggregateQuery +=
    'AND Date__c >= :startDate ' +
    'AND Date__c <= :endDate ';
}
employeeAggregateQuery +=
'GROUP BY Timesheet__r.Employee__c';
for (AggregateResult ar :
Database.query(employeeAggregateQuery)
) {
    Id employeeId = (Id) ar.get('employeeId');
    employeeAggregates.put(
    employeeId,
    ar
);
}
Map<Id, AggregateResult> projectAggregates =
new Map<Id, AggregateResult>();
String projectAggregateQuery =
'SELECT Project__c projectId, ' +
'COUNT(Id) lineItemCount, ' +
'SUM(Duration__c) totalDuration ' +
'FROM Timesheet_Line_Item__c ' +
'WHERE Timesheet__c IN :timesheetIds ' +
'AND Line_Item_Status__c IN (\'Submitted\') ' +
'AND Project__c != null ';
if (startDate != null && endDate != null) {
    projectAggregateQuery +=
    'AND Date__c >= :startDate ' +
    'AND Date__c <= :endDate ';
}
projectAggregateQuery +=

'WITH SECURITY_ENFORCED ' +
'GROUP BY Project__c';
for (AggregateResult ar :
Database.query(projectAggregateQuery)
) {
    Id projectId = (Id) ar.get('projectId');
    projectAggregates.put(
    projectId,
    ar
);
}
Map<String, AggregateResult> employeeProjectAggregates =
new Map<String, AggregateResult>();
String employeeProjectAggregateQuery =
'SELECT ' +
'Timesheet__r.Employee__c employeeId, ' +
'Project__c projectId, ' +
'COUNT(Id) lineItemCount, ' +
'SUM(Duration__c) totalDuration ' +
'FROM Timesheet_Line_Item__c ' +
'WHERE Timesheet__c IN :timesheetIds ' +
'AND Line_Item_Status__c IN (\'Submitted\') ' +
'AND Project__c != null ';
if (startDate != null && endDate != null) {
    employeeProjectAggregateQuery +=
    'AND Date__c >= :startDate ' +
    'AND Date__c <= :endDate ';
}
employeeProjectAggregateQuery +=
'GROUP BY Timesheet__r.Employee__c, Project__c';
for (AggregateResult ar :
Database.query(employeeProjectAggregateQuery)
) {
    Id employeeId =
    (Id) ar.get('employeeId');
    Id projectId =
    (Id) ar.get('projectId');
    String key =
    String.valueOf(employeeId) +
    '_' +
    String.valueOf(projectId);
    employeeProjectAggregates.put(
    key,
    ar
);
}
Map<String, TimesheetWrapper> wrapperMap =
new Map<String, TimesheetWrapper>();
for (Timesheet__c ts : timesheets) {
    String period =
    (ts.Start_Date__c != null
    ? ts.Start_Date__c.format()
    : '') +
    ' to ' +
    (ts.End_Date__c != null
    ? ts.End_Date__c.format()
    : '');

    if (ts.Is_Partial_Allowed__c == false) {
        if (ts.Status__c != 'Submitted') {
            continue;
        }
        String key = String.valueOf(ts.Id);
        TimesheetWrapper newWrapper = new TimesheetWrapper(
            key,
            String.valueOf(ts.Id),
            ts.Name,
            String.valueOf(ts.Employee__c),
            ts.Employee__r.Name,
            null,
            'All Projects',
            period,
            ts.Status__c,
            ts.Start_Date__c
        );
        newWrapper.isPartialAllowed = false;
        newWrapper.duration = (ts.Total_Hours__c != null) ? ts.Total_Hours__c : 0;
        wrapperMap.put(key, newWrapper);
        continue;
    }

    if (
    ts.Timesheets__r == null ||
    ts.Timesheets__r.isEmpty()
    ) {
        continue;
    }

for (Timesheet_Line_Item__c line : ts.Timesheets__r) {
    String projName =
    (line.Project__c != null)
    ? line.Project__r.Name
    : line.Type__c;
    if (line.Type__c == 'Absence') {
        projName = 'Absence';
    }
String key =
ts.Id + '_' + projName;
if (!wrapperMap.containsKey(key)) {
    TimesheetWrapper newWrapper =
    // Initializes the wrapper.
    new TimesheetWrapper(
    key,
    String.valueOf(ts.Id),
    ts.Name,
    String.valueOf(ts.Employee__c),
    ts.Employee__r.Name,
    String.valueOf(line.Project__c),
    projName,
    period,
    ts.Status__c,
    ts.Start_Date__c
);
newWrapper.isPartialAllowed = true;
if (
ts.Employee__c != null &&
employeeAggregates.containsKey(ts.Employee__c)
) {
    AggregateResult employeeAgg =
    employeeAggregates.get(ts.Employee__c);
    newWrapper.employeeLineItemCount =
    (Integer) employeeAgg.get('lineItemCount');
    newWrapper.employeeTotalDuration =
    (Decimal) employeeAgg.get('totalDuration');
}
if (
line.Project__c != null &&
projectAggregates.containsKey(line.Project__c)
) {
    AggregateResult projectAgg =
    projectAggregates.get(line.Project__c);
    newWrapper.projectLineItemCount =
    (Integer) projectAgg.get('lineItemCount');
    newWrapper.projectTotalDuration =
    (Decimal) projectAgg.get('totalDuration');
}
if (
ts.Employee__c != null &&
line.Project__c != null
) {
    String employeeProjectKey =
    String.valueOf(ts.Employee__c) +
    '_' +
    String.valueOf(line.Project__c);
    if (
    employeeProjectAggregates.containsKey(
    employeeProjectKey
    )
    ) {
        AggregateResult employeeProjectAgg =
        employeeProjectAggregates.get(
        employeeProjectKey
    );
    newWrapper.employeeProjectLineItemCount =
    (Integer) employeeProjectAgg.get(
    'lineItemCount'
);
newWrapper.employeeProjectTotalDuration =
(Decimal) employeeProjectAgg.get(
'totalDuration'
);
}
}
wrapperMap.put(
key,
newWrapper
);
}
TimesheetWrapper tw =
wrapperMap.get(key);
tw.duration +=
(line.Duration__c != null
? line.Duration__c
: 0);
tw.lineItems.add(line);
}
}
TimesheetDataResponse response =
// Initializes the response.
new TimesheetDataResponse();
response.rows.addAll(wrapperMap.values());
response.timesheetNames.addAll(timesheetNameSet);
if (groupingIndexes != null && !groupingIndexes.isEmpty()) {
    response.groupedRows =
    getGroupedRowsFromSOQL(
    timesheetIds,
    startDate,
    endDate,
    groupingIndexes,
    columnOrder
);
}
return response;
}
// Approves the selected timesheets.
@AuraEnabled
public static String approveTimesheets(List<Id> timesheetIds) {
    if (timesheetIds == null || timesheetIds.isEmpty()) {
        return 'Error: No timesheets provided.';
    }

    try {
        for (Id tsId : timesheetIds) {
            Boolean processed = approveSalesforceApproval(tsId);

            if (!processed) {
                return 'Error: No pending approval request found for Timesheet.';
            }

            updateNonPartialLineItems(tsId, 'Approved', null);
            updateNonPartialTimesheetStatus(tsId, 'Approved');
        }

        return 'Success';
    } catch (Exception e) {
        return 'Error: ' + e.getMessage();
    }
}

// Approves the selected line items.
@AuraEnabled
public static String approveLineItems(List<Id> lineItemIds) {
    if (lineItemIds == null || lineItemIds.isEmpty()) {
        return 'Error: No line items provided.';
    }

    try {
        List<Timesheet_Line_Item__c> selectedItems = [
            SELECT Id,
                   Line_Item_Status__c,
                   Timesheet__c,
                   Timesheet__r.Is_Partial_Allowed__c
            FROM Timesheet_Line_Item__c
            WHERE Id IN :lineItemIds
        ];

        List<Timesheet_Line_Item__c> itemsToApprove =
            new List<Timesheet_Line_Item__c>();

        for (Timesheet_Line_Item__c li : selectedItems) {
            if (
                li.Timesheet__r.Is_Partial_Allowed__c == true
                && li.Line_Item_Status__c == 'Submitted'
            ) {
                li.Line_Item_Status__c = 'Approved';
                itemsToApprove.add(li);
            }
        }

        if (!itemsToApprove.isEmpty()) {
            SObjectAccessDecision decision =
                Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    itemsToApprove,
                    true
                );

            update decision.getRecords();
        }

        // Parent status for partial Timesheets is handled by
        // TimesheetLineItemTriggerHandler.
        return 'Success';
    } catch (Exception e) {
        return 'Error: ' + e.getMessage();
    }
}

// Rejects selected line items with rejection notes.
@AuraEnabled
public static String rejectLineItemsWithNotes(
    List<Id> lineItemIds,
    String rejectionNotes
) {
    if (lineItemIds == null || lineItemIds.isEmpty()) {
        return 'Error: No line items provided.';
    }

    try {
        List<Timesheet_Line_Item__c> selectedItems = [
            SELECT Id,
                   Line_Item_Status__c,
                   Rejection_Notes__c,
                   Timesheet__c,
                   Timesheet__r.Is_Partial_Allowed__c
            FROM Timesheet_Line_Item__c
            WHERE Id IN :lineItemIds
        ];

        List<Timesheet_Line_Item__c> itemsToReject =
            new List<Timesheet_Line_Item__c>();

        for (Timesheet_Line_Item__c li : selectedItems) {
            if (
                li.Timesheet__r.Is_Partial_Allowed__c == true
                && li.Line_Item_Status__c == 'Submitted'
            ) {
                li.Line_Item_Status__c = 'New';
                li.Rejection_Notes__c = rejectionNotes;
                itemsToReject.add(li);
            }
        }

        if (!itemsToReject.isEmpty()) {
            SObjectAccessDecision decision =
                Security.stripInaccessible(
                    AccessType.UPDATABLE,
                    itemsToReject,
                    true
                );

            update decision.getRecords();
        }

        // Parent status for partial Timesheets is handled by
        // TimesheetLineItemTriggerHandler.
        return 'Success';
    } catch (Exception e) {
        return 'Error: ' + e.getMessage();
    }
}

// Updates line items for a non-partial Timesheet.
private static void updateNonPartialLineItems(
    Id timesheetId,
    String newStatus,
    String rejectionNotes
) {
    List<Timesheet_Line_Item__c> lineItems = [
        SELECT Id,
               Line_Item_Status__c,
               Rejection_Notes__c
        FROM Timesheet_Line_Item__c
        WHERE Timesheet__c = :timesheetId
        AND Line_Item_Status__c = 'Submitted'
    ];

    for (Timesheet_Line_Item__c lineItem : lineItems) {
        lineItem.Line_Item_Status__c = newStatus;

        if (newStatus == 'New') {
            lineItem.Rejection_Notes__c = rejectionNotes;
        }
    }

    if (!lineItems.isEmpty()) {
        SObjectAccessDecision decision =
            Security.stripInaccessible(
                AccessType.UPDATABLE,
                lineItems,
                true
            );

        update decision.getRecords();
    }
}

// Updates the parent Timesheet status for non-partial approval/rejection.
// The line-item trigger skips parent status updates when partial is false.
private static void updateNonPartialTimesheetStatus(
    Id timesheetId,
    String newStatus
) {
    Timesheet__c timesheet = [
        SELECT Id, Is_Partial_Allowed__c
        FROM Timesheet__c
        WHERE Id = :timesheetId
        LIMIT 1
    ];

    if (timesheet.Is_Partial_Allowed__c == false) {
        timesheet.Status__c = newStatus;

        SObjectAccessDecision decision =
            Security.stripInaccessible(
                AccessType.UPDATABLE,
                new List<Timesheet__c>{ timesheet },
                true
            );

        update decision.getRecords();
    }
}

// Rejects the selected timesheets.
@AuraEnabled
public static String rejectTimesheets(
    List<Id> timesheetIds,
    String rejectionNotes
) {
    if (timesheetIds == null || timesheetIds.isEmpty()) {
        return 'Error: No timesheets provided.';
    }

    try {
        for (Id tsId : timesheetIds) {
            Boolean processed =
                rejectSalesforceApproval(tsId, rejectionNotes);

            if (!processed) {
                return 'Error: No pending approval request found for Timesheet.';
            }

            updateNonPartialLineItems(
                tsId,
                'New',
                rejectionNotes
            );

            updateNonPartialTimesheetStatus(
                tsId,
                'New'
            );
        }

        return 'Success';
    } catch (Exception e) {
        return 'Error: ' + e.getMessage();
    }
}

// Updates new line items when a timesheet is submitted.
public static void updateSubmittedTimesheetLineItems(Id timesheetId) {
    try {
        Timesheet__c timesheet = [
        SELECT Id, Status__c
        FROM Timesheet__c
        WHERE Id = :timesheetId
        LIMIT 1
        ];
        if (timesheet.Status__c == 'Submitted') {

           
            List<Timesheet_Line_Item__c> lineItems = [
            SELECT Id, Line_Item_Status__c
            FROM Timesheet_Line_Item__c
            WHERE Timesheet__c = :timesheetId
            AND Line_Item_Status__c = 'New'
            ];


if (lineItems.isEmpty()) {
    throw new AuraHandledException(
        'There are no new line items to submit.'
    );
}

            for (Timesheet_Line_Item__c lineItem : lineItems) {
                lineItem.Line_Item_Status__c = 'Submitted';
            }
        if (!lineItems.isEmpty()) {
            SObjectAccessDecision decision =
            Security.stripInaccessible(
            AccessType.UPDATABLE,
            lineItems,
            true
        );
        update decision.getRecords();
    }
}
} catch (Exception e) {
AuraHandledException ae =
// Handles AuraHandledException.
new AuraHandledException(e.getMessage());
throw ae;
}
}
// Approves the pending Salesforce approval request.
private static Boolean approveSalesforceApproval(Id timesheetId) {
    List<ProcessInstanceWorkitem> pendingWorkItems = [
        SELECT Id
        FROM ProcessInstanceWorkitem
        WHERE ProcessInstance.TargetObjectId = :timesheetId
        AND ProcessInstance.Status = 'Pending'
    ];

    if (pendingWorkItems.isEmpty()) {
        return false;
    }

    for (ProcessInstanceWorkitem wi : pendingWorkItems) {
        Approval.ProcessWorkitemRequest req =
            new Approval.ProcessWorkitemRequest();

        req.setComments('Approved by Manager');
        req.setAction('Approve');
        req.setWorkitemId(wi.Id);

        Approval.ProcessResult result = Approval.process(req);

        if (!result.isSuccess()) {
            String errorMessage = 'Approval failed.';
            if (result.getErrors() != null && !result.getErrors().isEmpty()) {
                errorMessage = result.getErrors()[0].getMessage();
            }
            throw new AuraHandledException(errorMessage);
        }
    }

    return true;
}

// Rejects the pending Salesforce approval request.
private static Boolean rejectSalesforceApproval(
    Id timesheetId,
    String rejectionNotes
) {
    List<ProcessInstanceWorkitem> pendingWorkItems = [
        SELECT Id
        FROM ProcessInstanceWorkitem
        WHERE ProcessInstance.TargetObjectId = :timesheetId
        AND ProcessInstance.Status = 'Pending'
    ];

    if (pendingWorkItems.isEmpty()) {
        return false;
    }

    for (ProcessInstanceWorkitem wi : pendingWorkItems) {
        Approval.ProcessWorkitemRequest req =
            new Approval.ProcessWorkitemRequest();

        req.setComments(rejectionNotes);
        req.setAction('Reject');
        req.setWorkitemId(wi.Id);

        Approval.ProcessResult result = Approval.process(req);

        if (!result.isSuccess()) {
            String errorMessage = 'Rejection failed.';
            if (result.getErrors() != null && !result.getErrors().isEmpty()) {
                errorMessage = result.getErrors()[0].getMessage();
            }
            throw new AuraHandledException(errorMessage);
        }
    }

    return true;
}
}
