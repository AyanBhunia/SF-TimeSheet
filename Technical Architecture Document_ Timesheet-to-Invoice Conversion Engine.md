# **Technical Architecture Document: Timesheet-to-Invoice Conversion Engine**

## **1. Executive Summary & Architectural Pattern**

* **Objective:** Split and merge approved/submitted `dbt__Timesheet_Line_Item__c` records across multiple employees and projects into customer-facing `Intermediate_Invoice__c` and `Intermediate_Invoice_Line_Item__c` records aligned with the QuickBooks Online (QBO) Invoice API structure.  
* **Deployment Model:** Direct implementation inside the target Salesforce sandbox org (`sb1`) using unmanaged custom objects, fields, Flow, LWC, Aura wrapper, and Apex referencing the installed `dbt__` package objects.  
* **Selected Architecture (Option A):** **Screen Flow Orchestrator + Invocable Apex Engine (In-Memory Preview & Atomic Commit) + LWC Preview Editor + Aura Modal Wrapper**.  
  * **Aura Modal Wrapper (`c__GenerateProjectInvoicesWrapper`)**: Hosts the Flow inside a responsive Lightning modal tab, ensuring instantaneous launch and automatic list-view refresh upon completion.
  * **Screen Flow (`Generate_Project_Invoices`)**: Manages the 3-step wizard UI, user inputs (date range, billable toggle), default field mappings, candidate selection, and error fault routing.  
  * **Invocable Apex Actions (`TimesheetInvoiceFetchAction`, `TimesheetInvoicePreviewAction`, `TimesheetInvoiceCommitAction`)**: Perform high-volume querying, deduplication against previously invoiced line items, rate resolution from `dbt__Project_Employee__c`, multi-key aggregation, in-memory preview generation, and atomic DML creation.
  * **LWC Preview Editor (`invoicePreviewEditor`)**: Embedded inside Screen 3 to provide real-time accordion views by Customer Account, live recalculation of invoice totals, and inline editing of dates, memos, line descriptions, quantities, and hourly rates.

```
[Intermediate_Invoice__c List View Button]
       │
       ▼
[Aura Wrapper: c__GenerateProjectInvoicesWrapper]
       │
       ▼
[Screen 1: Filter Criteria] ──(Start/End Date, Only Billable Checkbox)
       │
       ▼
[Apex Action 1: TimesheetInvoiceFetchAction]
   - Filters by Line Item Date & Timesheet Status (Submitted/Approved)
   - Excludes Absences & already-invoiced Line Item IDs
       │
       ▼
[Screen 2: Review Candidate Timesheets]
   - Summary cards of total hours and line items
   - Selection Data Table (Fallback: auto-selects all if none explicitly checked)
       │
       ▼
[Apex Action 2: TimesheetInvoicePreviewAction]
   - Groups Header by: dbt__Project__r.Account__c
   - Merges Lines by: Project + Employee + Activity + Billable
   - Resolves Rate from: dbt__Project_Employee__c.dbt__Hourly_Rate__c (or 0 if Non-Billable)
       │
       ▼
[Screen 3: LWC Preview & Inline Edit: invoicePreviewEditor]
   - Accordion view per Customer Account
   - Live recalculation of totals upon inline edits (Quantity, Rate, Memo, Description)
       │
       ▼
[Apex Action 3: TimesheetInvoiceCommitAction]
   - Database.setSavepoint() atomic transaction
   - Inserts Intermediate_Invoice__c headers
   - Maps parent IDs and inserts Intermediate_Invoice_Line_Item__c records with Source IDs
       │
       ▼
[Screen 4: Confirmation Screen]
   - Displays count and links to newly created Intermediate Invoices
```

---

## **2. QBO-Aligned Data Model**

### **A. Existing Object Modifications**

**1. Project (`dbt__Project__c`)**
* **Field Label:** Account (`Account__c`)  
* **Data Type:** Lookup (`Account`)  
* **Purpose & QBO Mapping:** Links a project to the customer Account. Maps to QBO `Invoice.CustomerRef`. Every project under the same `Account__c` rolls into a single combined `Intermediate_Invoice__c` header for that billing run.

---

### **B. New Custom Object 1: Intermediate Invoice (`Intermediate_Invoice__c`)**

Represents the QBO Invoice header entity. One record is created per unique customer account (`dbt__Project__r.Account__c`).

* **Name (Intermediate Invoice Number)**  
  * **Type:** Auto-Number (`INV-{00000}`)  
  * **QBO Equivalent:** `DocNumber`  
  * **Mapping / Default:** System-generated upon insert.  
* **Account__c (Customer)**  
  * **Type:** Lookup (`Account`) — Required  
  * **QBO Equivalent:** `CustomerRef.value` & `CustomerRef.name`  
  * **Mapping / Default:** Populated from `dbt__Project__r.Account__c`.  
* **Invoice_Date__c (Transaction Date)**  
  * **Type:** Date  
  * **QBO Equivalent:** `TxnDate`  
  * **Mapping / Default:** Defaults to `TODAY()`; inline-editable on Preview Screen.  
* **Due_Date__c (Due Date)**  
  * **Type:** Date  
  * **QBO Equivalent:** `DueDate`  
  * **Mapping / Default:** Defaults to `TODAY() + 30` (configurable offset); inline-editable on Preview Screen.  
* **Billing_Period_Start__c & Billing_Period_End__c**  
  * **Type:** Date  
  * **QBO Equivalent:** Custom metadata / `PrivateNote` context  
  * **Mapping / Default:** Populated from the Start Date and End Date selected on Screen 1.  
* **Status__c**  
  * **Type:** Picklist (`Draft`, `Confirmed`, `Synced to QBO`, `Void`)  
  * **QBO Equivalent:** Invoice lifecycle state  
  * **Mapping / Default:** Set to `Draft` upon generation (or `Confirmed` based on policy).  
* **Customer_Email__c**  
  * **Type:** Email  
  * **QBO Equivalent:** `BillEmail.Address`  
  * **Mapping / Default:** Defaulted from Account primary contact/email; inline-editable on Preview Screen.  
* **Billing_Address__c**  
  * **Type:** Long Text Area (32,768)  
  * **QBO Equivalent:** `BillAddr` (`Line1`, `City`, `CountrySubDivisionCode`, `PostalCode`)  
  * **Mapping / Default:** Populated from `Account.BillingStreet`, `BillingCity`, `BillingState`, `BillingPostalCode`, `BillingCountry`.  
* **Memo__c (Customer Memo)**  
  * **Type:** Long Text Area (1,000)  
  * **QBO Equivalent:** `CustomerMemo.value`  
  * **Mapping / Default:** Configurable default template; inline-editable on Preview Screen.  
* **Total_Amount__c**  
  * **Type:** Currency (18, 2)  
  * **QBO Equivalent:** `TotalAmt`  
  * **Mapping / Default:** Maintained programmatically by the engine and LWC editor to allow direct screen-flow binding and live client-side editing.  
* **QB_Invoice_Id__c & QB_Sync_Token__c**  
  * **Type:** Text (50) — External ID (`QB_Invoice_Id__c`)  
  * **QBO Equivalent:** `Id` and `SyncToken`  
  * **Mapping / Default:** Populated when synchronized with QuickBooks Online.

---

### **C. New Custom Object 2: Intermediate Invoice Line Item (`Intermediate_Invoice_Line_Item__c`)**

Represents an element in the QBO `Invoice.Line[]` array where `DetailType = "SalesItemLineDetail"`.

* **Intermediate_Invoice__c**  
  * **Type:** Master-Detail (`Intermediate_Invoice__c`)  
  * **QBO Equivalent:** Parent Invoice container  
  * **Mapping / Default:** Links the line item to its parent `Intermediate_Invoice__c`.  
* **Line_Number__c**  
  * **Type:** Number (4, 0)  
  * **QBO Equivalent:** `Line.LineNum`  
  * **Mapping / Default:** Sequential integer (1, 2, 3...) per invoice.  
* **Project__c**  
  * **Type:** Lookup (`dbt__Project__c`)  
  * **QBO Equivalent:** `SalesItemLineDetail.ClassRef` or `ItemRef` context  
  * **Mapping / Default:** Populated from the merge group's `dbt__Project__c`.  
* **Employee__c**  
  * **Type:** Lookup (`dbt__Employee__c`)  
  * **QBO Equivalent:** Line metadata / resource tracking  
  * **Mapping / Default:** Populated from the merge group's `dbt__Employee__c`.  
* **Activity__c**  
  * **Type:** Text (255)  
  * **QBO Equivalent:** `SalesItemLineDetail.ItemRef.name`  
  * **Mapping / Default:** Populated from `dbt__Timesheet_Line_Item__c.dbt__Activity__c`.  
* **Description__c**  
  * **Type:** Long Text Area (4,000)  
  * **QBO Equivalent:** `Line.Description`  
  * **Mapping / Default:** Auto-formatted via template `{Project Name} - {Employee Name} ({Activity})`; inline-editable on Preview Screen.  
* **Quantity__c (Total Hours)**  
  * **Type:** Number (10, 2)  
  * **QBO Equivalent:** `SalesItemLineDetail.Qty`  
  * **Mapping / Default:** `SUM(dbt__Duration__c)` of all merged timesheet line items; inline-editable on Preview Screen.  
* **Unit_Price__c (Hourly Rate)**  
  * **Type:** Currency (16, 2)  
  * **QBO Equivalent:** `SalesItemLineDetail.UnitPrice`  
  * **Mapping / Default:** Fetched from `dbt__Project_Employee__c.dbt__Hourly_Rate__c` if Billable = true, or `0.00` if Billable = false; inline-editable on Preview Screen.  
* **Amount__c (Line Total)**  
  * **Type:** Formula (Currency): `Quantity__c * Unit_Price__c`  
  * **QBO Equivalent:** `Line.Amount`  
  * **Mapping / Default:** Automatically calculated.  
* **Billable__c**  
  * **Type:** Checkbox  
  * **QBO Equivalent:** Internal tracking / $0 line indicator  
  * **Mapping / Default:** Matches the merge group's `dbt__Billable__c` value.  
* **Service_Date__c**  
  * **Type:** Date  
  * **QBO Equivalent:** `SalesItemLineDetail.ServiceDate`  
  * **Mapping / Default:** Latest `dbt__Date__c` among merged timesheet lines (or Billing Period End Date).  
* **QB_Item_Id__c & QB_Tax_Code__c**  
  * **Type:** Text (50)  
  * **QBO Equivalent:** `SalesItemLineDetail.ItemRef.value` & `TaxCodeRef.value`  
  * **Mapping / Default:** Optional default QBO Service Item ID passed from Flow.  
* **Source_Timesheet_Line_Items__c (Traceability & Deduplication Field)**  
  * **Type:** Long Text Area (131,072 characters)  
  * **QBO Equivalent:** Internal Salesforce audit trail  
  * **Mapping / Default:** Comma-separated list of 18-character `dbt__Timesheet_Line_Item__c` IDs. Allows storing thousands of source IDs without modifying locked timesheet records.

---

## **3. Core Business Logic & Rules**

### **Rule 1: Candidate Timesheet Selection & In-Memory Deduplication**

Because submitted/approved timesheets are locked by approval processes, no DML updates are performed on `dbt__Timesheet_Line_Item__c`. Instead, deduplication is executed in two steps:

1. **Collect Already-Invoiced Line Item IDs:**  
   * Query all existing `Intermediate_Invoice_Line_Item__c` records where `Intermediate_Invoice__r.Status__c != 'Void'`.  
   * Extract and parse every comma-separated ID in `Source_Timesheet_Line_Items__c` into an in-memory `Set<Id> alreadyInvoicedIds`.  
2. **Fetch Eligible `dbt__Timesheet_Line_Item__c` Records:**  
   * Filter: `dbt__Date__c >= :startDate AND dbt__Date__c <= :endDate`  
   * Filter: `dbt__Timesheet__r.dbt__Status__c IN :allowedStatuses` (default: `'Submitted'`, `'Approved'`)  
   * Filter: `dbt__Type__c != 'Absence' AND dbt__Absence_Category__c = null`  
   * Filter: `dbt__Project__c != null AND dbt__Project__r.Account__c != null`  
   * Filter: `Id NOT IN :alreadyInvoicedIds`  
   * Optional: If `onlyBillable == true`, add filter `dbt__Billable__c = true`.

### **Rule 2: Hourly Rate Resolution**

1. Query `dbt__Project_Employee__c` junction records where `dbt__Project__c IN :projectIds AND dbt__Employee__c IN :employeeIds`.  
2. Build a lookup map keyed by composite string `projectId + '_' + employeeId` pointing to `dbt__Hourly_Rate__c`.  
3. When creating an `Intermediate_Invoice_Line_Item__c`:  
   * If `dbt__Billable__c == false`: `Unit_Price__c = 0.00`.  
   * If `dbt__Billable__c == true`: `Unit_Price__c` is resolved from `dbt__Project_Employee__c.dbt__Hourly_Rate__c`. If missing or null, defaults to `0.00` and is flagged for review.

### **Rule 3: Splitting & Merging Logic**

* **Invoice Header Grouping Key:** `dbt__Project__r.Account__c`  
  * All eligible timesheet line items whose projects belong to the same Customer Account are combined under a single `Intermediate_Invoice__c` header.  
* **Invoice Line Item Merge Key:**  
  * Composite key: `dbt__Project__c + '|' + dbt__Employee__c + '|' + dbt__Activity__c + '|' + dbt__Billable__c`  
  * Grouping separates billable hours from non-billable hours even for the same employee/project to prevent rate blending.  
  * For each composite key under an Account:  
    * `Quantity__c = SUM(dbt__Duration__c)`  
    * `Source_Timesheet_Line_Items__c = String.join(listOfLineItemIds, ',')`

---

## **4. End-to-End Screen Flow & UI Architecture**

### **Entry Point: List View Button & Modal Wrapper**

* **WebLink:** `Generate_Project_Invoices` placed on `Intermediate_Invoice__c` List View.  
* **Target:** Opens `/lightning/cmp/c__GenerateProjectInvoicesWrapper` (Aura Modal Component).  
* **UX Advantage:** Opens instantly inside a centered modal overlay rather than navigating away from the list view. Upon finishing, it fires `e.force:refreshView` and closes the modal.

### **Screen 1: Filter Criteria**
* **Inputs:** Start Date, End Date, "Include Only Billable Items" checkbox.  
* **Navigation:** Next triggers `TimesheetInvoiceFetchAction`.

### **Screen 2: Review Candidate Timesheets**
* **Summary Banner:** Total eligible hours and line items count.  
* **Data Table:** Shows candidate timesheets (`Name`, `dbt__Employee__c`, `dbt__Start_Date__c`, `dbt__End_Date__c`, `dbt__Status__c`, `dbt__Total_Hours__c`).  
* **Fallback Logic:** If the user clicks Next without explicitly checking checkboxes, the engine automatically selects **all** candidate timesheets found.

### **Screen 3: Interactive Preview & Inline Edit (`invoicePreviewEditor`)**
* **LWC Architecture:** Embedded via `lightning__FlowScreen`.  
* **Header Editing:** Invoice Date, Due Date, Customer Memo per invoice card.  
* **Line Item Inline Editing:** Line Description, Quantity (Hours), and Unit Price (Hourly Rate).  
* **Live Client-Side Recalculation:** Editing Quantity or Rate instantly updates line totals and header invoice totals without round-trips to the server.  
* **Serialization:** Passes modified records to Flow via JSON string `invoicesJson` to maintain full attribute fidelity.

### **Screen 4: Confirmation & Error Fault Paths**
* **Fault Connectors:** All Apex actions are wired with `<faultConnector>` elements routing to `Screen_Error` displaying `{Cancel/Retry}` options and the detailed `{!$Flow.FaultMessage}`.  
* **Commit:** Commits intermediate invoices and line items atomically. Screen 4 provides success metrics and direct navigation links.

---

## **5. Page Layouts & Related Lists Specification**

### **A. Intermediate Invoice Layout (`Intermediate_Invoice__c-Intermediate Invoice Layout`)**

| Section | Left Column | Right Column |
| :--- | :--- | :--- |
| **Intermediate Invoice Information** | • Intermediate Invoice Number (`Name`)<br>• Account (`Account__c`)<br>• Status (`Status__c`)<br>• Total Amount (`Total_Amount__c`)<br>• Customer Email (`Customer_Email__c`) | • Owner (`OwnerId`)<br>• Intermediate Invoice Date (`Invoice_Date__c`)<br>• Due Date (`Due_Date__c`)<br>• Billing Period Start (`Billing_Period_Start__c`)<br>• Billing Period End (`Billing_Period_End__c`) |
| **Billing & Notes** | • Billing Address (`Billing_Address__c`) | • Memo (`Memo__c`) |
| **QuickBooks Integration** | • QB Invoice Id (`QB_Invoice_Id__c`) | • QB Sync Token (`QB_Sync_Token__c`) |
| **System Information** | • Created By (`CreatedById`) | • Last Modified By (`LastModifiedById`) |

* **Related Lists:**
  * **Intermediate Invoice Line Items (`Intermediate_Invoice_Line_Item__c.Intermediate_Invoice__c`)**:
    * Visible Columns: `NAME` (Line Item Number), `Line_Number__c`, `Project__c`, `Employee__c`, `Activity__c`, `Description__c`, `Quantity__c`, `Unit_Price__c`, `Amount__c`, `Billable__c`, `Service_Date__c`.

---

### **B. Intermediate Invoice Line Item Layout (`Intermediate_Invoice_Line_Item__c-Intermediate Invoice Line Item Layout`)**

| Section | Left Column | Right Column |
| :--- | :--- | :--- |
| **Line Item Information** | • Line Item Name (`Name`)<br>• Intermediate Invoice (`Intermediate_Invoice__c`)<br>• Line Number (`Line_Number__c`)<br>• Project (`Project__c`)<br>• Employee (`Employee__c`)<br>• Activity (`Activity__c`) | • Quantity / Hours (`Quantity__c`)<br>• Unit Price / Hourly Rate (`Unit_Price__c`)<br>• Amount (`Amount__c`)<br>• Billable (`Billable__c`)<br>• Service Date (`Service_Date__c`) |
| **Description & Timesheets** | • Description (`Description__c`) | • Source Timesheet Line Items (`Source_Timesheet_Line_Items__c`) |
| **QuickBooks Integration** | • QB Item Id (`QB_Item_Id__c`) | • QB Tax Code (`QB_Tax_Code__c`) |
| **System Information** | • Created By (`CreatedById`) | • Last Modified By (`LastModifiedById`) |

---

## **6. Apex Engine & Invocable Classes Architecture**

The implementation is split into a core service engine and dedicated invocable action classes:

1. **`TimesheetInvoiceEngine.cls`**:
   * `fetchEligibleData(startDate, endDate, onlyBillable, allowedStatuses, accountIdFilter)`
   * `buildPreview(selectedTimesheetIds, eligibleLineItemIds, startDate, endDate, onlyBillable, mergeKeyFields, dueDaysOffset, descriptionTemplate)`
   * `commitInvoices(invoicesToInsert, lineItemsToInsert)`
   * `commitInvoicesFromJson(invoicesJson)`
   * `getAlreadyInvoicedLineItemIds()`
2. **`TimesheetInvoiceFetchAction.cls`**: `@InvocableMethod` wrapper for Flow Step 1.
3. **`TimesheetInvoicePreviewAction.cls`**: `@InvocableMethod` wrapper for Flow Step 2.
4. **`TimesheetInvoiceCommitAction.cls`**: `@InvocableMethod` wrapper for Flow Step 3 with `Database.setSavepoint()` rollback guarantee.
5. **`TimesheetInvoiceEngineTest.cls`**: Comprehensive unit test suite covering end-to-end multi-project conversion, rate fallback, empty timesheet selection, and JSON commit flows.

---

## **7. Critical Architecture Guardrails & Lessons Learned**

1. **Flow Invocable SObject Relationship Deserialization Restriction:**
   * *Issue:* Salesforce Flow throws `A field wasn't found or isn't supported for Apex action...` if an `@InvocableMethod` returns `List<SObject>` containing queried parent/child relationship fields (e.g., `dbt__Employee__r.Name`).
   * *Resolution:* SOQL queries populating SObject collections for Flow must query only direct fields on the object itself.
2. **Flow Screen Navigation Button Configuration:**
   * *Issue:* In Salesforce Flow metadata, screen progression is controlled exclusively by `<allowFinish>` and `<allowBack>`. Setting `allowFinish=false` removes the "Next" button on intermediate screens.
   * *Resolution:* Intermediate screens must have `<allowFinish>true</allowFinish>` to render the "Next" button.
3. **Aura Modal Initialization Timing:**
   * *Issue:* Calling `flow.startFlow()` synchronously in Aura's `init` controller before the DOM finishes mounting can cause client-side rendering exceptions.
   * *Resolution:* Wrap the call inside `window.setTimeout($A.getCallback(...), 0)`.
4. **SOQL Long Text Area Query Restriction:**
   * *Issue:* Salesforce disallows filtering on Long Text Area fields in SOQL `WHERE` clauses (`Source_Timesheet_Line_Items__c != null`).
   * *Resolution:* Query the field without the filter and check `String.isNotBlank(ili.Source_Timesheet_Line_Items__c)` in memory.

---

## **8. Verification & Test Matrix**

* **Unit Test Coverage:** 91% code coverage with 100% test pass rate (5/5 methods passing).
* **Multi-Scenario Sandbox Verification (`sb1`):**
  * `INV-00001` ($5,400.00): Multi-employee consolidation across 3 employees on Billable Project.
  * `INV-00002` ($14,625.00): High-volume multi-project consolidation (3 separate hourly rates: $200, $175, $125).
  * `INV-00003` ($4,800.00): Legacy and ESN multi-project consolidation under single Account.
  * `INV-00004` ($15,000.00): Live UI Flow execution verifying interactive Preview Editor, inline edits, and automatic creation of 5 `Intermediate_Invoice_Line_Item__c` records.
  * **Deduplication Verification:** Running subsequent runs for overlapping date windows verified 0 duplicate line items created.
