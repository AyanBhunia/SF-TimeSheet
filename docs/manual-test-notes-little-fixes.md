# Manual test notes: "little fixes" (branch `little-fixes`)

For the tester. No technical knowledge needed. Use a test org with at least one employee who has a manager, one active
project, and a timesheet for the current week. "Accrual" means the employee has an Accrual Start Date and Accrual Divisor.

## 1. Saving the weekly timesheet is now all-or-nothing
**Before:** Save first deleted rows, then saved the rest. If the second part failed, the deleted rows were gone.
Example: a timer was running on Project A / Development today. User clicked *Copy previous timesheet* (last week also
had Project A / Development on today's weekday) and *Save*. An error appeared, but the other rows of the week had vanished.

**Now:** The whole save succeeds or nothing changes, and the message says why.

**Test**
1. Start a timer on Project A / Development. Open the current week's timesheet, pick last week (that has the same project and activity on today's weekday) and click *Copy*, then *Save*.
   Expect: error "A timer is running on Project A / Development ... Nothing was saved." Reload: every row is still there.
2. Normal edit (change hours, add a row, delete a row) and Save. Expect: "Records saved".
3. Open the same timesheet in two tabs. In tab 2 change the hours of a row and save. In tab 1 delete that same row and save.
   Expect: error "A row was changed elsewhere ... Reload". The row is still there.
4. With a timer running (row shows 0 h), remove that row in the grid and Save. Expect: saved, the timer row is still there, no error.
5. Open a timesheet in the grid. Meanwhile save a running timer on one of its rows (e.g. from the phone) so that row has more hours. In the open grid edit a *different* row and Save.
   Expect: saved, and the timer's hours on the first row are NOT overwritten.
6. Same setup, but this time edit the row the timer just saved (the grid still shows the old hours) and Save.
   Expect: "A row was changed elsewhere ... Reload". Nothing is saved.
7. Submit a timesheet (or have it approved), open it in the grid, change hours and Save.
   Expect: "This timesheet is already submitted/approved ... Ask your manager or HR to reopen it". Nothing changes. After HR reopens it, saving works.

## 2. "Copy previous timesheet" copies project hours only
**Before:** It also copied last week's leave (e.g. approved PTO) into this week, and Save then deleted this week's real leave rows.

**Now:** Only project/activity hours are copied. This week's leave rows stay untouched.

**Test:** Last week has project hours + 8 h approved PTO. This week has 8 h approved PTO on another day. Copy last week into this week and Save.
Expect: project hours copied, last week's PTO NOT copied, this week's PTO still there. The PTO tab still shows that day "On timesheet".

## 3. Approved leave is no longer pushed into a Submitted/Approved timesheet
**Before:** Approving leave for a week whose timesheet was already submitted or approved silently added the leave to it and changed its totals.

**Now:** That leave day is flagged instead ("The timesheet for this week is already submitted. Reopen it, then use Retry sync...").

**Test**
1. Submit the timesheet of week X. Create a PTO request for a day in week X and approve it (manager/HR).
   Expect: PTO tab shows the request as "Approved, sync error". The submitted timesheet has no new row.
2. HR reopens the timesheet (status back to New). In the PTO tab open the request and click *Retry timesheet sync*.
   Expect: the day appears on the timesheet and shows "On timesheet". Repeat with an Approved timesheet.

## 4. Leave balance shown in the PTO tab is correct
**Before:** Leave that was approved but whose week was not yet approved was not subtracted, so the balance looked too high and the same hours could be requested twice.

**Now:** The balance subtracts waiting leave and approved leave not yet counted. Requests over the balance are still allowed.

**Test (employee with accrual and 10 h balance):** Request 8 h: available shows 2 h. Manager approves: still 2 h. Request another 8 h: warning "goes over the leave balance by 6 hours".
After the week's timesheet is approved: available still 2 h (not 10, not -6).

## 5. Clear messages when leave goes over the balance
**Before:** Employees only saw "goes over the balance"; managers saw nothing, and later the employee could not submit the timesheet and nobody knew why.

**Now:** The employee warning adds that the timesheet may be blocked until the manager adds extra accrued hours. The manager sees a yellow note on the request:
"<name> will be X h over their leave balance ... add Extra Accrued Hours on their Employee record".

**Test:** With accrual, request more hours than the balance. Expect: extra sentence in the warning; as manager, open the request in *Approve*: yellow note with the number of hours. Employee **without** accrual: neither the sentence nor the note appears.
Example: balance 10 h, Request 1 = 4 h, Request 2 = 8 h. The note on Request 1 speaks about all their leave, not only that request.

## 6. A timesheet cannot be submitted/approved while a timer is running
**Before:** It could be, and then the timer could no longer be saved ("already submitted"), so the tracked time was lost.

**Test:** Start a timer. Try to submit the timesheet for approval. Expect: "A timer is still running on this timesheet. Save or discard it in the timer first...". Save or discard the timer, then submit: works.
A manager approving an already **submitted** timesheet is never blocked by a timer (only the timer's owner can clear it).
Starting a timer on a submitted or approved week is refused ("already submitted").

## 7. If the timer cannot be saved, the user is told what to do
**Before:** A plain "exceeded 24 hours" error with no hint.

**Now:** The message also gives the measured time and says to enter the hours by hand, then discard the timer. The timer stays so nothing is lost.

**Test:** Enter 23.9 h today on another project in the grid. Start a timer, let it run about 15 minutes, press Save.
Expect: "... The timer measured 0.2x h. Type these hours into that project and activity row of the timesheet, then discard the timer."

## 8. Starting the timer twice at the same time creates only one timer
**Test:** Double-click *Start* quickly, or press Start in two browser tabs at the same time. Expect: one running timer; the other attempt says a timer is already running. Saving the timer works.
Starting a timer while the manager approves the same week must not hang or fail with a lock error.

## 9. A new row can no longer push a day above 24 hours
**Before:** Editing was checked, but adding a new row on a day that already had hours was not.

**Test:** A day has 20 h. Add a new row (other activity) with 6 h and Save: refused with "Duration entered for the date has exceeded 24 hours". With 4 h: saved.
Also: on a fresh week enter two rows for the same day with 15 h each in one go and Save. Expect: refused with the same message (it used to be saved as 30 h). 10 h + 10 h is saved.

## 10. Small fixes
- **HR Admin only user:** open *Employee Overview*: the profile/leave card loads without an error.
- **Admin without an Employee record:** open the app; the timer utility bar no longer shows a red error each time you switch browser tabs.
- **Demo data:** generate demo data, create a PTO request for a demo employee, then *Delete Demo Records*: it succeeds (it used to fail).

## Quick regression list (should behave as before)
Start, pause, continue, save, discard timer; timer notifications (1 h before the limit and at the limit); apply, approve, reject PTO; weekly grid add/edit/delete; submit and approve a timesheet; dashboards; PDF export.
