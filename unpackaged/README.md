# Leave Approval Process and PTO emails (not packaged)

Approval processes can't ship in the managed package, so this folder holds the Leave Approval process and the
email alerts it uses. The PTO email templates (folder **PTO Emails**) are in the package. Deploy this folder once
per org, after installing the package:

```
sf project deploy start --metadata-dir unpackaged -o <org alias>
```

Names carry the package namespace (`dbt__`), so the same files deploy to subscriber orgs and to the namespaced
development org. The folder is listed in `.forceignore`, so packaging and source deploys skip it.

## Emails

| When | To | Template | Sent by |
|---|---|---|---|
| Request submitted | Approver (`Approver__c`, the employee's manager) | PTO: Approval Request | Approval process assignment email |
| Request submitted | Employee (request owner) | PTO: Request Submitted | Alert `PTO_Request_Submitted` (initial submission) |
| Request approved | Employee (request owner) | PTO: Request Approved | Alert `PTO_Request_Approved` (final approval) |
| Request rejected | Employee (request owner) | PTO: Request Rejected | Alert `PTO_Request_Rejected` (final rejection) |

- The alerts are sent as the current user: the employee (or whoever submitted) on submit, the approver on approve
  or reject. Nothing to configure.
- The approval and rejection emails show Decision Notes (who decided, when, and the rejection reason). The request
  trigger stamps it in the same save as the status change, so it is filled in before the alert goes out.
- Every email links to the request in the PTO tab (field `PTO_Tab_Link__c`): the approver's email opens the
  Approve section, the employee's emails open Past. Approving by email reply is not set up.

## How it works with the PTO tab

- `PTO_Request__c.Leave_Approval`: entry Status = Submitted, approver = `Approver__c`, final approval sets Status
  to Approved, rejection sets it to Rejected. Records are unlocked after either. One approval covers the whole
  request (all its Leave Line Items).
- Submit in the PTO tab sends the new request into the process. Approve/Reject in the PTO tab completes the open
  approval step, so the same emails go out whether the decision is made in the PTO tab or on the standard
  approval page.
- The PTO tab works without this folder, but then no emails are sent. The Salesforce bell notifications
  (notification type PTO Request Update, in the package) are sent either way: to the approver on submit, to the
  employee on approve or reject.
- A request with no approver (the employee has no manager) is not sent into the process, so it gets no emails.
  HR approves it in the PTO tab.

## Org checks if emails don't arrive

- Setup > Deliverability: Access level is **All email** (new sandboxes and scratch orgs start at System email only).
- The approver's user setting **Receive Approval Request Emails** is not *Never*.
- The employee has an active User on the Employee record (the request owner gets the employee emails).
