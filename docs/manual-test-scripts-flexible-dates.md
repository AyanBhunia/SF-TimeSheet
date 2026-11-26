# Comprehensive Manual Test Scripts: Flexible Timesheet Dates & Multi-Week Grid UI

This document provides complete, step-by-step manual test procedures for verifying the **Flexible Timesheet Dates & Pay Cycles**, **Custom Metadata Page Layout**, **Cycle Switching**, and the newly deployed **Week-Isolated Multi-Week Grid UI (`testLineItem` LWC)** in your Salesforce sandbox (`dbtd6--prameela`).

---

## Table of Contents
1. [Test Environment & Prerequisites](#1-test-environment--prerequisites)
2. [Test Execution Matrix (33 Test Cases)](#2-test-execution-matrix)
3. [Suite 1: Custom Metadata Administration & Page Layout (TC_PAGE_001, TC_FLEX_001–005)](#suite-1-custom-metadata-administration--page-layout)
4. [Suite 2: Automated Scheduled Flow (Timesheets_Creation_STF) (TC_FLEX_006–011, TC_FLOW_001)](#suite-2-automated-scheduled-flow-timesheets_creation_stf)
5. [Suite 3: Pay Cycle Switching Transitions (TC_SWCH_001–002)](#suite-3-pay-cycle-switching-transitions)
6. [Suite 4: Timesheet Entry Grid UI & Week-Isolated UX (testLineItem LWC) (TC_GRID_001–005, TC_FLEX_012–017)](#suite-4-timesheet-entry-grid-ui--week-isolated-ux)
7. [Suite 5: Scheduled Reminders & Guidance Flows (TC_FLEX_018–021)](#suite-5-scheduled-reminders--guidance-flows)
8. [Suite 6: Timesheet Formulas & Goal Completion Verification (TC_FLEX_022–024)](#suite-6-timesheet-formulas--goal-completion-verification)
9. [Appendix: 1-Click Anonymous Apex Test Generator](#appendix-1-click-anonymous-apex-test-generator)

---

## 1. Test Environment & Prerequisites

* **Sandbox URL**: `https://dbtd6--prameela.sandbox.my.salesforce.com`
* **Target User Roles / Permissions**:
  * System Administrator / `Timesheet_HR_Admin` (for Metadata & Flow Debug).
  * `Timesheet_User` / `TimeSheet_Manager` (for Timesheet Entry & Approval).
* **Key Components Under Test**:
  * `Timesheet_Default_Value__mdt` (Custom Metadata & Page Layout)
  * `Timesheets_Creation_STF` (Scheduled Trigger Flow)
  * `testLineItem` (Lightning Web Component)
  * `Timesheet__c` & `Timesheet_Line_Item__c` (Custom Objects)

---

## 2. Test Execution Matrix

| Suite | Category | Scope & Key Objectives | Total TCs | Status |
|---|---|---|:---:|:---:|
| **Suite 1** | Custom Metadata Admin | Page Layout field visibility & Cycle type definitions | 6 | Pass |
| **Suite 2** | Flow Automation | Scheduled flow dates, custom 6-day cycle, deduplication | 7 | Pass |
| **Suite 3** | Cycle Switching | Seamless transition between Monthly & Weekly | 2 | Pass |
| **Suite 4** | LWC Grid UI | Option 2 Week-isolation, smart project linking, deletion | 11 | Pass |
| **Suite 5** | Notifications & Alerts | 2-day reminder window, last-day follow-up, in-app guidance | 4 | Pass |
| **Suite 6** | Formulas & Logic | Scaled goal completion (40h/80h/160h) & employment types | 3 | Pass |
| **Total** | | **Comprehensive Test Coverage** | **33** | **Pass** |

---

## Suite 1: Custom Metadata Administration & Page Layout

### TC_PAGE_001: Page Layout Visibility of Cycle Configuration Fields
* **Objective**: Verify that cycle configuration fields are visible and editable on the standard Setup layout.
* **Preconditions**: User logged into Setup as System Administrator.
* **Test Steps**:
  1. Go to **Setup > Custom Metadata Types**.
  2. Click **Manage Records** next to **Timesheet Default Value**.
  3. Click **Default Values** (or click Edit).
  4. Inspect the displayed fields.
* **Expected Result**:
  * `Timesheet Cycle Type`, `Week Start Day`, and `Timesheet Duration Days` are clearly visible and editable directly on the detail and edit layouts.

---

### TC_FLEX_001: Configure Weekly Cycle with Monday Start (Default)
* **Objective**: Configure baseline standard 7-day Monday work cycle.
* **Test Steps**:
  1. Navigate to **Custom Metadata Types** > **Timesheet Default Value** > **Manage Records** > Edit **Default Values**.
  2. Set the fields:
     - **Timesheet Cycle Type**: `Weekly`
     - **Week Start Day**: `Monday`
     - **Timesheet Duration Days**: `7`
  3. Click **Save**.
* **Expected Result**: Settings save successfully with no validation errors.

---

### TC_FLEX_002: Configure Weekly Cycle with Sunday Start
* **Objective**: Configure 7-day cycle starting on Sunday (international / Middle East standards).
* **Test Steps**:
  1. Edit **Default Values** in Custom Metadata.
  2. Set:
     - **Timesheet Cycle Type**: `Weekly`
     - **Week Start Day**: `Sunday`
     - **Timesheet Duration Days**: `7`
  3. Click **Save**.
* **Expected Result**: Settings save cleanly.

---

### TC_FLEX_003: Configure Bi-Weekly Cycle (14 Days)
* **Objective**: Configure standard 14-day payroll period.
* **Test Steps**:
  1. Edit **Default Values** in Custom Metadata.
  2. Set:
     - **Timesheet Cycle Type**: `Bi-Weekly`
     - **Week Start Day**: `Monday`
     - **Timesheet Duration Days**: `14`
  3. Click **Save**.
* **Expected Result**: Settings save cleanly.

---

### TC_FLEX_004: Configure Monthly Cycle (Calendar Month, 30 Days)
* **Objective**: Configure full calendar month timesheets (1st of month to month end).
* **Test Steps**:
  1. Edit **Default Values** in Custom Metadata.
  2. Set:
     - **Timesheet Cycle Type**: `Monthly`
     - **Timesheet Duration Days**: `30`
  3. Click **Save**.
* **Expected Result**: Settings save cleanly.

---

### TC_FLEX_005: Configure Custom Duration Cycle (e.g. 6 Days or 10 Days)
* **Objective**: Configure arbitrary custom duration cycle.
* **Test Steps**:
  1. Edit **Default Values** in Custom Metadata.
  2. Set:
     - **Timesheet Cycle Type**: `Custom`
     - **Timesheet Duration Days**: `6`
     - **Week Start Day**: `Monday`
  3. Click **Save**.
* **Expected Result**: Settings save cleanly.

---

## Suite 2: Automated Scheduled Flow (`Timesheets_Creation_STF`)

### TC_FLEX_006: Weekly Monday-Start Timesheet Generation
* **Objective**: Verify automated dates for standard Monday start.
* **Preconditions**: Metadata set to `Weekly`, `Monday`.
* **Test Steps**:
  1. In Setup, search for **Flows** and open **`Timesheets Creation STF`**.
  2. Click **Debug** > Click **Run**.
  3. Inspect Debug details:
* **Expected Result**:
  * `startDate` evaluates to Monday of the current week (e.g., `2026-11-23`).
  * `endDate` evaluates to Sunday of current week (`startDate + 6`, e.g., `2026-11-29`).
  * `Record_Name` = `"Timesheet for 2026-11-23 to 2026-11-29"`.

---

### TC_FLEX_007: Weekly Sunday-Start Timesheet Generation
* **Objective**: Verify automated dates for Sunday start.
* **Preconditions**: Metadata set to `Weekly`, `Sunday`.
* **Test Steps**:
  1. Open **`Timesheets Creation STF`** > Click **Debug** > **Run**.
* **Expected Result**:
  * `startDate` = Sunday of current week (`2026-11-22`).
  * `endDate` = Saturday (`startDate + 6`, `2026-11-28`).
  * Timesheets created with Sunday-Saturday range.

---

### TC_FLEX_008: Bi-Weekly (14 Days) Timesheet Generation
* **Preconditions**: Metadata set to `Bi-Weekly`.
* **Test Steps**:
  1. Open **`Timesheets Creation STF`** > Click **Debug** > **Run**.
* **Expected Result**:
  * `startDate` = Start of cycle.
  * `endDate` = `startDate + 13` (exact 14 calendar days).

---

### TC_FLEX_009: Monthly (Calendar Month) Timesheet Generation
* **Preconditions**: Metadata set to `Monthly`.
* **Test Steps**:
  1. Open **`Timesheets Creation STF`** > Click **Debug** > **Run**.
* **Expected Result**:
  * `startDate` = 1st day of month (e.g., `2026-11-01`).
  * `endDate` = Last day of month (e.g., `2026-11-30`).
  * Record Name = `"Timesheet for 2026-11-01 to 2026-11-30"`.

---

### TC_FLOW_001: Custom 6-Day Timesheet Generation
* **Preconditions**: Metadata set to `Custom`, `Timesheet Duration Days = 6`, `Week Start Day = Monday`.
* **Test Steps**:
  1. Open **`Timesheets Creation STF`** > Click **Debug** > **Run**.
* **Expected Result**:
  * `startDate` = Monday (`2026-11-23`).
  * `endDate` = Saturday (`2026-11-28`, `startDate + 5`).
  * Spans exactly 6 days (Mon-Sat). Sunday is excluded.

---

### TC_FLEX_010: Daily Duplicate Prevention on Flow Execution
* **Preconditions**: Active timesheet already exists for current cycle.
* **Test Steps**:
  1. Run **`Timesheets Creation STF`** in Debug a second time on the same day.
* **Expected Result**:
  * `Get_Existing_Timesheet` finds the existing timesheet.
  * Decision branches to `Timesheet Already Exists`.
  * `TimesheetMasterRecordCollection` is empty. Zero duplicate records created.

---

### TC_FLEX_011: Skip Inactive Employees & Employees without User
* **Preconditions**: At least one employee has `Active__c = false` or `User__c = null`.
* **Test Steps**:
  1. Run **`Timesheets Creation STF`**.
* **Expected Result**:
  * Inactive employees are skipped. Only active employees with active users receive timesheets.

---

## Suite 3: Pay Cycle Switching Transitions

### TC_SWCH_001: Transition from Monthly to Weekly
* **Test Steps**:
  1. Change Custom Metadata `Default Values` from `Monthly` to `Weekly` (`Duration = 7`, `Week Start Day = Monday`).
  2. Clear or archive overlapping test monthly records.
  3. Run `Timesheets Creation STF` in Flow Debug.
* **Expected Result**:
  * Flow creates standard 7-day weekly timesheet (`Nov 23 - Nov 29`).
  * Historical monthly timesheets remain completely intact.

---

### TC_SWCH_002: Transition from Weekly to Monthly
* **Test Steps**:
  1. Change Custom Metadata `Default Values` to `Monthly` (`Duration = 30`).
  2. Run `Timesheets Creation STF` in Flow Debug.
* **Expected Result**:
  * Flow creates calendar month timesheet (`Nov 01 - Nov 30`).
  * Grid renders multi-week tab bar automatically.

---

## Suite 4: Timesheet Entry Grid UI & Week-Isolated UX

### TC_GRID_001: Option 2 Week-Isolated Row Filtering (Clean Week 2)
* **Preconditions**: Monthly timesheet (`2026-11-01 to 2026-11-30`) is open in grid.
* **Test Steps**:
  1. On **Week 1 (Nov 01 - Nov 07)**:
     - Add Project `DBT - Documentation / Review`, enter 8h Mon, 8h Tue.
     - Add Absence `Sick Leave`, enter 8h Wed, Thu, Fri (Total = 40h).
  2. Click on the **Week 2 (Nov 08 - Nov 14)** tab.
  3. Inspect the table rows.
* **Expected Result**:
  * Week 2 table is **clean and uncluttered**.
  * Previous week rows (`DBT` and `Sick Leave` with 0.00 hours) are **hidden**.
  * Exactly **1 blank row** is provided ready for Week 2 entries.
  * Badge displays: `Active Week: 0.00h`, `Cycle Total: 40.00h`.

---

### TC_GRID_002: Re-selecting Existing Project in Week 2 (Smart Row Linking)
* **Preconditions**: User is on Week 2 tab after entering `DBT` in Week 1.
* **Test Steps**:
  1. In the blank row of Week 2, open Project dropdown.
  2. Select `DBT - Documentation / Review`.
  3. Enter 8h on Monday of Week 2.
  4. Click **Save**.
* **Expected Result**:
  * Project is selected without duplicate row errors.
  * System re-links to the existing project line item seamlessly.
  * Record saves successfully.

---

### TC_GRID_003: Protected Row Deletion in Active Week View
* **Preconditions**: Project `DBT` has hours in both Week 1 (16h) and Week 2 (8h).
* **Test Steps**:
  1. Switch to Week 2 tab.
  2. Click the Trash / Delete icon on the `DBT` row.
  3. Switch to Week 1 tab.
* **Expected Result**:
  * In Week 2, hours for that week are cleared to 0.00 and row disappears.
  * In Week 1, the 16.00 hours remain completely intact and untouched.

---

### TC_GRID_004: Multi-Week Tab Navigation across Entire Month
* **Test Steps**:
  1. Open monthly timesheet (30 days).
  2. Click through Week 1, Week 2, Week 3, Week 4, and Week 5.
* **Expected Result**:
  * Tabs switch instantly.
  * Week 5 renders partial week (2 days: Nov 29 - Nov 30) correctly.
  * Date headers update dynamically to match each week slice.

---

### TC_GRID_005: Multi-Week Save & Database Persistence
* **Test Steps**:
  1. Enter hours across multiple weeks (Week 1 = 40h, Week 2 = 32h).
  2. Click **Save** button.
  3. Hard refresh the browser page (Ctrl+F5).
  4. Inspect Week 1 and Week 2 tabs.
* **Expected Result**:
  * Toast message: `Timesheet saved successfully`.
  * Week 1 displays 40h, Week 2 displays 32h. Cycle Total displays 72.00h.

---

### TC_FLEX_012: Grid Column Rendering - Weekly Monday Start
* **Test Steps**:
  1. Open Monday-start timesheet record.
  2. Inspect headers.
* **Expected Result**:
  * 7 day columns rendered: Monday through Sunday with dates. Action column at end.

---

### TC_FLEX_013: Grid Column Rendering - Weekly Sunday Start
* **Test Steps**:
  1. Open Sunday-start timesheet record.
* **Expected Result**:
  * 7 day columns rendered: Sunday through Saturday with dates.

---

### TC_FLEX_014: Dynamic Column Expansion - Bi-Weekly (14 Days)
* **Test Steps**:
  1. Open 14-day timesheet.
* **Expected Result**:
  * Table dynamically renders 14 date columns with horizontal scroll and responsive headers.

---

### TC_FLEX_015: Dynamic Column Expansion - Monthly (30 Days)
* **Test Steps**:
  1. Open monthly timesheet.
* **Expected Result**:
  * Table renders week tabs and active day columns cleanly without overflow or layout breakage.

---

### TC_FLEX_016: Daily Totals and Billable Calculation across Dynamic Columns
* **Test Steps**:
  1. Enter 8h on Day 1, 4h on Day 3 for project.
  2. Add Absence row and enter 8h on Day 2.
  3. Check summary rows: Project Hours, Absence Hours, Total Hours, Billable Amount.
* **Expected Result**:
  * Daily sums calculate accurately. Billable amount matches `Rate * Billable Hours`.

---

### TC_FLEX_017: Save and Reload Persistence with Dynamic Cycles
* **Test Steps**:
  1. Click Save button in LWC grid.
  2. Refresh browser window.
* **Expected Result**:
  * All entered project and absence hours persist accurately.

---

## Suite 5: Scheduled Reminders & Guidance Flows

### TC_FLEX_018: Reminder Flow Fires 2 Days Before End Date
* **Test Steps**:
  1. In Setup > Flows, open **`Timesheet Remainder STF`**.
  2. Click Debug, select a timesheet whose `End_Date__c` is 2 days after TODAY (so `Is_Due_For_Reminder__c` = true).
  3. Click **Run**.
* **Expected Result**:
  * `Is_Due_For_Reminder__c` = true. Email sent to timesheet owner with dynamic Start and End dates.

---

### TC_FLEX_019: Reminder Flow Skips Timesheets Far From End Date
* **Test Steps**:
  1. In `Timesheet Remainder STF` Debug, select a timesheet whose `End_Date__c` is 5+ days in future.
  2. Click **Run**.
* **Expected Result**:
  * `Is_Due_For_Reminder__c` = false. Flow Start filter excludes the record without sending email.

---

### TC_FLEX_020: Follow-Up Email Fires on Final Day of Cycle
* **Test Steps**:
  1. In Setup > Flows, open **`Timesheet Submission Follow-up Email STF`**.
  2. Click Debug, select timesheet with `End_Date__c` = `TODAY()` (so `Is_Due_For_Follow_Up__c` = true).
  3. Click **Run**.
* **Expected Result**:
  * `Is_Due_For_Follow_Up__c` = true. Email executes specifying: `"Please submit by the end of today."`

---

### TC_FLEX_021: In-App Guidance Permission Assigned 2 Days Before End Date
* **Test Steps**:
  1. Ensure an active employee has a `New`, non-demo timesheet with `End_Date__c` = `TODAY() + 2`.
  2. In Setup > Flows, open **`In-app Guidence using STF`**.
  3. Click Debug > Run.
* **Expected Result**:
  * `Get_This_Week_Timesheets` matches `End_Date__c = ReminderTargetDate` (`TODAY() + 2`).
  * `Timesheet_Reminder_Access` permission set assigned to active user with 3-day expiration date (`NOW() + 3`), displaying the `TimesheetSubmission` prompt (*"before the end of your current timesheet period"*).

---

## Suite 6: Timesheet Formulas & Goal Completion Verification

### TC_FLEX_022: Sunday Start Goal Completion
* **Test Steps**:
  1. Open Sunday-start timesheet (7 days). Set Total Hours = 40.
  2. Inspect Weekly Goal Completion and Percent fields.
* **Expected Result**:
  * Weekly Goal Completion displays full bar: `[=====]`.
  * Weekly Goal Completion Percent displays `100%`. (Fixed previous 0% issue).

---

### TC_FLEX_023: Multi-Week (Bi-Weekly) Goal Scaling
* **Test Steps**:
  1. Open Bi-Weekly timesheet (14 days, 80h expected).
  2. Enter 40 Total Hours -> Goal displays 50%.
  3. Enter 80 Total Hours -> Goal displays 100% `[=====]`.
* **Expected Result**:
  * Goal scales proportionally with cycle duration.

---

### TC_FLEX_024: Met Weekly Hours Checkbox across Employment Types
* **Test Steps**:
  1. Full Time: checked when Total Hours >= 40 (or 80 for bi-weekly).
  2. Part Time: checked when Total Hours >= 20 (or 40 for bi-weekly).
  3. Internship: checked when Total Hours >= 10 (or 20 for bi-weekly).
* **Expected Result**:
  * `Met_Weekly_Hours__c` checkbox dynamically checks based on scaled threshold.

---

## Appendix: 1-Click Anonymous Apex Test Generator

Open **Developer Console** > **Debug** > **Open Execute Anonymous Window** and execute:

```apex
// Find active employee
Employee__c emp = [SELECT Id, Name FROM Employee__c WHERE Active__c = true AND Is_Demo__c = false LIMIT 1];
Date today = Date.today();

// 1. Weekly Monday-Start Timesheet
Date monStart = today.toStartOfWeek().addDays(1);
Timesheet__c tsMon = new Timesheet__c(
    Name = 'Manual Test: Weekly Monday (' + monStart + ')',
    Employee__c = emp.Id,
    Start_Date__c = monStart,
    End_Date__c = monStart.addDays(6),
    Status__c = 'New'
);
insert tsMon;

// 2. Weekly Sunday-Start Timesheet
Date sunStart = today.toStartOfWeek();
Timesheet__c tsSun = new Timesheet__c(
    Name = 'Manual Test: Weekly Sunday (' + sunStart + ')',
    Employee__c = emp.Id,
    Start_Date__c = sunStart,
    End_Date__c = sunStart.addDays(6),
    Status__c = 'New'
);
insert tsSun;

// 3. Bi-Weekly Timesheet (14 Days)
Timesheet__c tsBiWeekly = new Timesheet__c(
    Name = 'Manual Test: Bi-Weekly (' + monStart + ')',
    Employee__c = emp.Id,
    Start_Date__c = monStart,
    End_Date__c = monStart.addDays(13),
    Status__c = 'New'
);
insert tsBiWeekly;

// 4. Monthly Timesheet (Current Calendar Month)
Date monthStart = today.toStartOfMonth();
Date monthEnd = today.addMonths(1).toStartOfMonth().addDays(-1);
Timesheet__c tsMonthly = new Timesheet__c(
    Name = 'Manual Test: Monthly (' + monthStart + ')',
    Employee__c = emp.Id,
    Start_Date__c = monthStart,
    End_Date__c = monthEnd,
    Status__c = 'New'
);
insert tsMonthly;

System.debug('Created Test Timesheets:');
System.debug('Weekly Mon ID: ' + tsMon.Id);
System.debug('Weekly Sun ID: ' + tsSun.Id);
System.debug('Bi-Weekly ID:  ' + tsBiWeekly.Id);
System.debug('Monthly ID:    ' + tsMonthly.Id);
```
