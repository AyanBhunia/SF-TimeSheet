# Things to Do: SF-TimeSheet

## Phase 1: Critical Fixes
- **Name:** 1. Move TimesheetTrigger logic to a handler class
  - **Description:** `TimesheetTrigger` contains 172 lines of business logic. It needs to be moved to a handler class for better testing and maintenance.
  - **Implementation details:** Create `TimesheetTriggerHandler.cls`. Move before insert, before update, after insert, after update, after delete, after undelete logic. Ensure it checks recursion if necessary.
  - **Status:** Completed
  - **Comment:** 

- **Name:** 2. Add CRUD/FLS enforcement on managed package object queries
  - **Description:** Queries against `dbt__Timesheet__c`, `dbt__Employee__c`, etc. lack `WITH SECURITY_ENFORCED`.
  - **Implementation details:** Add `WITH SECURITY_ENFORCED` or use `Security.stripInaccessible()` on `TimesheetAccrualBatch`, `EmployeeAccrualUpdater`, and `TimesheetTriggerHandler`. Fix DML updates using `Database.update(records, false)` instead of bare `update`.
  - **Status:** Completed
  - **Comment:** 

- **Name:** 3. Add try-catch with AuraHandledException to all @AuraEnabled methods
  - **Description:** Missing error handling exposes raw exceptions.
  - **Implementation details:** Wrap queries and DML in try/catch in `GetEmployeeDetails`, `GetTimesheet`, `GetTimesheetLineItems`, `GetDashboardTimesheetLineItems`, `GetRangeOfTimesheetsLineItems`, `WeeklyTimesheetController`, `ProjectController`.
  - **Status:** Completed
  - **Comment:** 

- **Name:** 4. Fix deployment blockers in problems.txt
  - **Description:** Several packaging installation errors exist (OwnerId on detail object, invalid report fields, etc.).
  - **Implementation details:** 
    1. Remove `OwnerId` from tests (`ProjectControllerTest`, `TimesheetLineItemLwcControllerTest`, `TimesheetLineItemTriggerHandlerTest`).
    2. Change `Timesheet__c` sharingModel to `ControlledByParent` (or remove `MasterDetail` if it should be Private).
    3. Remove invalid `InformalName` field on User.
    4. Fix or delete obsolete reports (Activity_wise_Weekly_report_Kjd, etc.).
    5. Rename `PostInstallScript` to avoid conflicts.
    6. Fix list view column `OWNER.ALIAS`.
  - **Status:** Completed
  - **Comment:** @User, for the `Timesheet__c` sharing model conflict: Should `Timesheet__c` be Private (meaning we must change the Master-Detail relationship with Employee to a Lookup), or should it remain Master-Detail (meaning we can't set it to Private)? - Answer: We can not change any existing relationship as this is existing application in appexchange , and salesforce does not allow changes like this.

- **Name:** 5. Fix TimesheetAccrualBatch and EmployeeAccrualUpdater modifiers
  - **Description:** Batch is `global`, missing `with sharing`.
  - **Implementation details:** Change to `public with sharing class TimesheetAccrualBatch`. Add `with sharing` to `EmployeeAccrualUpdater`.
  - **Status:** Completed
  - **Comment:** 

- **Name:** 6. Fix LWC Critical Promises and Module cache
  - **Description:** Unhandled promise rejections in PDF components, shared data cache issues, LMS leak.
  - **Implementation details:** 
    1. Fix `initializePDFLibraries` in `createEmployeeTimesheet` and `createPDF`.
    2. Add `disconnectedCallback` with LMS `unsubscribe` in dashboard components.
    3. Replace `location.reload()` with `refreshApex` in `timesheetLineItemsLWC`.
  - **Status:** Completed
  - **Comment:** 

## Phase 2: Code Quality
- **Name:** 7. Create TestDataFactory
  - **Description:** Eliminate duplicate setup logic in test classes.
  - **Implementation details:** Create `TestDataFactory.cls` with `createEmployee`, `createTimesheet`, `createLineItem`, etc.
  - **Status:** Completed
  - **Comment:** 

- **Name:** 8. Consolidate Duplicate Accrual Logic
  - **Description:** DRY violation on accrual calculation.
  - **Implementation details:** Create `AccrualCalculationService.cls` and use it in triggers and batch.
  - **Status:** Completed
  - **Comment:** 

- **Name:** 9. Replace manual FLS checks with WITH SECURITY_ENFORCED
  - **Description:** In `TimesheetLineItemLwcController` and `TimesheetLineItemController`.
  - **Implementation details:** Simplify controller security code.
  - **Status:** Completed
  - **Comment:** 

- **Name:** 10. Clean up unused/debug code
  - **Description:** Remove debug prints, dead code, testLineItem.
  - **Implementation details:** Delete `testLineItem` LWC, `TimesheetLineItemController.cls` if unused. Remove `System.debug` in production.
  - **Status:** Completed
  - **Comment:** 

## Phase 3 & 4: Architecture & New Features
- **Name:** 11. Implement proper trigger framework
  - **Description:** Build a unified trigger dispatcher.
  - **Implementation details:** E.g., `TriggerHandler` virtual class.
  - **Status:** Completed
  - **Comment:** 

- **Name:** 12. Create Service Layer and DAL
  - **Description:** Separate SOQL and logic from controllers.
  - **Implementation details:** Create Selector classes and Service classes.
  - **Status:** Completed
  - **Comment:** 

- **Name:** 13. New Features
  - **Description:** Implement timer, mobile UI, manager dashboard, templates, etc.
  - **Implementation details:** (To be defined step by step).
  - **Status:** Pending
  - **Comment:** @User, let me know which features from Phase 4 of the review you want me to prioritize first after we finish Phase 1 & 2.
