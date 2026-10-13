# Submit for Approval Visibility Rules & Formula Findings

## 1. Overview
The visibility of the **Submit** (Submit for Approval) action on the Timesheet Lightning record page is governed by Dynamic Action Visibility Rules and an underlying formula field (`Met_Weekly_Hours__c`).

---

## 2. Dynamic Action Visibility Filter
Configured in the Lightning Record Page metadata:  
- **File:** `Timesheet/main/default/flexipages/Timesheet_Master_Record_Page1.flexipage-meta.xml` (Lines 11–27)

### Filter Criteria (`1 AND 2 AND 3`):
| # | Field / Expression | Operator | Value | Description |
|---|---|---|---|---|
| 1 | `Status__c` | Equal | `New` | Timesheet must be in "New" status. |
| 2 | `Met_Weekly_Hours__c` | Equal | `true` | Minimum hours required per employment type are satisfied. |
| 3 | `Manager__r.Alias` | Not Equal | *null/empty* | Timesheet has an assigned manager. |

---

## 3. Underlying Formula: `Met_Weekly_Hours__c`
Configured on the `Timesheet__c` custom object:  
- **File:** `Timesheet/main/default/objects/Timesheet__c/fields/Met_Weekly_Hours__c.field-meta.xml`  
- **Return Type:** `Checkbox (Boolean)`

### Formula:
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

### Hours Threshold Summary:
- **Full Time:** `Total_Hours__c >= 40`
- **Part Time:** `Total_Hours__c >= 20`
- **Internship:** `Total_Hours__c >= 10`
- **Others / Unspecified:** Evaluates to `FALSE`

---

## 4. Custom LWC Component Visibility (Alternative Grid Action)
For the custom grid component (`Timesheet/main/default/lwc/timesheetLineItemEntry/timesheetLineItemEntry.js` Lines 128–141):
- **Submit Button (`showSubmitButton`):** Visible when `!isTimesheetLocked` (`Status__c` is neither `'Submitted'` nor `'Approved'`) and `Total Hours > 0`.
- **Partial Submit Button (`showPartialSubmitButton`):** Visible when `Allow_Partial_Submit__c` is enabled, timesheet is not locked, and there is at least one unsubmitted/unapproved line item with date `<= today`.
