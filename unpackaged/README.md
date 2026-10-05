# Optional Leave Approval Process (not packaged)

Approval processes can't ship in the managed package, so this folder holds an optional one for orgs that
want standard approval emails and history. Deploy it on its own:

```
sf project deploy start --metadata-dir unpackaged
```

- `PTO_Request__c.Leave_Approval`: entry Status = Submitted, approver = `Approver__c`,
  final approval sets Status to Approved, rejection sets it to Rejected. Records are unlocked after either.
- One approval covers the whole request (all its Leave Line Items).
- The PTO tab works with or without it. When it is active, Submit also sends the new request into it, and
  Approve/Reject in the PTO tab completes the open approval step.
- Approving or rejecting from the standard approval screen works too: the request trigger stamps Decided By, Decided On
  and a Decision Notes line with the approver's comment, and an approval writes the days to the timesheets.

The folder is listed in `.forceignore`, so packaging and source deploys skip it.
