# PartialSubmit → appexchange: Change, Code/Security Review & Impact Analysis

Branches diverged at `6baacd4` (v2.26). PartialSubmit: 31 commits, 146 files (+14.8k / −1.9k). appexchange: 29 commits since (v2.28: PTO, Demo Data, Assign Employees, guidance flow, rejection-note & date-picker fixes).
Analysis delegated to agy (`gemini-3.8-flash-high`, 4 parallel runs); key findings re-verified against code by Claude. Raw agy reports: `report_A..D.md`.

## 1. What PartialSubmit contains

| Area | Components |
|---|---|
| Partial Submit | `Allow_Partial_Submit__c` (mdt), `Is_Partial_Allowed__c` (formula), `Line_Item_Status__c`, `Rejection_Notes__c`, `Status__c += Partial`, `timesheetSubmitAction`, `WeeklyTimesheetController.submitTimesheet` |
| Manager Approval | `TimesheetApprovalController` (1,575 lines), `timesheetApprovalScreen` LWC, `Timesheet_Approval` tab |
| Timer | `TimesheetTimerController` + test, `timesheetTimer` LWC (utility bar), `Start_Time__c`, `End_Time__c`, `Created_From_Timer__c` |
| Entry UI | `timesheetLineItemEntry` (rename of `testLineItem`), `timesheetMobileEntry`, `timesheetLineItemsLWC` refreshApex |
| Refactors | `TriggerHandler` framework, `TimesheetTriggerHandler`, `AccrualCalculationService`, `EmployeeSelector`/`TimesheetSelector`/`TimesheetService` (unused), `TestDataFactory` |
| Housekeeping | dashboard LWC `unsubscribe` leak fix, createPDF promise fix, `PostInstallScript` → `TimesheetPostInstallScript` rename, deletion of 9 reports + dashboard |
| Junk (root) | `temp_controller.cls`, `fix_apex.*`, `update_apex.*`, `test*.apex`, `test_lwc.js`, `*.md` plans, `.html` mockup, `scripts/*.apex` (hardcoded org IDs) |

## 2. Verdict — what to bring to appexchange

| Feature | Bring? | Why / blocker | Effort |
|---|---|---|---|
| Dashboard LWC `unsubscribe` fixes, createPDF fix, `timesheetLineItemsLWC` refreshApex | **Yes** | Clean bug fixes (keep appexchange's toast wording in dashboardProfile) | Low |
| Accrual refactor (`AccrualCalculationService`) | **Yes, after fixes** | `finish()` runs org-wide synchronous recalculation (50k-row risk); make new methods `public` not `global` | Medium |
| Trigger handler framework | **Yes, after fixes** | Drops appexchange's `LeaveToLineItem.forTimesheets` and `LeaveValidator.checkLineItems` calls and `User__c != null` guards → PTO breaks. `TriggerHandler` has no sharing keyword, no tests | Medium |
| Partial Submit | **Yes, after fixes** | Critical bugs below (permset FLS, auto-submit). PTO lines must be created as `Approved`; validation rule must cover `Partial` | Medium-High |
| Manager Approval screen | **Not yet** | No test class (1.5k lines), no manager authorization, non-partial path depends on a non-existent approval process, SOQL/DML in loops | High |
| Timer | **Done — redesigned on branch `timer`** (see §5) | PartialSubmit version not ported as-is; rebuilt on appexchange. Issues #4, #5, the timer parts of #10–#12 and the timer FLS part of #1 are resolved | — |
| Mobile entry | **Not yet** | No lock check on Submitted/Approved timesheets, native `confirm()`, tablets get no component | Medium |
| Line item entry rename | **Port into `testLineItem`** | Deleting `testLineItem` breaks the packaged flexipage; keep the name | Medium |
| `PostInstallScript` rename | **No** | Released `global` class – cannot be removed from a managed package | — |
| Report/dashboard deletions | **No** (product decision) | Removes subscriber-facing assets; keep unless intentionally retiring them | — |
| `EmployeeSelector`/`TimesheetSelector`/`TimesheetService` | **No** (or fix) | Unused; `EmployeeSelector` is `global` → permanent API burden | — |
| Root junk, `scripts/*.apex`, `sfdx-project.json` (v2.26 / TimeSheetTest), `.sf*` | **No** | Keep appexchange's sfdx-project.json (v2.28 ancestors) | — |

## 3. Critical / High issues (verified ✔ = confirmed by Claude in code)

| # | Sev | Issue | Location | Fix |
|---|---|---|---|---|
| 1 | Critical ✔ | New fields `Line_Item_Status__c`, `Rejection_Notes__c`, `Created_From_Timer__c`, `Is_Partial_Allowed__c` are in **no** permission set. Trigger + timer queries use `WITH SECURITY_ENFORCED` → non-admin users get `QueryException` on line-item insert/timer load; `stripInaccessible` silently drops approvals | 3 permsets; `TimesheetLineItemTriggerHandler.cls:335`, `TimesheetTimerController.cls:21` | Add FLS (Read for User, Edit for Manager/HR) |
| 2 | Critical ✔ | `Timesheet__c.Employee__c` FLS removed from all 3 permsets (present on appexchange) | permissionsets | Keep appexchange entries |
| 3 | Critical ✔ | Adding a line item to a **New** partial-allowed timesheet flips it to `Submitted` (afterInsert → `touchParentTimesheetIfStatusChanged` computes `'Submitted'` whenever not all approved). `Allow_Partial_Submit__c` defaults true → affects every timesheet | `TimesheetLineItemTriggerHandler.cls:13-18, 383-399` | Only recompute when parent is already Submitted/Partial |
| 4 | Critical ✔ — **resolved in `timer`** | `getTimerInitData` is `@AuraEnabled(cacheable=true)` but calls `discardTimer` (DML) → runtime error when active timer's project is inactive | `TimesheetTimerController.cls:3, 40` | Make non-cacheable or move discard to a separate call |
| 5 | Critical ✔ (found by Claude) — **resolved in `timer`** (timer never creates timesheets) | Timer creates `Timesheet__c` with `Status__c = 'Draft'` — not a value in the restricted picklist (New/Partial/Submitted/Approved) → insert fails; also `Timesheet_User` has `allowCreate=false` on Timesheet__c | `TimesheetTimerController.cls:402-408` | Use `'New'`; don't create timesheets from timer (flow owns creation) |
| 6 | Critical ✔ | Non-partial approve/reject require a `ProcessInstanceWorkitem`; no Timesheet approval process exists in either branch, submit only calls `Approval.lock` → always "No pending approval request" | `TimesheetApprovalController.cls:1503-1573`, `WeeklyTimesheetController.cls:202` | Drop the approval-process dependency; set statuses directly (unlock first) |
| 7 | Critical | `TimesheetApprovalController` (1,575 lines), `TimesheetTriggerHandler`, `TriggerHandler` have no tests; Jest tests are `expect(1).toBe(1)` | — | Write tests before packaging (75% gate) |
| 8 | Critical ✔ | Released `global class PostInstallScript` renamed → package version create fails | `classes/TimesheetPostInstallScript.cls`, `Command.txt` | Keep `PostInstallScript` |
| 9 | Critical ✔ | Merge would drop PTO hooks: `LeaveToLineItem.forTimesheets` (appexchange `TimesheetTrigger.trigger:75`) and `LeaveValidator.checkLineItems` (handler L8/L14) are absent from new handlers | `TimesheetTriggerHandler.afterInsert`, `TimesheetLineItemTriggerHandler.before*` | Re-add both calls |
| 10 | High ✔ | Authorization: `approveLineItems`, `rejectLineItemsWithNotes`, `approveTimesheets`, `rejectTimesheets`, `submitTimesheet`, timer `startTimer/stopTimer/discardTimer` never check caller is the manager/owner (only `with sharing`) | `TimesheetApprovalController.cls:1231-1421`, `TimesheetTimerController.cls:73-370` | Check `Employee__r.Manager…/User__c == UserInfo.getUserId()` or custom permission (`PTO_Approve_Team`-style) |
| 11 | High | SOQL/DML inside loops in `approveTimesheets`/`rejectTimesheets`, `Approval.process` per record, timer `getOrCreateTimesheet` per day | `TimesheetApprovalController.cls:1237-1448`, `TimesheetTimerController.cls:211-242` | Bulkify |
| 12 | High ✔ | Hardcoded `dbt__` field names in LWCs (approval screen 8, line item entry 59, timer 3) — breaks in non-namespaced scratch/unlocked orgs | lwc JS | Use `@salesforce/schema` imports |
| 13 | High | Dynamic SOQL in approval controller without `WITH USER_MODE`; `TriggerHandler` has no sharing keyword — both flagged by Security Review scanners | `TimesheetApprovalController.cls:284, 704, 975, 1009, 1065`; `TriggerHandler.cls:1` | `WITH USER_MODE`, `inherited sharing` |
| 14 | High | Test classes in `<classAccesses>` of permsets (appexchange removed them in 900a60d) | permissionsets | Strip `*Test` |
| 15 | High | Flow `Timesheets_Creation_STF` loses appexchange's `OwnerId = User__c` and `Is_Demo__c = false` filter | flow | Keep appexchange version |
| 16 | Medium | Errors returned as `'Error: ' + e.getMessage()` strings instead of `AuraHandledException`; `List has no rows` risk on `LIMIT 1` assignments; rejection sets status `New` not `Rejected`; `Partial*` picklist values unused | approval controller | — |
| 17 | Medium | Static recursion set never cleared (chunked DML), two triggers compute parent status with different rules (`Met_Weekly_Hours__c` vs not) | `TimesheetTriggerHandler.cls:3, 204`; LI handler 390 | Single status-rollup service |
| 18 | Medium | appexchange `DemoDataControllerTest` asserts ≤25 SOQL in `createDemoLineItems`; extra after-trigger queries likely break it | appexchange test L269 | Re-run, adjust |

Rejected agy claims (not issues): `Datetime.newInstance(Long)` is a valid Apex overload; "timezone skew" in midnight split (both values are absolute instants); report D's statement that PartialSubmit permsets include the new fields (they don't).

## 4. Merge strategy

Do **not** `git merge PartialSubmit` into appexchange. Create `feature/partial-submit-ax` from `origin/appexchange` and port by layer:

1. Data model: new fields + `Partial` picklist value + mdt field; merge `Default_Values` record (keep 6 `Max_*_Hours__c` + add `Allow_Partial_Submit__c`).
2. Safe fixes: dashboard LWCs, createPDF, timesheetLineItemsLWC.
3. Trigger framework + accrual service, re-adding `LeaveToLineItem`, `LeaveValidator`, `User__c != null` guards; `inherited sharing`; tests.
4. Partial submit logic with fixes #1, #3, #6; `LeaveToLineItem` sets `Line_Item_Status__c = 'Approved'`; validation rule covers `Partial`.
5. Approval screen after #7, #10, #11, #12 are fixed.
6. Timer: **done on branch `timer`** (§5). Mobile entry still open (#10 lock check, `confirm()`, tablets).
7. Permsets: appexchange superset + new FLS/classes/tab, no test classes.
8. Keep appexchange `sfdx-project.json`, `PostInstallScript`, reports, flow, `testLineItem`. Bump to 2.29.0.NEXT. `sf apex run test -l RunLocalTests -c`.

## 5. Timer — current implementation (branch `timer`, from `appexchange`)

The PartialSubmit timer was not ported; it was rebuilt on appexchange in a simpler form and tested end to end in tsorg.

**Design**
- A running timer is a normal `Timesheet_Line_Item__c` (today, chosen project + activity) whose new field `Timer_Data__c` (Text 255) holds the timer state as JSON. No other new fields, no `Start_Time__c`/`End_Time__c`/`Created_From_Timer__c`.
- Start finds today's row for project + activity on the user's latest timesheet covering today, or creates it at 0h. The timer never creates timesheets; no timesheet → clear message.
- The clock shows the **line item total**: current `Duration__c` + timer time. It auto-stops when the total reaches `Working_Hours_Per_Day__c` (8); Continue runs up to `min(Maximum_Working_Hrs_Per_Day__c, 24)`. The stop is worked out on read (no scheduled job) at the exact moment the limit was hit.
- Save adds the timer time to that row's **current** `Duration__c` (manual edits during the run count) and clears `Timer_Data__c`. One row only, no midnight split. The 24h daily limit is left to the existing validation; its message is shown.
- Discard deletes a row the timer created (0h), otherwise only clears `Timer_Data__c`. Continue only on the start day (server-enforced, server date).
- Guards: one running timer per employee, owner-only actions (`ownedTimer`), Submitted/Approved timesheet and inactive project blocked, `WITH SECURITY_ENFORCED` + `stripInaccessible`, no cacheable DML.

**Where it shows**
- Desktop: utility bar (`Time_Sheet_UtilityBar`, needs *Load in background* = on) with the live clock on the bar label (`lightning/platformUtilityBarApi`: `EnclosingUtilityId` + `updateUtility`).
- Phone: full-screen layout at the top of Employee Overview (`phoneOnly`), shown only with custom permission `Timesheet_Timer`. On phones Contribution Graph, Weekly Chart and Select Employee are hidden (`$Client.FormFactor`); Employee Details stacks its columns.
- Weekly grid (`testLineItem`): never deletes a running timer's row (guard in `WeeklyTimesheetController.deleteTimesheetLineItems`); reloads when the timer changes it, warns before overwriting with unsaved edits; tells open timers to reload after its own save.

**Security / permissions**: `TimesheetTimerController` class access, `Timer_Data__c` FLS and custom permission `Timesheet_Timer` in Timesheet User / Manager / HR Admin.

**Tests**: `TimesheetTimerControllerTest` 18 tests, 97% coverage; RunLocalTests 116/116 in tsorg. Browser E2E (Playwright, 13 scenarios / 47 checks, real data): normal save, reuse existing row, 24h validation, inactive project, submitted timesheet, row deleted elsewhere, second device, grid interplay, midnight, two tabs, double click, auto-stop at 8h + continue, clock includes row hours and follows record/grid edits. agy reviews run on each step; findings verified before fixing.

**Open / decided**
- Accepted as-is (product decision): sessions < 6 min can't be saved; overlapping timesheets use the latest; deleting a running row in the grid reappears silently.
- Utility bar timer ignores `Timesheet_Timer` (utility items have no visibility rules) and Apex does not check the permission — option: dedicated *Timesheet Timer* permission set + component/Apex permission check.
- tsorg's utility bar was edited in App Manager (eager off, right aligned); source has eager on, left aligned.
- `timesheetLineItemsLWC` (not on any page) deletes rows without the running-timer guard.

