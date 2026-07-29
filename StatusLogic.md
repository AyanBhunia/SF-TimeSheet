
# System Context & Requirement Specification

You are an expert software architect and developer. I need you to implement a state machine and status-syncing logic between a parent object (`Timesheet`) and its child objects (`Line Items`).

Below are the exact statuses, invariants, and state transition rules.

## 1. Data Model & Allowed Values

* **Timesheet Statuses:** `New`, `Partial`, `Submitted`, `Approved`
* **Line Item Statuses:** `New`, `Partial Submitted`, `Partial Approved`, `Submitted`, `Approved`

## 2. Invariants (Golden Rules)

At any given time, the Timesheet status MUST logically align with its Line Items.

* If Timesheet = `New` ➔ ALL Line Items = `New`
* If Timesheet = `Partial` ➔ Line Items are either `Partial Submitted` or `Partial Approved`.
* If Timesheet = `Submitted` ➔ Line Items = `Submitted` (except  `Partial Submitted` ).
* If Timesheet = `Approved` ➔ ALL Line Items = `Approved`.

## 3. Actor Actions & State Transitions

Implement logic to handle the following operations based on the Actor performing them.

### A. Employee Operations

1. **Action:** Partial Submit
    * **Pre-condition:** Timesheet is `New`.
    * **Result:** Timesheet becomes `Partial`. Target Line Items become `Partial Submitted`.
2. **Action:** Submit (Full)
    * **Pre-condition:** Timesheet is `New` or `Partial`.
    * **Result:** Timesheet becomes `Submitted`. ALL Line Items become `Submitted`, **EXCEPT** any Line Items already marked as `Partial Approved` (which retain their status).

### B. Manager Operations

1. **Action:** Partial Approve
    * **Pre-condition:** Timesheet is `Partial`.
    * **Result:** Timesheet remains `Partial`. Target Line Items become `Partial Approved`.
2. **Action:** Partial Reject
    * **Pre-condition:** Timesheet is `Partial`.
    * **Result:** Target Line Items become `New`.
    * **Conditional Rollup Logic:** If this rejection results in ALL Line Items on the Timesheet having a status of `New`, the Timesheet status must automatically revert to `New`. Otherwise, the Timesheet remains `Partial`.
3. **Action:** Approve (Full)
    * **Pre-condition:** Timesheet is `Submitted`.
    * **Result:** Timesheet becomes `Approved`. ALL Line Items become `Approved`.
4. **Action:** Reject (Full)
    * **Pre-condition:** Timesheet is `Submitted`.
    * **Result:** Timesheet becomes `New`. ALL Line Items become `New`,**EXCEPT** any Line Items already marked as `Partial Approved` (which retain their status).

### C. System Admin Operations (Manual Overrides)

System Admins can forcefully change the Timesheet status. The system must cascade these changes to the Line Items as follows:

1. **Override:** `Partial` to `New`
    * **Cascade:** ALL Line Items become `New`.
2. **Override:** `Submitted` to `New`
    * **Cascade:** Line Items become `New`, **EXCEPT** those currently marked `Partial Approved` (which keep their status).
3. **Override:** `Approved` to `New`
    * **Cascade:** ALL Line Items become `New`.
4. **Override:** `Approved` to `Submitted`
    * **Cascade:** ALL Line Items become `Submitted`.
5. **Override:** `Submitted` to `Partial`
    * **Cascade:** Line Items become `Partial Submitted`, **EXCEPT** those currently marked `Partial Approved` (which keep their status).
6. **Override:** `Approved` to `Partial`
    * **Cascade:** ALL Line Items become `Partial Submitted`.

## 4. Task Request

Based on the exact specifications above, please generate the required code/logic. Ensure that all exceptions (specifically the preservation of the `Partial Approved` status during specific transitions) and the conditional rollup logic for "Partial Reject" are strictly handled.

## 5.Useful Table

| USER         | Operation             | Timesheet Status                                | Line Item Status                                |
|--------------|-----------------------|-------------------------------------------------|-------------------------------------------------|
| Employee     | Partial submit        | Partial                                         | Partial submitted                               |
| manager      | partial approve       | Partial                                         | Partial Approve                                 |
| Manager      | Partial Reject        | New if all line items are new now, else Partial | New                                             |
| Employee     | Submit                | Submitted                                       | Submitted<br>(all except Partial Approved)      |
| Manager      | Approve               | Approved                                        | Approved (all)                                  |
| Manager      | Reject                | New                                             | New (all)                                       |
|              |                       |                                                 |                                                 |
| System admin | Partial to new        | New                                             | New (all)                                       |
|              | Submitted to new      | New                                             | New (all except Partial Approved)               |
|              | Approved to New       | New                                             | New (all)                                       |
|              | Approved to Submitted | Submitted                                       | Submitted (all)                                 |
|              | Submitted to partial  | Partial                                         | Partial Submitted (all except Partial Approved) |
|              | Approved to Partial   | Partial                                         | Partial Submitted (all)                         |
|              |                       |                                                 |                                                 |
