# Findings and Issues

This file holds all the potential issues found in reviews and testing that we can tackle later.
Add new items at the end with the date found, and remove them once fixed.

---

## 1. PTO request can be created for another employee outside the PTO tab

- **Severity:** Medium (security)
- **Found:** 2026-10-13, security review of v2.26 (`6baacd4`) to v2.27
- **Where:** `PtoRequestService.beforeRequestSave` (called by `PtoRequestTrigger`)

**Problem**
`PtoController` only lets a user file leave for themselves, for a direct report (manager), or for anyone (HR).
The request trigger does not repeat that check. `PTO_Request__c.Employee__c` is a required lookup (no field-level
permission), and Timesheet User and TimeSheet Manager both have Create on `PTO_Request__c`. Anyone using the
standard New button or the API can therefore create a request for any Employee record they can read.
TimeSheet Manager has View All on `Employee__c`, so a manager can file leave for any employee in the org, not only
their direct reports. The request is routed to that employee's real manager; if approved, the leave is written to
that employee's timesheet.

Worked out from the configuration; not yet reproduced with a restricted test user.

**Proposed fix**
On insert in `beforeRequestSave`, apply the same rule as `PtoController.Access.requireEmployee`: allow the request
only when the employee is the running user's own, the user has `PTO_Admin_All`, or the user has `PTO_Approve_Team`
and the employee is a direct report (`Employee__c.Manager__c` and the employee user's `ManagerId` are both the
running user). Add Apex tests for each case.

---

## 2. Days can be added to a PTO request after it is submitted

- **Severity:** Low
- **Found:** 2026-10-13, security review of v2.26 (`6baacd4`) to v2.27
- **Where:** `PtoRequestService.beforeLineInsert` (called by `LeaveLineItemTrigger`)

**Problem**
Timesheet User has Create on `Leave_Line_Item__c`, and the request owner can edit their own request. An employee can
insert new leave days directly (API or UI) into a request that is already waiting for approval. `LeaveValidator`
still runs (category limits, duplicate days), but the approver may already have reviewed a shorter request.

**Proposed fix**
Only allow new lines while the request is being submitted from the PTO tab (for example a static flag set in
`PtoRequestService.submit`), or when the running user has `PTO_Admin_All`.

---

Items 3 to 12 come from the app-wide investigation, the security/code review and the end-to-end browser test on tsorg
for branch `little-fixes` (2026-10-22 to 2026-10-23). Everything fixed on that branch is described in
`docs/manual-test-notes-little-fixes.md`; only what is still open is listed here.

## 3. Leave rows written by the PTO tab can be edited or deleted in the weekly grid

- **Severity:** Medium
- **Found:** 2026-10-22, app investigation (timer + PTO)
- **Where:** `lwc/testLineItem` (weekly grid) and `WeeklyTimesheetController.saveWeek`

**Problem**
When leave is approved, `LeaveToLineItem` writes an absence row into the timesheet and links the leave day to it.
The grid shows that row like any other, so the employee can change its hours or delete it. Nothing updates the PTO
side: after a delete the leave day still says "On timesheet" and keeps pointing to a row that no longer exists, and
after an edit the timesheet and the PTO request show different hours.

Example: Eli has 8 h approved PTO on Tuesday. In the grid he removes the Tuesday absence row and saves. The timesheet
now has no leave on Tuesday, but the PTO tab still lists Tuesday as "On timesheet".

**Proposed fix**
Show PTO-synced rows read-only in the grid (the leave link is on `Leave_Line_Item__c.Timesheet_Line_Item__c`), and
refuse edits/deletes of those rows in `saveWeek` unless the user has `PTO_Admin_All`. Alternatively, on delete, set
the leave day back to "Error" with "Row removed from the timesheet" so Retry sync can put it back.

---

## 4. "Available" leave balance is meaningless for employees without accrual

- **Severity:** Low (display)
- **Found:** 2026-10-23, end-to-end test on tsorg
- **Where:** PTO tab header (`PtoController` balance, `PtoData.pendingLeaveHours`)

**Problem**
For an employee with no Accrual Start Date there is nothing to accrue, so the balance is 0 minus all waiting and
approved leave. Eli on tsorg shows "-156 h available". The number is arithmetically right, and leave is still allowed
(no warning is shown without accrual), but the large negative number alarms users.

**Proposed fix**
When accrual is not configured, hide the number or show "No leave balance set up" instead.

---

## 5. Install script sends the installer's details to a fixed external address

- **Severity:** Medium (AppExchange security review / privacy)
- **Found:** 2026-10-22, security review
- **Where:** `PostInstallScript.cls:57-92`

**Problem**
After install the script emails the installing user's name, email and the org id to
`srini.chappidi@digitalbiz.tech` (hard-coded at line 59). The subscriber is not told. The AppExchange security review
treats sending subscriber data out of the org without disclosure as a finding.

**Proposed fix**
Either remove it, or disclose it in the listing/install instructions. Prefer the License Management App / Subscriber
Support Console, which already tells the publisher about installs.

---

## 6. Some system fields can be edited by users directly

- **Severity:** Low
- **Found:** 2026-10-22, security review
- **Where:** `Timesheet_Line_Item__c` field permissions in `Timesheet_User` / `TimeSheet_Manager`

**Problem**
`Hours_Limit_Exceeded__c`, `Billable_Amount__c` and `Timer_Data__c` are editable. Users only work through the LWC, but
through the API or a list view a user can, for example, change `Billable_Amount__c` on their own rows or clear
`Timer_Data__c`.
Accepted already: notifications sent to another user through `Timer_Data__c` (decided 2026-10-22; users only use the LWC).

**Proposed fix**
Make these fields read-only in the permission sets. Apex already writes them in system context where needed. Check
the grid and timer still save after the change.

---

## 7. Grid upsert checks "create" access for rows it also updates

- **Severity:** Low
- **Found:** 2026-10-22, security review
- **Where:** `WeeklyTimesheetController.cls:107` and `:237`

**Problem**
`Security.stripInaccessible(AccessType.CREATABLE, ...)` is used before an `upsert` that also updates existing rows.
A field that is creatable but not updatable for the user would still be written on update.
With today's permission sets the two lists are the same, so there is no impact now.

**Proposed fix**
Split the list into new rows (`CREATABLE`) and existing rows (`UPDATABLE`) and strip each with the matching check.

---

## 8. Small time window where the grid can still overwrite a change made elsewhere

- **Severity:** Low
- **Found:** 2026-10-22, code review of `saveWeek`
- **Where:** `WeeklyTimesheetController.saveWeek`

**Problem**
`saveWeek` now compares each row's hours with the hours the grid loaded and refuses if they changed. The check reads
the rows without a lock, so a timer save that commits in the few milliseconds between that check and the grid's
write is still overwritten.
`FOR UPDATE` was considered and left out because locking line items before the timesheet risks the lock-order
problems fixed in `startTimer`.

**Proposed fix**
Only if it is ever seen in practice: lock the parent timesheet first (same order as approval and `startTimer`), then
read the rows.

---

## 9. PDF table leaves out absence/PTO hours

- **Severity:** Low (decided 2026-10-22: leave as is for now)
- **Found:** 2026-10-22, app investigation
- **Where:** `lwc/createPDF/createPDF.js`

**Problem**
The PDF's table lists only project rows, but its total includes absence. A week with 32 h of work and 8 h of PTO
shows rows adding up to 32 h and a total of 40 h.

**Proposed fix**
Add the absence rows (category instead of project) to the table, or show "of which absence: X h" under the total.

---

## 10. Bulk PTO approval may fail when the approver cannot see every timesheet

- **Severity:** Low (needs verification)
- **Found:** 2026-10-22, app investigation (agent report, not reproduced)
- **Where:** `PtoController.approveRequests` (line 513) -> `PtoRequestService.decide` -> `LeaveToLineItem`

**Problem**
Reported: approving several requests at once looks up each employee's timesheet. If the approver cannot see one of
them (sharing), the lookup returns nothing and a null value may be used. On tsorg, approving one request at a time as
Mia worked. Bulk approval across employees with different sharing was not tested.

**Proposed fix**
Reproduce with a manager who approves requests of two employees, one of whose timesheets is not shared with them.
If it fails, treat a missing timesheet as "no timesheet for this week" (the leave day goes to "Waiting for timesheet").

---

## 11. Housekeeping

- **Severity:** Low
- **Found:** 2026-10-22, app investigation

- Validation rule `Absence_Category_Validation` is never true any more (dead).
- Two error messages hard-code "8" hours instead of using the configured limit.
- Old and draft flow versions are still in the package; old manifests (`manifest/*.xml`) list removed components.
- Dashboard data cache is never cleared after a save (charts may lag until reload).
- Weekly grid template has duplicate `key` values and inputs without labels (accessibility).
- No Jest tests for the LWCs; no dedicated test classes for the PTO helper classes (covered only through other tests).

---

## 12. Test data on tsorg is inconsistent

- **Severity:** Low (test org only)
- **Found:** 2026-10-23, end-to-end test on tsorg

**Problem**
- Some employees have two timesheets for overlapping weeks, so a day's total counts hours from both and "Copy
  previous timesheet" is refused for going over 24 h.
- An old timesheet row has no project, so copying that week is refused ("project is required").

The app handled both correctly, but they make manual tests confusing.

**Proposed fix**
Delete the duplicate timesheets and the row without a project on tsorg, or regenerate demo data.
