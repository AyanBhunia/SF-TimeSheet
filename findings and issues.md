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
