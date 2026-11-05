# **Technical Architecture Document: Timesheet-to-Invoice Conversion Engine**

## **1\. Executive Summary & Architectural Pattern**

* **Objective:** Split and merge approved/submitted dbt\_\_Timesheet\_Line\_Item\_\_c records across multiple employees and projects into customer-facing Intermediate_Invoice__c and Intermediate_Invoice_Line_Item__c records aligned with the QuickBooks Online (QBO) Invoice API structure.  
* **Deployment Model:** Direct implementation inside the target Salesforce org (unmanaged custom objects, fields, Flow, and Apex referencing the installed dbt\_\_ package objects).  
* **Selected Architecture (Option A):** **Screen Flow Orchestrator \+ Invocable Apex Calculation Engine (In-Memory Preview & Commit)**.  
  * **Screen Flow** manages the 3-step wizard UI, user inputs (date range, billable toggle), default field mappings, and configurable grouping parameters.  
  * **Invocable Apex** performs high-volume querying, deduplication against previously invoiced line items, rate resolution from dbt\_\_Project\_Employee\_\_c, multi-key aggregation, and atomic parent-child DML creation.

```
[Intermediate_Invoice__c List View Button]
       │
       ▼
[Screen 1: Filter Criteria] ──(Start/End Date, Only Billable Checkbox)
       │
       ▼
[Apex Action 1: Fetch Eligible Timesheets & Line Items]
  - Filters by Line Item Date & Timesheet Status (Submitted/Approved)
  - Excludes Absences & already-invoiced Line Item IDs
       │
       ▼
[Screen 2: Review Candidate Timesheets / Line Items]
  - User selects/confirms Timesheets to process
  - Excludes Absences & already-invoiced Line Item IDs
       │
       ▼
[Apex Action 2: Generate In-Memory Invoice Preview]
  - Groups Header by: dbt__Project__r.Account__c
  - Merges Lines by: Project + Employee + Activity + Billable
  - Resolves Rate from: dbt__Project_Employee__c.dbt__Hourly_Rate__c (or 0 if Non-Billable)
       │
       ▼
[Screen 3: Preview & Inline Edit Invoices]
  - Displays proposed Invoices & Line Items
  - Allows basic inline edits (Dates, Memo, Description, Hours, Rate)
       │
       ▼
[Apex Action 3: Commit Invoices & Line Items]
  - Inserts Intermediate_Invoice__c headers
  - Links & inserts Intermediate_Invoice_Line_Item__c records with comma-separated Source IDs
```

## **2\. QBO-Aligned Data Model (No-Table Format)**

### **A. Existing Object Modifications**

**1\. Project (dbt\_\_Project\_\_c)**

* **Field Label:** Account (Account\_\_c)  
* **Data Type:** Lookup (Account)  
* **Purpose & QBO Mapping:** Links a project to the customer Account. Maps to QBO Invoice.CustomerRef. Every project under the same Account\_\_c rolls into a single combined Intermediate_Invoice__c header for that billing run.

### **B. New Custom Object 1: Intermediate Invoice (Intermediate_Invoice__c)**

Represents the QBO Invoice header entity. One record is created per unique dbt\_\_Project\_\_r.Account\_\_c.

* **Name (Invoice Number)**  
  * **Type:** Auto-Number (INV-{00000})  
  * **QBO Equivalent:** DocNumber  
  * **Mapping / Default:** System-generated upon insert.  
* **Account\_\_c (Customer)**  
  * **Type:** Lookup (Account) — Required  
  * **QBO Equivalent:** CustomerRef.value & CustomerRef.name  
  * **Mapping / Default:** Populated from dbt\_\_Project\_\_r.Account\_\_c.  
* **Invoice\_Date\_\_c (Transaction Date)**  
  * **Type:** Date  
  * **QBO Equivalent:** TxnDate  
  * **Mapping / Default:** Defaults to TODAY() in Flow; **inline-editable** on Preview Screen.  
* **Due\_Date\_\_c (Due Date)**  
  * **Type:** Date  
  * **QBO Equivalent:** DueDate  
  * **Mapping / Default:** Defaults to TODAY() \+ 30 (configurable in Flow); **inline-editable** on Preview Screen.  
* **Billing\_Period\_Start\_\_c & Billing\_Period\_End\_\_c**  
  * **Type:** Date  
  * **QBO Equivalent:** Custom metadata / PrivateNote context  
  * **Mapping / Default:** Populated from the Start Date and End Date selected on Screen 1\.  
* **Status\_\_c**  
  * **Type:** Picklist (Draft, Confirmed, Synced to QBO, Void)  
  * **QBO Equivalent:** Invoice lifecycle state  
  * **Mapping / Default:** Set to Confirmed when created via the wizard (or Draft if configured).  
* **Customer\_Email\_\_c**  
  * **Type:** Email  
  * **QBO Equivalent:** BillEmail.Address  
  * **Mapping / Default:** Defaulted from Account primary email/contact if available; **inline-editable**.  
* **Billing\_Address\_\_c**  
  * **Type:** Long Text Area (or Address compound fields)  
  * **QBO Equivalent:** BillAddr (Line1, City, CountrySubDivisionCode, PostalCode)  
  * **Mapping / Default:** Copied from Account.BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry.  
* **Memo\_\_c (Customer Memo)**  
  * **Type:** Text Area (1000)  
  * **QBO Equivalent:** CustomerMemo.value  
  * **Mapping / Default:** Configurable default template in Flow; **inline-editable** on Preview Screen.  
* **Total\_Amount\_\_c**  
  * **Type:** Roll-Up Summary (SUM of Intermediate_Invoice_Line_Item__c.Amount\_\_c)  
  * **QBO Equivalent:** TotalAmt  
  * **Mapping / Default:** Automatically sums all child line items.  
* **QB\_Invoice\_Id\_\_c & QB\_Sync\_Token\_\_c**  
  * **Type:** Text (50) — External ID (QB\_Invoice\_Id\_\_c)  
  * **QBO Equivalent:** Id and SyncToken  
  * **Mapping / Default:** Populated later when synced with QuickBooks Online.

### **C. New Custom Object 2: Intermediate Invoice Line Item (Intermediate_Invoice_Line_Item__c)**

Represents an element in the QBO Invoice.Line\[\] array where DetailType \= "SalesItemLineDetail".

* **Intermediate_Invoice__c**  
  * **Type:** Master-Detail (Intermediate_Invoice__c)  
  * **QBO Equivalent:** Parent Invoice container  
  * **Mapping / Default:** Links the line item to its parent Intermediate_Invoice__c.  
* **Line\_Number\_\_c**  
  * **Type:** Number (4, 0\)  
  * **QBO Equivalent:** Line.LineNum  
  * **Mapping / Default:** Sequential integer (1, 2, 3...) per invoice.  
* **Project\_\_c**  
  * **Type:** Lookup (dbt\_\_Project\_\_c)  
  * **QBO Equivalent:** SalesItemLineDetail.ClassRef or ItemRef context  
  * **Mapping / Default:** Populated from the merge group's dbt\_\_Project\_\_c.  
* **Employee\_\_c**  
  * **Type:** Lookup (dbt\_\_Employee\_\_c)  
  * **QBO Equivalent:** Line metadata / resource tracking  
  * **Mapping / Default:** Populated from the merge group's dbt\_\_Employee\_\_c.  
* **Activity\_\_c**  
  * **Type:** Text (255)  
  * **QBO Equivalent:** SalesItemLineDetail.ItemRef.name  
  * **Mapping / Default:** Populated from dbt\_\_Timesheet\_Line\_Item\_\_c.dbt\_\_Activity\_\_c.  
* **Description\_\_c**  
  * **Type:** Long Text Area (4000)  
  * **QBO Equivalent:** Line.Description  
  * **Mapping / Default:** Auto-formatted via Flow template (default: {Project Name} \- {Employee Name} \- {Activity}); **inline-editable** on Preview Screen.  
* **Quantity\_\_c (Total Hours)**  
  * **Type:** Number (10, 2\)  
  * **QBO Equivalent:** SalesItemLineDetail.Qty  
  * **Mapping / Default:** SUM(dbt\_\_Duration\_\_c) of all merged timesheet line items; **inline-editable** on Preview Screen.  
* **Unit\_Price\_\_c (Hourly Rate)**  
  * **Type:** Currency (16, 2\)  
  * **QBO Equivalent:** SalesItemLineDetail.UnitPrice  
  * **Mapping / Default:** Fetched from dbt\_\_Project\_Employee\_\_c.dbt\_\_Hourly\_Rate\_\_c if Billable \= true, or 0.00 if Billable \= false; **inline-editable** on Preview Screen.  
* **Amount\_\_c (Line Total)**  
  * **Type:** Formula (Currency): Quantity\_\_c \* Unit\_Price\_\_c  
  * **QBO Equivalent:** Line.Amount  
  * **Mapping / Default:** Automatically calculated.  
* **Billable\_\_c**  
  * **Type:** Checkbox  
  * **QBO Equivalent:** Internal tracking / \$0 line indicator  
  * **Mapping / Default:** Matches the merge group's dbt\_\_Billable\_\_c value.  
* **Service\_Date\_\_c**  
  * **Type:** Date  
  * **QBO Equivalent:** SalesItemLineDetail.ServiceDate  
  * **Mapping / Default:** Latest dbt\_\_Date\_\_c among the merged timesheet line items (or Billing Period End Date).  
* **QB\_Item\_Id\_\_c & QB\_Tax\_Code\_\_c**  
  * **Type:** Text (50)  
  * **QBO Equivalent:** SalesItemLineDetail.ItemRef.value & TaxCodeRef.value  
  * **Mapping / Default:** Optional default QBO Service Item ID passed from Flow.  
* **Source\_Timesheet\_Line\_Items\_\_c (Traceability & Deduplication Field)**  
  * **Type:** Long Text Area (131,072 characters)  
  * **QBO Equivalent:** Internal Salesforce audit trail  
  * **Mapping / Default:** Comma-separated list of 18-character dbt\_\_Timesheet\_Line\_Item\_\_c IDs (e.g., a03xx000001abcAAA,a03xx000001abdAAA). At 19 characters per ID, a single line item can store over 6,800 source IDs without touching locked timesheet records.

## **3\. Core Business Logic & Rules**

### **Rule 1: Candidate Timesheet Line Item Selection & Deduplication**

Because submitted timesheets are locked and unmodifiable, we do not perform DML updates on dbt\_\_Timesheet\_Line\_Item\_\_c. Instead, deduplication works in two steps inside Apex:

> 1. **Collect Already-Invoiced Line Item IDs:**  
   * Query existing Intermediate_Invoice_Line_Item__c records where Invoice\_\_r.Status\_\_c \!= 'Void' (scoped to the relevant Accounts/Projects or recent periods).  
   * Parse every comma-separated ID in Source\_Timesheet\_Line\_Items\_\_c into an in-memory Set\<Id\> alreadyInvoicedIds.  
> 2. **Fetch Eligible dbt\_\_Timesheet\_Line\_Item\_\_c Records:**  
   * dbt\_\_Date\_\_c \>= :startDate AND dbt\_\_Date\_\_c \<= :endDate  
   * dbt\_\_Timesheet\_\_r.dbt\_\_Status\_\_c IN :allowedStatuses (Configurable in Flow; default: Submitted, Approved)  
   * dbt\_\_Type\_\_c \!= 'Absence' AND dbt\_\_Absence\_Category\_\_c \= null  
   * dbt\_\_Project\_\_c \!= null AND dbt\_\_Project\_\_r.Account\_\_c \!= null  
   * Id NOT IN :alreadyInvoicedIds  
   * If onlyBillable \== true: add filter dbt\_\_Billable\_\_c \= true.

### **Rule 2: Hourly Rate Resolution**

* Query dbt\_\_Project\_Employee\_\_c records where dbt\_\_Project\_\_c IN :projectIds AND dbt\_\_Employee\_\_c IN :employeeIds.  
* Build a lookup map keyed by String rateKey \= projectId \+ '\_' \+ employeeId pointing to dbt\_\_Hourly\_Rate\_\_c.  
* When building an Intermediate_Invoice_Line_Item__c:  
  * If dbt\_\_Billable\_\_c \== false: set Unit\_Price\_\_c \= 0.00.  
  * If dbt\_\_Billable\_\_c \== true: set Unit\_Price\_\_c to the matched dbt\_\_Project\_Employee\_\_c.dbt\_\_Hourly\_Rate\_\_c (defaulting to 0.00 if no junction record exists).

### **Rule 3: Splitting & Merging Logic**

* **Invoice Header Grouping Key:** dbt\_\_Project\_\_r.Account\_\_c  
  * All eligible timesheet line items whose projects belong to the same Customer Account are grouped under a single Intermediate_Invoice__c header.  
* **Invoice Line Item Merge Key (Option 2A):**  
  * Default composite key: dbt\_\_Project\_\_c \+ '\|' \+ dbt\_\_Employee\_\_c \+ '\|' \+ dbt\_\_Activity\_\_c \+ '\|' \+ dbt\_\_Billable\_\_c  
  * *(Note: Including dbt\_\_Billable\_\_c in the composite key ensures that if "Include Only Billable" is unchecked, billable hours at full rate and non-billable hours at \$0 rate for the same employee and activity remain on separate invoice lines rather than blending rates).*  
  * For each unique composite key under an Account:  
    * Quantity\_\_c \= Sum of dbt\_\_Duration\_\_c  
    * Source\_Timesheet\_Line\_Items\_\_c \= String.join(listOfLineItemIds, ',')

## **4\. End-to-End Screen Flow & UI Design**

### **Entry Point: List View Button on Intermediate_Invoice__c**

* **Button Type:** List Button (Display Checkboxes \= False) placed on the Intermediate_Invoice__c List View layout.  
* **URL Target:** /flow/Generate\_Project\_Invoices?retURL=/lightning/o/Intermediate_Invoice__c/list

### **Screen 1: Period & Filter Selection**

* **Period Quick-Select (Radio Buttons / Picklist):**  
  * This Week (Flow formula calculates current week's Monday to Sunday)  
  * This Month (Flow formula calculates 1st of current month to last day of current month)  
  * Custom Date Range (Reveals Start Date and End Date inputs via Conditional Visibility)  
* **Date Inputs:**  
  * Start\_Date (Date, required)  
  * End\_Date (Date, required)  
* **Billable Toggle:**  
  * Only\_Billable\_Items (Checkbox, Default \= True, Label: *"Include Only Billable Timesheet Items (Uncheck to include non-billable items at \$0 rate)"*)  
* **Optional Filter (Admin-extensible):**  
  * Customer\_Account (Optional Lookup to Account if the user only wants to generate invoices for one customer).

### **Action 1: Invocable Apex — TimesheetInvoiceController.fetchEligibleTimesheets**

* **Inputs from Flow:**  
  * startDate (Date)  
  * endDate (Date)  
  * onlyBillable (Boolean)  
  * allowedStatuses (List of Strings — defaulted in Flow to \['Submitted', 'Approved'\])  
  * accountIdFilter (Id, optional)  
* **Outputs to Flow:**  
  * eligibleTimesheets (List\<dbt\_\_Timesheet\_\_c\> — distinct parent timesheets that have eligible un-invoiced line items in the date range, for display on Screen 2\)  
  * eligibleLineItemIds (List\<String\> — exact IDs of the eligible dbt\_\_Timesheet\_Line\_Item\_\_c records within that date window)  
  * totalEligibleHours (Decimal)  
  * totalLineItemCount (Integer)

### **Screen 2: Found Timesheets Review**

* **Summary Banner (Display Text):** Shows total eligible dbt\_\_Timesheet\_\_c records found, total eligible line items falling within \[Start\_Date\] – \[End\_Date\], and total hours.  
* **Data Table (Standard Flow Data Table Component):**  
  * Displays eligibleTimesheets with columns: Name, dbt\_\_Employee\_\_r.Name, dbt\_\_Start\_Date\_\_c, dbt\_\_End\_Date\_\_c, dbt\_\_Status\_\_c, dbt\_\_Total\_Hours\_\_c.  
  * Selection Mode: Multiple (Pre-selects all rows by default so the user can optionally deselect specific timesheets they want to hold back).  
* **Navigation Button:** "Create Invoice Preview" (Next).

### **Action 2: Invocable Apex — TimesheetInvoiceController.generateInvoicePreview**

* **Inputs from Flow (Admin-Configurable Mappings & Rules):**  
  * selectedTimesheetIds (List\<Id\> from Screen 2 Data Table)  
  * eligibleLineItemIds (List\<String\> from Action 1\)  
  * startDate & endDate (Date)  
  * onlyBillable (Boolean)  
  * mergeKeyFields (String — defaulted in Flow to 'dbt\_\_Project\_\_c,dbt\_\_Employee\_\_c,dbt\_\_Activity\_\_c,dbt\_\_Billable\_\_c')  
  * defaultInvoiceStatus (String — defaulted in Flow to 'Confirmed')  
  * defaultPaymentTermsDays (Integer — defaulted in Flow to 30\)  
  * lineDescriptionTemplate (String — defaulted in Flow to '{Project} \- {Employee} ({Activity})')  
* **Outputs to Flow:**  
  * previewInvoices (List\<Intermediate_Invoice__c\> — in-memory records, no Id yet)  
  * previewLineItems (List\<Intermediate_Invoice_Line_Item__c\> — in-memory records linked to their parent invoice via a temporary correlation field Account\_Id\_Key\_\_c or Project\_\_r.Account\_\_c)

### **Screen 3: "Would-Be Created" Invoice Preview & Inline Edit**

To support viewing each proposed Invoice alongside its child Line Items AND allowing limited inline editing before DML insert, you have two clean implementation options in Screen 3:

* **Approach 3A (Standard Flow Repeater \+ Standard Flow Data Table — Zero Custom LWC Code):**  
  * Use a **Flow Screen section** iterating or displaying the previewInvoices Data Table at the top, and previewLineItems below, OR  
* **Approach 3B (Lightweight Embedded LWC invoicePreviewEditor inside the Flow Screen — Recommended for Inline Editing):**  
  * Because standard Flow Data Tables do not natively support inline editing of in-memory records with instant live recalculation of Amount \= Quantity \* Unit\_Price, a single compact LWC embedded in Screen 3 gives a clean accordion view per Customer Account.  
  * **Editable Header Fields (per Invoice Card):**  
    * Invoice\_Date\_\_c (Date picker)  
    * Due\_Date\_\_c (Date picker)  
    * Memo\_\_c (Text input)  
  * **Read-Only Header Fields:**  
    * Customer Account Name, Billing Period, Live Calculated Invoice Total.  
  * **Editable Line Item Columns (in lightning-datatable per Invoice):**  
    * Description\_\_c (Text)  
    * Quantity\_\_c (Number \- Hours)  
    * Unit\_Price\_\_c (Currency \- Rate)  
  * **Read-Only Line Item Columns:**  
    * Project Name, Employee Name, Activity, Billable Checkbox, Calculated Amount (Quantity \* Unit\_Price), Count of merged Timesheet entries.  
* **Navigation Button:** "Confirm & Create Invoices".

### **Action 3: Invocable Apex — TimesheetInvoiceController.commitInvoices**

*(Or standard Flow Create Records if using correlation mapping)*

* **Why an Invocable Commit Action is safest:**  
  * Takes the (potentially inline-edited) previewInvoices and previewLineItems from Screen 3\.  
  * Wraps the transaction in a Database.setSavepoint().  
  * Inserts List\<Intermediate_Invoice__c\>.  
  * Maps each inserted Intermediate_Invoice__c.Account\_\_c to its new Intermediate_Invoice__c.Id.  
  * Populates Intermediate_Invoice_Line_Item__c.Intermediate_Invoice__c on every child record and inserts List\<Intermediate_Invoice_Line_Item__c\>.  
  * Returns the created List\<Intermediate_Invoice__c\> IDs to display a final Confirmation Screen with direct links to the newly created invoices.

## **5\. Admin Configurability Design (Flow-Driven Customization)**

To fulfill your requirement that **default mappings, merge conditions, and field values can be modified later in Flow without rewriting the core engine**, the architecture separates **policy (Flow)** from **execution (Apex)**:

> 1. **Configurable Merge Keys via Flow Constant:**  
   * The Flow holds a text constant varMergeKeyFields \= "dbt\_\_Project\_\_c,dbt\_\_Employee\_\_c,dbt\_\_Activity\_\_c,dbt\_\_Billable\_\_c".  
   * In Apex, the grouping key is built dynamically using SObject.get(fieldName.trim()) by splitting varMergeKeyFields on commas.  
   * If an admin later wants to merge only by dbt\_\_Project\_\_c,dbt\_\_Activity\_\_c (combining all employees into one line), they simply remove dbt\_\_Employee\_\_c from the Flow constant—no Apex code change required.  
> 2. **Configurable Line Item Description Template:**  
   * The Flow passes varDescriptionTemplate \= "{Project} \| {Employee} \- {Activity}".  
   * Admins can change this string in Flow Builder to adjust how Intermediate_Invoice_Line_Item__c.Description\_\_c formats for QuickBooks.  
> 3. **Configurable Post-Processing in Flow:**  
   * Because previewInvoices and previewLineItems are real Salesforce SObject collections (List\<Intermediate_Invoice__c\> and List\<Intermediate_Invoice_Line_Item__c\>) exposed in the Flow, an admin can insert a standard Flow **Loop** or **Transform** element right after generateInvoicePreview (or before commitInvoices) to map additional custom fields on Intermediate_Invoice__c or Intermediate_Invoice_Line_Item__c using Flow Builder assignments.

## **6\. Apex Engine Blueprint (Structure & Signatures)**

Below is the structural blueprint for the Apex engine (TimesheetInvoiceEngine.cls) showing how dynamic merge keys, comma-separated ID deduplication, and dbt\_\_Project\_Employee\_\_c rate resolution work together:  
Apex Blueprint:

```java
public with sharing class TimesheetInvoiceEngine {

    // Wrapper for Flow Step 2 (Preview Generation)
    public class PreviewRequest {
        @InvocableVariable(required=true label='Selected Timesheet IDs')
        public List<Id> selectedTimesheetIds;

        @InvocableVariable(required=true label='Start Date')
        public Date startDate;

        @InvocableVariable(required=true label='End Date')
        public Date endDate;

        @InvocableVariable(required=true label='Only Billable Items')
        public Boolean onlyBillable;

        @InvocableVariable(label='Comma-Separated Merge Key Fields on Timesheet Line Item')
        public String mergeKeyFields; // Default: dbt__Project__c,dbt__Employee__c,dbt__Activity__c,dbt__Billable__c

        @InvocableVariable(label='Default Due Date Offset (Days)')
        public Integer dueDaysOffset; // Default: 30

        @InvocableVariable(label='Line Description Template')
        public String descriptionTemplate; // Default: {Project} - {Employee} - {Activity}
    }

    public class PreviewResponse {
        @InvocableVariable(label='Preview Invoices')
        public List<Intermediate_Invoice__c> previewInvoices;

        @InvocableVariable(label='Preview Invoice Line Items')
        public List<Intermediate_Invoice_Line_Item__c> previewLineItems;
    }

    // Helper method to extract all already-invoiced Timesheet Line Item IDs
    public static Set<Id> getAlreadyInvoicedLineItemIds() {
        Set<Id> invoicedIds = new Set<Id>();
        for (Intermediate_Invoice_Line_Item__c ili : [
            SELECT Source_Timesheet_Line_Items__c
            FROM Intermediate_Invoice_Line_Item__c
            WHERE Invoice__r.Status__c != 'Void'
              AND Source_Timesheet_Line_Items__c != null
        ]) {
            for (String rawId : ili.Source_Timesheet_Line_Items__c.split(',')) {
                String cleanId = rawId.trim();
                if (String.isNotBlank(cleanId)) {
                    invoicedIds.add((Id)cleanId);
                }
            }
        }
        return invoicedIds;
    }

    // Dynamic Composite Key Builder for Merging Line Items
    private static String buildCompositeMergeKey(
        dbt__Timesheet_Line_Item__c tli,
        List<String> keyFieldNames
    ) {
        List<String> keyParts = new List<String>();
        for (String fieldName : keyFieldNames) {
            Object val = tli.get(fieldName.trim());
            keyParts.add(val != null ? String.valueOf(val) : 'NULL');
        }
        return String.join(keyParts, '|');
    }
}
```

## **7\. Governor Limits, Error Handling & Edge Cases**

* **Projects Missing an Account Lookup (dbt\_\_Project\_\_c.Account\_\_c \== null):**  
  * Line items logged against internal projects without an Account\_\_c are automatically excluded from customer invoicing (or surfaced as a warning message on Screen 2 so the user knows why those hours were skipped).  
* **Missing dbt\_\_Project\_Employee\_\_c Rate Record:**  
  * If an employee logs billable time on a project where no dbt\_\_Project\_Employee\_\_c record exists (or dbt\_\_Hourly\_Rate\_\_c is null), the engine defaults Unit\_Price\_\_c to 0.00 and flags the description/preview so the user can manually enter the rate via inline edit on Screen 3\.  
* **Partial Timesheet Invoicing across Month Boundaries:**  
  * Because filtering and deduplication happen at the **dbt\_\_Timesheet\_Line\_Item\_\_c** level (using dbt\_\_Date\_\_c and Source\_Timesheet\_Line\_Items\_\_c), a weekly timesheet spanning Oct 29 – Nov 4 will safely bill Oct 29 – Oct 31 in the October invoice run, and the remaining Nov 1 – Nov 4 line items will automatically remain eligible for the November invoice run.  
* **Transaction Atomicity:**  
  * In the final Commit step, if inserting any Intermediate_Invoice__c or Intermediate_Invoice_Line_Item__c fails validation, Database.rollback(sp) reverts the entire batch cleanly and displays the exact error message inside the Flow screen.
