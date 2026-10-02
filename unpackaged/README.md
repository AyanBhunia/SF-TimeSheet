# Optional Leave Approval Process (not packaged)

Approval processes can't ship in the managed package, so this folder holds an optional one for orgs that
want standard approval emails and history. Deploy it on its own:

```
sf project deploy start --metadata-dir unpackaged
```

- `Leave_and_Holiday__c.Leave_Approval`: entry Status = Submitted, approver = `Approver__c`,
  final approval sets Status to Approved, rejection sets it back to New. Records are unlocked after either.
- The PTO tab works with or without it. When it is active, Submit also sends each leave day into it, and
  Approve/Reject in the PTO tab completes the open approval step.
- Rejecting from the standard approval screen keeps the reason in approval history only, not in Notes.

The folder is listed in `.forceignore`, so packaging and source deploys skip it.
