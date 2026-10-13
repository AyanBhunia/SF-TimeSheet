# Timesheet Hour Defaults, Submission Rules & Approval Specifications

---

## 1. Executive Summary
This document provides a comprehensive technical reference for:
1. Default values configured for timesheet hours and line item duration.
2. Global metadata settings controlling hour limits and submission behavior.
3. Weekly hours thresholds required to enable timesheet submission.
4. Visibility rules and conditions governing the **"Submit for Approval"** action.
5. System automations (Flows, Apex, LWC) enforcing these rules.

---

## 2. Field-Level Default Values

### 2.1 `Timesheet_Line_Item__c.Duration__c`
* **File:** `Timesheet/main/default/objects/Timesheet_Line_Item__c/fields/Duration__c.field-meta.xml`
* **Type:** Number (18, 2)
* **Default Value:** `8` (8 hours)
* **Description:** Pre-populates daily logged hours to 8 when a new timesheet line item is created.

### 2.2 Other Related Field Defaults
| Object | Field | Default Value | Description |
|---|---|---|---|
| `Timesheet_Line_Item__c` | `Date__c` | `TODAY()` | Defaults line item date to current date |
| `Timesheet_Line_Item__c` | `Hours_Limit_Exceeded__c` | `false` | Flag set by Flow when daily limit is exceeded |
| `Employee__c` | `Accrual_Divisor__c` | `9` | Divisor used in PTO / vacation accrual calculation |
| `Employee__c` | `Total_Accrued_Hours__c` | `0` | Base accrued vacation hours |
| `Employee__c` | `Total_Absence_Hours__c` | `0` | Base absence hours |

---

## 3. Global Configuration (Custom Metadata)

### 3.1 `Timesheet_Default_Value__mdt` -> `Default_Values`
* **Metadata Record File:** `Timesheet/main/default/customMetadata/Timesheet_Default_Value.Default_Values.md-meta.xml`

| Field API Name | Configured Value | Unit | Functional Purpose |
|---|---|---|---|
| `Working_Hours_Per_Day__c` | **`8.0`** | Hours | Standard expected working hours per day. |
| `Maximum_Working_Hrs_Per_Day__c` | **`24.0`** | Hours | Absolute maximum allowed hours per employee per day across all line items. |
| `Working_Days_per_Week__c` | **`5.0`** | Days | Standard working days in a weekly cycle. |
| `Accrued_Vacation_Days__c` | **`10.0`** | Days | Standard annual/periodic baseline vacation days. |
| `Allow_Partial_Submit__c` | **`true`** | Boolean | Controls whether users can submit partial day entries before the week ends. |

---

## 4. Weekly Hours Thresholds for Submission

### 4.1 Formula Field: `Timesheet__c.Met_Weekly_Hours__c`
* **File:** `Timesheet/main/default/objects/Timesheet__c/fields/Met_Weekly_Hours__c.field-meta.xml`
* **Return Type:** Checkbox (`Boolean`)

#### Formula Definition:
```sql
IF(
    ISPICKVAL(Employee__r.Employment_Type__c, "Full Time"),
    Total_Hours__c >= 40,
    IF(
        ISPICKVAL(Employee__r.Employment_Type__c, "Part Time"),
        Total_Hours__c >= 20,
        IF(
            ISPICKVAL(Employee__r.Employment_Type__c, "Internship"),
            Total_Hours__c >= 10,
            FALSE
        )
    )
)
```

#### Threshold Breakdown:
| Employment Type (`Employee__r.Employment_Type__c`) | Minimum Required Weekly Hours (`Total_Hours__c`) | Result if Met |
|---|---|---|
| **Full Time** | **>= 40 Hours** | `TRUE` |
| **Part Time** | **>= 20 Hours** | `TRUE` |
| **Internship** | **>= 10 Hours** | `TRUE` |
| **Unspecified / Other** | N/A | `FALSE` |

---

## 5. "Submit for Approval" Visibility Rules

### 5.1 Lightning Record Page Dynamic Action Rule
* **Record Page:** `Timesheet_Master_Record_Page1.flexipage-meta.xml` (Lines 11–27)
* **Action Name:** Standard `Submit` (Submit for Approval)

#### Filter Criteria (`1 AND 2 AND 3`):
1. **Timesheet Status:** `{!Record.Status__c} == 'New'`
2. **Weekly Hours Target Met:** `{!Record.Met_Weekly_Hours__c} == true`
3. **Manager Assigned:** `{!Record.Manager__r.Alias} != null`

> **Note:** If the timesheet is already `Submitted` or `Approved`, or if total hours do not satisfy the employment type threshold, or if no manager is assigned, the Submit action button is hidden.

---

## 6. Automations & Component Logic

### 6.1 Daily Duration Limit Enforcement (Flow)
* **Flow Name:** `Duration_Limit_RTF` (`Duration_Limit_RTF.flow-meta.xml`)
* **Trigger:** Record-triggered on `Timesheet_Line_Item__c` create/update.
* **Logic:**
  1. Queries `Timesheet_Default_Value__mdt.Default_Values`.
  2. Sums total line item durations for that employee on that specific date (`Date__c`).
  3. Checks if `Sum(Duration__c) > Maximum_Working_Hrs_Per_Day__c` (24.0 hrs).
  4. Flags `Hours_Limit_Exceeded__c` accordingly.

### 6.2 Custom LWC Grid Submission (`timesheetLineItemEntry`)
* **File:** `Timesheet/main/default/lwc/timesheetLineItemEntry/timesheetLineItemEntry.js`
* **Full Submit (`showSubmitButton`):**
  * Requires timesheet to be unlocked (`Status__c` not `Submitted` and not `Approved`).
  * Requires at least one day entry with `Duration > 0`.
* **Partial Submit (`showPartialSubmitButton`):**
  * Requires `Allow_Partial_Submit__c == true` (queried via Apex `WeeklyTimesheetController.isPartialSubmitAllowed`).
  * Requires timesheet to be unlocked.
  * Requires at least one entry on or before today's date (`day.date <= today`) that is not yet `Partial Submitted`, `Partial Approved`, or `Approved`.
