# Salesforce Scratch Org Metadata Retrieval: Troubleshooting & Runbook

This guide documents the root causes, architecture limitations, and step-by-step resolution workflows for issues encountered when retrieving changes from Salesforce Scratch Orgs (specifically namespaced developer scratch orgs) into a local Salesforce DX project.

---

## 1. Executive Summary & Root Cause Analysis

When developers make changes in a Salesforce Scratch Org (via Developer Console, Flow Builder, or Lightning App Builder), attempting to retrieve them via VS Code (*"SFDX: Retrieve Source from Org"* / *"SFDX: Pull Source from Default Scratch Org"*) or CLI (`sf project retrieve start`) frequently fails with errors such as:

* `Error (1): There are changes in your local files that conflict with the org changes you're trying to retrieve.`
* `» Warning: Nothing retrieved`
* Silent failures or indefinite command hangs in terminal/VS Code on Windows.

Even passing `--ignore-conflicts` (`-c`) often still yields `» Warning: Nothing retrieved` or hangs. The five underlying causes are detailed below.

---

### Root Cause 1: Temporary Session Links vs Local CLI Authentication
* **Issue**: Developers often open scratch orgs using temporary browser session URLs:
  `https://<mydomain>.scratch.my.salesforce.com/secur/frontdoor.jsp?sid=<session_id>`
* **Mechanism**: The `frontdoor.jsp` link allows browser access via a temporary bearer token (`sid`), but **does not create an OAuth token or connection record** in the local machine's Salesforce CLI (`sf` / `sfdx`) or VS Code.
* **Symptom**: `sf config get target-org` is blank, and `sf org list` does not list the scratch org. Any retrieve command either fails with `"No default org set"` or silently retrieves against the wrong org.

---

### Root Cause 2: `SourceMember.RevisionNum = null` in Namespaced Scratch Orgs
* **Issue**: The Salesforce DX source tracking mechanism breaks when code is modified in Developer Console or Setup within a namespaced org.
* **Mechanism**:
  * In a project configured with `"namespace": "dbt"`, the scratch org carries the namespace prefix.
  * When Apex classes or Flows are modified or activated directly in the web UI, Salesforce's Tooling API `SourceMember` table frequently records `RevisionNum = null`.
  * VS Code and `sf project retrieve start` query `SourceMember` where `RevisionNum > local_revision` to generate the list of files to pull.
  * Because `RevisionNum` is `null`, Salesforce calculates the change set as **0 components**.
* **Symptom**: Even when `--ignore-conflicts` is enabled, the CLI prepares the request, sees 0 remote revisions, and terminates with `» Warning: Nothing retrieved` without updating local files.

---

### Root Cause 3: Namespace Prefix Injection in Flows (`dbt__` vs Local)
* **Issue**: Flow Builder automatically hardcodes namespace prefixes into field and relationship references.
* **Mechanism**:
  * When saving a Flow in a namespaced scratch org, Flow Builder converts references like `Employee__r.Email__c` into `dbt__Employee__r.dbt__Email__c`.
  * In local DX source format (`"namespace": "dbt"` in `sfdx-project.json`), files are stored **unprefixed** (packaging injects prefixes at compile time).
  * During a source retrieve, the Source-Deploy-Retrieve (SDR) parser detects a structural mismatch between the incoming XML and the local XML, causing conflict errors or XML parsing failures.

---

### Root Cause 4: Duplicate `packageDirectories` Paths in `sfdx-project.json`
* **Issue**: Multiple package definitions pointing to the same folder path.
* **Example**:
  ```json
  "packageDirectories": [
    {
      "path": "Timesheet",
      "package": "Timesheet",
      "default": true
    },
    {
      "path": "Timesheet",
      "package": "TimesheetUnlocked",
      "default": false
    }
  ]
  ```
* **Mechanism**: Salesforce CLI uses `packageDirectories` paths to resolve where retrieved source files should be unpacked. Having identical `path: "Timesheet"` entries triggers ambiguity in SDR file-decomposition routines, causing CLI retrieval to hang or loop indefinitely on Windows.

---

### Root Cause 5: LWC Web UI Misconception vs FlexiPage Updates
* **Issue**: Developers make changes to an LWC's configuration on a record page and attempt to retrieve the LWC bundle.
* **Mechanism**:
  * Lightning Web Components (LWC) **cannot be edited in the browser** (Developer Console only supports Apex, Aura, and Visualforce).
  * Any layout changes, tab reorganizations, dynamic related lists, or component property adjustments made in Lightning App Builder live in the **FlexiPage** metadata (`*.flexipage-meta.xml`), **not** in the LWC bundle folder (`/lwc/*`).
  * Right-clicking the LWC folder in VS Code to retrieve will find no differences in the cloud.

---

## 2. Emergency Retrieval Runbook (The Bulletproof Bypass)

When standard VS Code pull or CLI retrieve fails or hangs, use this foolproof workflow that bypasses `SourceMember` tracking completely via the Metadata API (SOAP) and converts the metadata back to DX source format.

### Step 1: Connect the Org Locally via Access Token
If you only have a `frontdoor.jsp?sid=...` URL:
1. Extract the `<session_id>` (everything after `sid=`) and `<instance_url>` (e.g. `https://<org-name>.scratch.my.salesforce.com`).
2. Run in terminal:
```powershell
$env:SF_ACCESS_TOKEN = "<session_id>"
sf org login access-token --instance-url <instance_url> --alias scratch-org --no-prompt
sf config set target-org=scratch-org
```

---

### Step 2: Create a Dedicated Manifest (`package.xml`)
Create a manifest file containing the exact components you modified (e.g., `manifest/retrieve-manual.xml`):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<Package xmlns="http://soap.sforce.com/2006/04/metadata">
    <types>
        <members>TimesheetTimerNotificationService</members>
        <name>ApexClass</name>
    </types>
    <types>
        <members>Timesheet_Remainder_STF</members>
        <members>Timesheet_Submission_Follow_up_Email</members>
        <members>Deactivating_employees_and_users</members>
        <members>Deactivating_inactive_employee_user</members>
        <members>Absence_management_STF</members>
        <members>Timesheet_Timer_Notification</members>
        <name>Flow</name>
    </types>
    <types>
        <members>Employee_Lightning_Record_Page</members>
        <name>FlexiPage</name>
    </types>
    <types>
        <members>Employee__c-Employee Layout</members>
        <name>Layout</name>
    </types>
    <version>60.0</version>
</Package>
```

---

### Step 3: Retrieve in Metadata Format and Convert to DX Source Format
Bypass source tracking conflicts by retrieving directly into a temporary folder and converting:

```powershell
# 1. Clean temporary directories
Remove-Item -Recurse -Force "$env:TEMP\sf_meta", "$env:TEMP\converted_source" -ErrorAction SilentlyContinue

# 2. Retrieve metadata into a ZIP and unzip it
sf project retrieve start -o scratch-org --manifest manifest/retrieve-manual.xml --target-metadata-dir "$env:TEMP\sf_meta" --unzip

# 3. Convert MDAPI format to DX Source format
sf project convert mdapi --root-dir "$env:TEMP\sf_meta\unpackaged" --output-dir "$env:TEMP\converted_source"

# 4. Copy converted source into your package directory
Copy-Item -Path "$env:TEMP\converted_source\main\default\*" -Destination "Timesheet\main\default" -Recurse -Force
```

---

### Step 4: Verify with Git
Check the exact changes applied:
```powershell
git diff --stat
git status
```

---

## 3. How to Prevent These Issues Going Forward

1. **Local-First Development for Apex & LWC**:
   * Always write and modify Apex and LWC in VS Code, then deploy to the scratch org using:
     ```powershell
     sf project deploy start --source-dir Timesheet/main/default/classes/MyClass.cls
     ```
   * Avoid making code edits in the browser's Developer Console, as this avoids corrupting `SourceMember` tracking in namespaced orgs.

2. **Fix Duplicate Package Paths**:
   * Review `sfdx-project.json` and ensure no two package directories share the exact same `"path"`. If multiple package definitions are required for packaging scripts, point development to a single active directory or distinguish sub-paths.

3. **Resetting Source Tracking when Desynced**:
   * If local tracking gets out of sync with remote org revisions, reset the local revision cache:
     ```powershell
     sf project reset tracking -o <org_alias> -p
     ```

4. **Remember FlexiPages when modifying LWC Placement**:
   * When dragging LWCs, modifying visibility rules, or editing record page tabs in Lightning App Builder, always retrieve the **FlexiPage** (`sf project retrieve start -m FlexiPage:<RecordPageName>`), not just the LWC bundle.
