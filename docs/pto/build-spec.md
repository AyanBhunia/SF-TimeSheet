# PTO build spec (implementation contracts)

Companion to `pto-technical-plan.md`. This file fixes names, API shapes and UI behaviour so every piece fits together.

Repo facts:
- Source root: `Timesheet/main/default`. Package namespace `dbt`, but source never uses the `dbt__` prefix (except the existing `TimesheetTrigger`, which already does).
- API version 64.0 for every new component.
- Today in the org: 2026-10-02. Timesheets are weekly, Monday to Sunday (`Start_Date__c` Monday, `End_Date__c` Sunday).
- Look and feel: plain SLDS, industrial, no gimmicks. Use `slds-*` utility classes first; keep custom CSS short. No emoji.

## Metadata

### Object `Leave_and_Holiday__c`
- Label "Leave and Holiday", plural "Leaves and Holidays". Name field: AutoNumber `LH-{000000}`, label "Leave Number", starting number 1.
- `sharingModel` Private, `externalSharingModel` Private, `deploymentStatus` Deployed, `enableReports` true, `enableSearch` false, `enableActivities` false, `enableHistory` false, `enableBulkApi` true, `enableSharing` true, `enableStreamingApi` true. No tab, no layout, no list views.

| Field | Type | Details |
| --- | --- | --- |
| `Employee__c` | Lookup(Employee__c) | required true, deleteConstraint Restrict, relationshipName `Leaves_and_Holidays`, relationshipLabel "Leaves and Holidays" |
| `Date__c` | Date | required true |
| `Type__c` | Picklist, restricted | values Leave (default), Holiday |
| `Status__c` | Picklist, restricted | values New, Submitted (default), Approved |
| `Absence_Category__c` | Picklist, restricted | exactly the line item values in the same order: On Duty, Sick Leave, Permission, PTO-Planned, PTO-Un Planned, Holiday |
| `Duration__c` | Number(4,2) | label "Duration (Hours)" |
| `Notes__c` | LongTextArea(2000) | visibleLines 4 |
| `Approver__c` | Lookup(User) | deleteConstraint SetNull, relationshipName `Leave_Approvals` |
| `Unique_Key__c` | Text(80) | unique true, externalId true, caseSensitive false |

Required fields (`Employee__c`, `Date__c`) must NOT appear in permission set fieldPermissions.

### Custom metadata `Timesheet_Default_Value__mdt`
Six new fields, Number precision 4 scale 2, `fieldManageability` SubscriberControlled: `Max_PTO_Planned_Hours__c`, `Max_PTO_Unplanned_Hours__c`, `Max_Sick_Leave_Hours__c`, `Max_Permission_Hours__c`, `Max_On_Duty_Hours__c`, `Max_Holiday_Hours__c`. Record `Default_Values` gets 8.0 for each.

### Validation rules on `Timesheet_Line_Item__c`
`Duration` and `Eight_hour_limit_for_out_of_office`: replace the fixed `8` with a `CASE(TEXT(Absence_Category__c), ...)` over the six metadata fields, default 8. Keep names, messages and the narrower category filter of the second rule.

### Custom permissions
`PTO_Approve_Team` (label "PTO: Approve Team Leave") and `PTO_Admin_All` (label "PTO: Administer All Leave").

### Tab and app
- Lightning component tab `PTO` (label "PTO", `lwcComponent` = `ptoApp`, motif `Custom20: Airplane`).
- Add `PTO` to `Timesheet.app-meta.xml` tabs right after `Timesheet__c`.

### Permission sets
| | Timesheet_User | TimeSheet_Manager | Timesheet_HR_Admin |
| --- | --- | --- | --- |
| Leave object | R C E | R C E | R C E D, View All, Modify All |
| Fields Type, Absence_Category, Duration, Notes | read+edit | read+edit | read+edit |
| Fields Status, Approver, Unique_Key | read | read | read+edit |
| Custom permission | — | PTO_Approve_Team | PTO_Admin_All |
| Tab PTO | Visible | Visible | Visible |
| Classes | PtoController | PtoController | PtoController, HolidayLoader |

## Apex contracts (`PtoController`, all `@AuraEnabled`, imperative calls, no cacheable)

Dates cross the wire as `YYYY-MM-DD` strings in responses, in a field named `leaveDate` (`date` is reserved in Apex); the LWCs copy it to `date` on receipt. Errors are thrown as `AuraHandledException` with a readable message when called from Lightning, and as `PtoController.PtoException` from any other context.

Reads that must see records the user doesn't own run through `PtoData` (without sharing). `PtoController` checks access before every call.

1. `getContext()` returns
```
{
  employee: { id, name, managerId, managerName, hasManager, available } | null,   // current user's Employee__c; available = hours
  isManager, isHrAdmin, canApprove,           // canApprove = isManager || isHrAdmin
  employees: [ { id, name, managerName, hasManager } ],  // apply-for picker; manager: direct reports; HR: all active employees; excludes self
  categories: [ { value, label, maxHours } ], // leave categories (no Holiday), in picklist order
  dailyMax,                                   // Maximum_Working_Hrs_Per_Day__c
  today                                       // 'YYYY-MM-DD'
}
```
2. `getDayRecords(Id employeeId, Date startDate, Date endDate)` returns
```
{
  employee: { id, name, managerName, hasManager, available },
  leaves:    [ { id, leaveDate, type, category, hours, status, notes } ],   // all statuses
  lineItems: [ { id, leaveDate, type, category, hours } ]                  // Attendance and Absence
}
```
3. `submitLeave(Id employeeId, String rowsJson)`; rowsJson = `[ { date:'YYYY-MM-DD', category, hours, notes } ]`. Returns
```
{ success, rowErrors: [ '' | message ] (same order as input), warnings: [ message ], submittedCount, resubmittedCount }
```
4. `getPast(Id employeeId, Integer offsetRows)`; employeeId null = current user. Returns
```
{ rows: [ { id, leaveDate, type, category, hours, status, displayStatus, notes } ], hasMore, offset }
```
25 rows per page (query fetches 26). `displayStatus`: Submitted, Approved, Rejected, or "Conversion error" (status New whose latest note line starts with `Not in Timesheet`).
5. `getOverview(Id employeeId, Integer year)` returns
```
{ available, takenHours, pendingHours, nextLeaveDate, nextLeaveCount,
  byCategory: [ { category, approved, submitted } ] }
```
6. `getTeamWeek(Date weekStart)` (manager: direct reports; HR: all active employees, max 200) returns
```
{ weekStart, days: [7 x 'YYYY-MM-DD'], rows: [ { employeeId, name, hours: [7 numbers] } ] }
```
7. `getPendingApprovals()` returns `[ { id, employeeId, employeeName, leaveDate, type, category, hours, notes } ]` sorted by date ascending. Nobody sees their own leave here.
8. `approveLeave(List<Id> leaveIds)` and `rejectLeave(List<Id> leaveIds, String reason)` return `{ processed, errors: [ message ] }`. An approved day that can't be written to its timesheet is reported in `errors`.

`getContext()` also returns `pendingCount` (rows waiting for this approver).

## LWC

All components: API 64.0, `isExposed` false except `ptoApp` (exposed, target `lightning__Tab`). Import Apex as `@salesforce/apex/PtoController.<method>`. Toasts via `lightning/platformShowToastEvent`. Show `lightning-spinner` while loading. Error text from `error.body.message`.

### `ptoTable` (shared table, renders only, parent owns data)
API:
- `@api columns` = `[ { fieldName, label, type: 'text'|'date'|'number'|'picklist'|'status', editable, sortable, options: [ {label, value} ], align: 'left'|'right', width } ]`
- `@api rows` = `[ { key, locked, error, info, ...values } ]` (`locked` greys the row and disables inputs; `error` red text under the row; `info` blue text under the row)
- `@api rowActions` = `[ { name, label, variant } ]` (variant is a `lightning-button` variant). Buttons render in the last column for unlocked rows only.
- `@api sortedBy`, `@api sortedDirection` ('asc' | 'desc'); `@api emptyMessage`.
- Events: `cellchange` detail `{ rowKey, fieldName, value }`; `rowaction` detail `{ rowKey, action }`; `sort` detail `{ fieldName, direction }` (clicking a sortable header toggles direction).
- Templates cannot index objects, so compute a `viewRows` getter with `cells` per row (flags `isText`, `isDate`, `isNumber`, `isPicklist`, `isStatus`, `isEditable`).
- Editable cells: `lightning-input` (type date / number with step 0.25 / text), `variant="label-hidden"`. Picklist cells use a native SLDS `select` so the dropdown isn't clipped by the scrolling table; `renderedCallback` keeps its value in sync. Fire `cellchange` on change.
- `status` cells render a pill: `slds-badge` with a class per status (Submitted = warning, Approved = success, Rejected / Conversion error = error, Holiday = neutral).
- Table: `slds-table slds-table_bordered slds-table_cell-buffer slds-table_fixed-layout` inside an `overflow-x:auto` wrapper. Locked rows: grey background. Error rows: light warning background.

### `ptoConfirmModal` (extends `LightningModal`)
- `@api mode` ('approve' | 'reject'), `@api summary` (string like "Priya Natarajan · 2026-10-12 · PTO-Planned · 8 h").
- Approve: confirm text, buttons Cancel / Approve. Reject: required textarea "Reason (added to the employee's notes)"; Reject button shows an inline error if blank.
- `this.close({ confirmed: true, reason })` or `this.close({ confirmed: false })`.

### `ptoPast`
- `@api employeeId`. Loads `getPast(employeeId, offset)`; Previous / Next buttons, "Page N"; shows rows `Showing a–b`.
- Columns: Date, Type, Category, Hours (right), Status (status pill using `displayStatus`), Notes.
- `@api refresh()` reloads page 1.

### `ptoApprove`
- Loads `getPendingApprovals()`. Columns: Employee, Date, Category, Hours, Notes; all sortable client side. Row actions Approve (success) and Reject (destructive).
- Each action opens `ptoConfirmModal`; on confirm call `approveLeave([id])` / `rejectLeave([id], reason)`, toast, reload, and dispatch `changed` event (bubbles false).
- Empty state: "No leave is waiting for your approval."

### `ptoOverview`
- `@api context` (from `getContext`), `@api employeeId`.
- Four tiles: Available (h), Taken this year (Approved), Pending (Submitted), Next leave (date + days).
- Bar chart (Chart.js from static resource `jsChart`, horizontal bars, stacked Approved + Submitted) of hours by category for the current year.
- Managers and HR: heatmap of the team week using Chart.js matrix (static resource `jsChartMatrix`, load after `jsChart`), rows = employees, columns = Mon..Sun, cell colour by hours (0, ≤2, ≤4, <8, ≥8). Previous / Next week buttons. Use `getTeamWeek(weekStart)` with Monday of the current week.
- `@api refresh()` reloads.

### `ptoApply`
- `@api context`. Employee picker for managers and HR (`context.employees` plus "Me"), read-only name for users.
- Inputs: start date, end date, category (combobox of `context.categories`), hours per day (max = category max), "Include Saturday and Sunday" checkbox.
- Table (`ptoTable`) starts with one empty row. Changing dates fills one row per day (weekdays only unless the checkbox is ticked) and loads `getDayRecords` for the range: Submitted/Approved leave and absence line items appear as locked rows; rejected (New) leave matching a row's date + category shows an info line "Resubmits the rejected request".
- Client checks per row, same as the server: hours > 0 and ≤ category max; no Submitted/Approved leave or absence line item with the same date + category; same date + category not entered twice; day total (line items that day + Submitted/Approved leave without a matching line item + the new rows) ≤ `dailyMax`.
- Buttons: Add row, Clear, Review. Review shows days, total hours, balance after, a warning box if over balance, a warning if the employee has no manager ("This employee has no manager, so the request will stay pending until HR approves it."), "You won't be able to edit these after submitting.", Back / Submit.
- Submit calls `submitLeave`; on success toast, reset to one empty row, dispatch `changed`.

### `ptoApp`
- Loads `getContext()`. If `employee` is null and the user is not HR: message "Your user isn't linked to an employee record. Ask HR to set User on your Employee record."
- SLDS tab strip (`slds-tabs_default`): Overview, Apply, Past, Approve (Approve only when `canApprove`, with a count of pending). Renders only the active section.
- On `changed` from a child: reload context and refresh the other sections when they are next shown.

## Changes made during org testing

- Conversion matches an existing absence line item by employee + date + category across all of the employee's timesheets (not only the matched one), so two overlapping timesheets never get the same day twice.
- `LeaveService.submit` does one `upsert` on `Unique_Key__c`, so a DML error index points at the caller's row.
- Approve/reject re-read each record after the Approval Process step and only update what is still Submitted (no double conversion, one "Not in Timesheet" note).
- Approved leave can't change date, category or employee (its line item is already on that day's timesheet); changing hours updates the line item.
- `HolidayLoader` checks `PTO_Admin_All` itself and writes in Queueable batches of 200 rows.
- The Apply tab defaults to PTO-Planned.
- The Employee trigger copies the user's `ManagerId` into `Employee__c.Manager__c`, so in practice both direct-report links agree.
