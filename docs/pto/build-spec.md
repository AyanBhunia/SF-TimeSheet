# PTO build spec (v2 implementation contracts)

Companion to `pto-technical-plan.md`. This file fixes names, API shapes and UI behaviour so every piece fits together.

Repo facts:
- Source root: `Timesheet/main/default`. Package namespace `dbt`, but source never uses the `dbt__` prefix (except the existing `TimesheetTrigger`, which already does).
- API version 64.0 for every new component.
- Timesheets are weekly, Monday to Sunday (`Start_Date__c` Monday, `End_Date__c` Sunday).
- Look and feel: plain SLDS, industrial, no gimmicks. Use `slds-*` utility classes first; keep custom CSS short. No emoji.

## Removed from v1

Delete from source and from tsorg (destructive deploy; `Deploy-Delta.ps1` doesn't delete):
- `objects/Leave_and_Holiday__c` (object and all fields)
- `triggers/LeaveAndHolidayTrigger`
- `classes/HolidayLoader`
- `flows/PTO_Holiday_Loader`
- `unpackaged/approvalProcesses/Leave_and_Holiday__c.Leave_Approval.approvalProcess` and `unpackaged/workflows/Leave_and_Holiday__c.workflow`
- The matching entries in the three permission sets
- `classes/LeaveService` is renamed to `PtoRequestService`

## Metadata

### Object `PTO_Request__c`
- Label "PTO Request", plural "PTO Requests". Name field: AutoNumber `PTO-{000000}`, label "Request Number", starting number 1.
- `sharingModel` Private, `externalSharingModel` Private, `deploymentStatus` Deployed, `enableReports` true, `enableSearch` false, `enableActivities` false, `enableHistory` false, `enableBulkApi` true, `enableSharing` true, `enableStreamingApi` true. No tab, no layout, no list views.

| Field | Type | Details |
| --- | --- | --- |
| `Employee__c` | Lookup(Employee__c) | required true, deleteConstraint Restrict, relationshipName `PTO_Requests`, relationshipLabel "PTO Requests" |
| `Status__c` | Picklist, restricted | values Submitted (default), Approved, Rejected |
| `Approver__c` | Lookup(User) | deleteConstraint SetNull, relationshipName `PTO_Approvals` |
| `Notes__c` | LongTextArea(2000) | label "Reason", visibleLines 4 |
| `Decision_Notes__c` | LongTextArea(2000) | label "Decision Notes", visibleLines 3 |
| `Decided_By__c` | Lookup(User) | deleteConstraint SetNull, relationshipName `PTO_Decisions` |
| `Decided_On__c` | DateTime | |
| `Start_Date__c` | Summary MIN | summarizedField `Leave_Line_Item__c.Date__c` |
| `End_Date__c` | Summary MAX | summarizedField `Leave_Line_Item__c.Date__c` |
| `Total_Hours__c` | Summary SUM | summarizedField `Leave_Line_Item__c.Duration__c` |
| `Day_Count__c` | Summary COUNT | |
| `Sync_Error_Count__c` | Summary COUNT | filter `Leave_Line_Item__c.Sync_Status__c` equals Error |

### Object `Leave_Line_Item__c`
- Label "Leave Line Item", plural "Leave Line Items". Name field: AutoNumber `LLI-{000000}`, label "Line Number", starting number 1.
- `sharingModel` ControlledByParent, `externalSharingModel` ControlledByParent, `deploymentStatus` Deployed, `enableReports` true, `enableSearch` false, `enableActivities` false, `enableHistory` false, `enableBulkApi` true, `enableStreamingApi` true. No tab, no layout, no list views.

| Field | Type | Details |
| --- | --- | --- |
| `PTO_Request__c` | MasterDetail(PTO_Request__c) | relationshipName `Leave_Line_Items`, relationshipLabel "Leave Line Items", reparentableMasterDetail false, writeRequiresMasterRead false, relationshipOrder 0 |
| `Date__c` | Date | required true |
| `Absence_Category__c` | Picklist, restricted | exactly the timesheet line item values in the same order: On Duty, Sick Leave, Permission, PTO-Planned, PTO-Un Planned, Holiday |
| `Duration__c` | Number(4,2) | label "Duration (Hours)" |
| `Unique_Key__c` | Text(80) | unique true, externalId true, caseSensitive false |
| `Sync_Status__c` | Picklist, restricted | values Waiting for timesheet (default), On timesheet, Error. Label "Timesheet Status" |
| `Sync_Error__c` | Text(255) | label "Timesheet Error" |
| `Timesheet_Line_Item__c` | Lookup(Timesheet_Line_Item__c) | deleteConstraint SetNull, relationshipName `Leave_Line_Items` |

Required fields (`Employee__c`, `Date__c`) and the master-detail field must NOT appear in permission set fieldPermissions. The roll-ups are listed read-only so reports and list views can show them.

### Custom metadata `Timesheet_Default_Value__mdt`
No change from v1: `Max_PTO_Planned_Hours__c`, `Max_PTO_Unplanned_Hours__c`, `Max_Sick_Leave_Hours__c`, `Max_Permission_Hours__c`, `Max_On_Duty_Hours__c`, `Max_Holiday_Hours__c`, all 8.0 in `Default_Values`.

### Validation rules on `Timesheet_Line_Item__c`
No change from v1 (`Duration` and `Eight_hour_limit_for_out_of_office` read the metadata fields).

### Custom permissions
No change: `PTO_Approve_Team` ("PTO: Approve Team Leave") and `PTO_Admin_All` ("PTO: Administer All Leave").

### Tab and app
No change: Lightning component tab `PTO` (`ptoApp`, motif `Custom20: Airplane`), on `Timesheet.app-meta.xml` after `Timesheet__c`.

### Permission sets
| | Timesheet_User | TimeSheet_Manager | Timesheet_HR_Admin |
| --- | --- | --- | --- |
| `PTO_Request__c` | R C E | R C E | R C E D, View All, Modify All |
| Request `Notes__c` | read+edit | read+edit | read+edit |
| Request `Status__c`, `Approver__c`, `Decision_Notes__c`, `Decided_By__c`, `Decided_On__c` | read | read | read+edit |
| `Leave_Line_Item__c` | R C | R C | R C E D, View All, Modify All |
| Line `Absence_Category__c`, `Duration__c` | read+edit | read+edit | read+edit |
| Line `Unique_Key__c`, `Sync_Status__c`, `Sync_Error__c`, `Timesheet_Line_Item__c` | read | read | read |
| Request roll-ups `Start_Date__c`, `End_Date__c`, `Day_Count__c`, `Total_Hours__c`, `Sync_Error_Count__c` | read | read | read |
| Custom permission | — | PTO_Approve_Team | PTO_Admin_All |
| Tab PTO | Visible | Visible | Visible |
| Classes | PtoController | PtoController | PtoController |

## Triggers

`PtoRequestTrigger` on `PTO_Request__c` (before insert, before update, after update) and `LeaveLineItemTrigger` on `Leave_Line_Item__c` (before insert, before update, before delete). Both delegate to `PtoRequestService`:

| Event | Behaviour |
| --- | --- |
| Request before insert/update | Status defaults to Submitted. `Approver__c` from `Employee__r.Manager__c` on insert when blank. Status only moves Submitted to Approved or Rejected; `Employee__c` can't change. A decision made outside the PTO tab (standard approval screen, data load) gets `Decided_By__c`, `Decided_On__c` and a `Decision_Notes__c` line with the approver's comment stamped here |
| Request after update | Status → Approved: `LeaveToLineItem.convertRequests(ids)`. Status → Rejected: set `Unique_Key__c` = null on its lines |
| Line before insert | Load parent requests (1 query). Refuse a line whose request isn't Submitted. Stamp `Unique_Key__c` = `LeaveValidator.key(employeeId, date, category)`. Default `Sync_Status__c`. Run `LeaveValidator.validate` and `addError` per row |
| Line before update | `Date__c`, `Absence_Category__c`, `Duration__c` can't change: "Leave days can't be changed after submitting." Sync fields and the key may change |
| Line before delete | Allowed only when the request is Rejected, or the user has `PTO_Admin_All` |

## Apex contracts (`PtoController`, all `@AuraEnabled`, imperative calls, no cacheable)

Dates cross the wire as `YYYY-MM-DD` strings, in fields named `leaveDate`, `startDate`, `endDate` (`date` is reserved in Apex); the LWCs copy `leaveDate` to `date` on receipt. Errors are thrown as `AuraHandledException` with a readable message when called from Lightning, and as `PtoController.PtoException` from any other context.

Reads that must see records the user doesn't own run through `PtoData` (without sharing). `PtoController` checks access before every call.

Shared row shapes:
```
RequestRow = { id, name, employeeId, employeeName, startDate, endDate, dayCount, totalHours,
               status, displayStatus, notes, decisionNotes, approverName, decidedByName, decidedOn, submittedOn }
LineRow    = { id, leaveDate, category, hours, syncStatus, syncError }
```
`displayStatus` is Submitted, Approved, Rejected, or "Approved, sync error" (Approved with `Sync_Error_Count__c` > 0).

1. `getContext()` returns
```
{
  employee: { id, name, managerId, managerName, hasManager, available } | null,   // current user's Employee__c; available = hours
  isManager, isHrAdmin, canApprove,           // canApprove = isManager || isHrAdmin
  employees: [ { id, name, managerName, hasManager } ],  // apply-for picker; manager: direct reports; HR: all active employees; excludes self
  categories: [ { value, label, maxHours } ], // leave categories (no Holiday), in picklist order
  dailyMax,                                   // Maximum_Working_Hrs_Per_Day__c
  today,                                      // 'YYYY-MM-DD'
  pendingCount                                // requests waiting for this approver
}
```
2. `getDayRecords(Id employeeId, Date startDate, Date endDate)` (max 62 days) returns
```
{
  employee:  { id, name, managerName, hasManager, available },
  leaves:    [ { id, leaveDate, category, hours, status, requestId, requestName } ],  // lines on Submitted/Approved requests only
  lineItems: [ { id, leaveDate, type, category, hours } ]                           // timesheet line items, Attendance and Absence
}
```
3. `submitLeave(Id employeeId, String rowsJson, String notes)`. `rowsJson` = `[ { date:'YYYY-MM-DD', category, hours } ]`; notes ≤ 2,000 characters. Returns
```
{ success, rowErrors: [ '' | message ] (same order as input), warnings: [ message ], requestId, requestName, dayCount }
```
4. `getPast(Id employeeId, Integer offsetRows)`; employeeId null = current user. Returns
```
{ rows: [ RequestRow ], hasMore, offset }
```
25 requests per page (the query fetches 26), ordered by `Start_Date__c DESC, CreatedDate DESC`.
5. `getRequestLines(Id requestId)` returns `{ request: RequestRow, lines: [ LineRow ] }`, lines by date. Allowed for the request's own employee, their manager (two-link rule), or HR.
6. `getOverview(Id employeeId, Integer year)` returns
```
{ available, takenHours, pendingHours, pendingRequests, nextLeaveDate, nextLeaveCount,
  byCategory: [ { category, approved, submitted } ] }
```
Sums leave lines whose request is Submitted or Approved, within the year.
7. `getTeamWeek(Date weekStart)` (manager: direct reports; HR: all active employees, max 200) returns
```
{ weekStart, days: [7 x 'YYYY-MM-DD'], rows: [ { employeeId, name, hours: [7 numbers] } ] }
```
8. `getPendingApprovals()` returns `[ RequestRow ]`, Submitted only, sorted by `Start_Date__c` ascending. Nobody sees their own request here.
9. `approveRequests(List<Id> requestIds)` and `rejectRequests(List<Id> requestIds, String reason)` return `{ processed, errors: [ message ], syncErrors: [ message ] }`. `syncErrors` lists lines of approved requests that couldn't go onto their timesheet (the request is still approved).
10. `retrySync(Id requestId)` (HR only) returns `{ processed, errors, syncErrors }`.

## LWC

All components: API 64.0, `isExposed` false except `ptoApp` (exposed, target `lightning__Tab`). Import Apex as `@salesforce/apex/PtoController.<method>`. Toasts via `lightning/platformShowToastEvent`. Show `lightning-spinner` while loading. Error text from `error.body.message`.

### `ptoTable` (shared table, renders only, parent owns data)
API:
- `@api columns` = `[ { fieldName, label, type: 'text'|'date'|'number'|'picklist'|'status', editable, sortable, options: [ {label, value} ], align: 'left'|'right', width } ]`
- `@api rows` = `[ { key, locked, error, info, ...values } ]`. `locked` greys the row and disables inputs; `error` prints red text under the row; `info` prints blue text under the row.
- `@api rowActions` = `[ { name, label, variant } ]` (variant is a `lightning-button` variant). Buttons render in the last column for unlocked rows only.
- `@api sortedBy`, `@api sortedDirection` ('asc' | 'desc'); `@api emptyMessage`.
- **New:** `@api selectable` (boolean), `@api selectedKey`. When selectable, rows get `tabindex="0"`, `aria-selected`, a pointer cursor and the `slds-is-selected` class on the selected one. Click or Enter fires `rowselect`.
- Events: `cellchange` detail `{ rowKey, fieldName, value }`; `rowaction` detail `{ rowKey, action }`; `sort` detail `{ fieldName, direction }` (clicking a sortable header toggles direction); `rowselect` detail `{ rowKey }`.
- Templates cannot index objects, so compute a `viewRows` getter with `cells` per row (flags `isText`, `isDate`, `isNumber`, `isPicklist`, `isStatus`, `isEditable`).
- Editable cells: `lightning-input` (type date / number with step 0.25 / text), `variant="label-hidden"`. Picklist cells use a native SLDS `select` so the dropdown isn't clipped by the scrolling table; `renderedCallback` keeps its value in sync. Fire `cellchange` on change.
- `status` cells render a pill (`slds-badge`):
    - warning: Submitted, Waiting for timesheet
    - success: Approved, On timesheet
    - error: Rejected, Error, "Approved, sync error"
- Table: `slds-table slds-table_bordered slds-table_cell-buffer slds-table_fixed-layout` inside an `overflow-x:auto` wrapper. Locked rows: grey background. Error rows: light warning background.

### `ptoConfirmModal` (extends `LightningModal`)
- `@api mode` ('approve' | 'reject'), `@api summary` (string like "PTO-000123 · Priya Natarajan · 2026-10-12 to 2026-10-16 · 5 days · 40 h").
- Approve: confirm text "Approves all days in this request. Days whose week has a timesheet are added to it now." Buttons Cancel / Approve.
- Reject: required textarea "Reason (shown to the employee)"; the Reject button shows an inline error if it's blank.
- Returns `this.close({ confirmed: true, reason })` or `this.close({ confirmed: false })`.

### `ptoRequestDetail` (new; the right-hand pane)
- `@api requestId` (setter reloads), `@api mode` ('past' | 'approve'), `@api canRetry` (HR).
- Loads `getRequestLines(requestId)`. With no `requestId`: empty state "Select a request to see its days."
- Header (`slds-box`):
    - first line: request number, status pill (`displayStatus`)
    - second line: employee, "12 Oct – 16 Oct 2026", "5 days · 40 h"
    - then: Approver (or "No manager, waiting for HR"), Reason, Decision notes (when present), Submitted on.
- Lines: `ptoTable` with columns Date, Category, Hours (right), Timesheet (status pill from `syncStatus`), Error (`syncError`, only when any line has one).
- Approve mode: Approve (brand) and Reject (destructive) buttons at the top right. Each opens `ptoConfirmModal`, then calls `approveRequests([id])` / `rejectRequests([id], reason)`. It toasts (warning toast listing `syncErrors` if any) and dispatches `decided` (detail `{ requestId }`).
- Past mode with `canRetry` and `Sync_Error_Count__c` > 0: a "Retry timesheet sync" button calls `retrySync`, then reloads and dispatches `decided`.
- `@api refresh()` reloads.

### `ptoPast`
- `@api employeeId`, `@api context`, `@api canRetry`. Loads `getPast(employeeId, offset)`.
- Managers and HR (when `context.employees` isn't empty) get an Employee combobox above the list ("Me" plus `context.employees`), so they can open a direct report's (or, for HR, anyone's) requests. This is how HR reaches another employee's failed day to retry it.
- Layout: `slds-grid slds-wrap slds-gutters_small`. List column `slds-size_1-of-1 slds-medium-size_7-of-12`, detail column `slds-size_1-of-1 slds-medium-size_5-of-12`.
- List: `ptoTable` selectable. Columns: Request, From, To, Days (right), Hours (right), Status (pill from `displayStatus`). Previous / Next buttons, "Page N", "Showing a to b".
- The first row is selected after each load. Detail: `ptoRequestDetail mode="past"`, `can-retry` from context `isHrAdmin`.
- `@api refresh()` reloads page 1. On `decided` from the detail: reload the current page, keep the selection.
- Empty state: "No leave requests yet."

### `ptoApprove`
- Loads `getPendingApprovals()`. Same split layout as Past.
- List: `ptoTable` selectable and sortable on the client. Columns: Request, Employee, From, To, Days, Hours, Submitted. No row action buttons.
- Detail: `ptoRequestDetail mode="approve"`.
- On `decided`: reload, select the request that took the decided one's place (or the last one), dispatch `changed` (bubbles false).
- Empty state: "No leave requests are waiting for your approval."

### `ptoOverview`
- `@api context` (from `getContext`), `@api employeeId`.
- Four tiles:
    - Available (h), caption "Balance minus pending"
    - Taken this year, caption "Approved leave"
    - Pending (h), caption "In N requests"
    - Next leave (date + days)
- Bar chart (Chart.js from static resource `jsChart`, horizontal bars, stacked Approved + Submitted) of hours by category for the current year.
- Managers and HR: heatmap of the team week using Chart.js matrix (static resource `jsChartMatrix`, load after `jsChart`). Rows = employees, columns = Mon..Sun, cell colour by hours (0, ≤2, ≤4, <8, ≥8). Previous / Next week buttons. Uses `getTeamWeek(weekStart)`, starting with Monday of the current week.
- `@api refresh()` reloads.

### `ptoApply`
- `@api context`. Employee picker for managers and HR (`context.employees` plus "Me"), read-only name for users.
- Inputs: start date, end date, category (combobox of `context.categories`, default PTO-Planned), hours per day (max = category max), "Include Saturday and Sunday" checkbox, and a **Reason** textarea (`lightning-textarea`, max 2,000) under the table.
- Table (`ptoTable`) starts with one empty row. Columns: Date, Day, Category, Hours, and a Remove action. No Notes column.
- Changing dates fills one row per day (weekdays only unless the checkbox is ticked) and loads `getDayRecords` for the range. Lines on Submitted/Approved requests and absence timesheet line items appear as locked rows. The locked row's info line reads "On PTO-000123, Approved" or "Already on the timesheet".
- Client checks per row, same as the server:
    - hours > 0 and ≤ category max
    - no line on a Submitted/Approved request and no absence line item with the same date + category
    - the same date + category isn't entered twice
    - day total (line items that day + pending leave lines not yet on a timesheet + the new rows) ≤ `dailyMax`
- Buttons: Add row, Clear, Review.
- Review shows:
    - "One request", days, total hours, balance after
    - a warning box if over balance
    - a warning if the employee has no manager ("This employee has no manager, so the request will stay pending until HR approves it.")
    - "You won't be able to edit this request after submitting."
    - Back / Submit
- Submit calls `submitLeave(employeeId, rowsJson, notes)`. On success: toast "PTO-000123 submitted, 5 days", reset to one empty row and blank reason, dispatch `changed`.

### `ptoApp`
- Loads `getContext()`. If `employee` is null and the user is not HR: message "Your user isn't linked to an employee record. Ask HR to set User on your Employee record."
- SLDS tab strip (`slds-tabs_default`): Overview, Apply, Past, Approve. Approve only shows when `canApprove`, with the count of pending requests. Renders only the active section.
- On `changed` from a child: reload context and refresh the other sections when they are next shown.

## Unpackaged Approval Process
- `unpackaged/approvalProcesses/PTO_Request__c.Leave_Approval.approvalProcess`.
    - Entry criteria `Status__c` equals Submitted.
    - Single step, approver = related user `Approver__c`.
    - Final approval action: field update `Set_Status_Approved`. Final rejection action: `Set_Status_Rejected`.
    - Record lock released on both.
- `unpackaged/workflows/PTO_Request__c.workflow`: field updates `Set_Status_Approved` (Status__c = Approved) and `Set_Status_Rejected` (Status__c = Rejected).
- `unpackaged/package.xml` lists `ApprovalProcess PTO_Request__c.Leave_Approval` and `WorkflowFieldUpdate PTO_Request__c.Set_Status_*`. Update `README.md`.

## Notes carried over from v1 org testing (still apply)

- Conversion matches an existing absence line item by employee + date + category across all of the employee's timesheets (not only the matched one), so two overlapping timesheets never get the same day twice.
- Approve/reject re-read each request after the Approval Process step and only update what is still Submitted, so there's no double conversion.
- The Apply tab defaults to PTO-Planned.
- The Employee trigger copies the user's `ManagerId` into `Employee__c.Manager__c`, so in practice both direct-report links agree.
- Custom permissions are checked with and without the `dbt__` prefix (`PtoController.hasPermission`).

## Changes made during the v2 build

- Past has an Employee picker for managers and HR (see `ptoPast`); without it HR could not reach another employee's sync error to retry it.
- Decisions made in the standard approval screen are stamped by the request trigger (who, when, approver's comment), so Past shows them like tab decisions. `PtoRequestService` sets a flag while the tab decides, so a tab decision writes one note, not two.
- `DemoDataControllerTest` asserted exactly 2 queries for `createDemoTimesheets`; the PTO hook in `TimesheetTrigger` (since v1) adds the approved-leave lookup, so it now expects 3 and says why.
- The approval process file was renamed to `PTO_Request__c.Leave_Approval`; its rejection field update is `PTO_Set_Rejected`.
- Deleting v1 from tsorg: Metadata API deletes only the latest flow version, so the older `PTO_Holiday_Loader` versions were deleted through the Tooling API; the object, trigger and classes went in the same deploy as v2 with `--post-destructive-changes` (pre-destructive fails because the org's old classes still reference the object).
