# Manual test notes: "little fixes" (branch `little-fixes`)

For the tester. No technical knowledge needed. Each item says what went wrong before, what changed, how to test it,
and what you should see. Known open problems that are NOT fixed are listed in `findings and issues.md`, so don't
report those again.

## Before you start

**Users you need** (in tsorg these exist already):

| Role | tsorg user | Used for |
|---|---|---|
| Employee | Eli Employee | timer, weekly grid, applying for leave |
| Manager of the employee | Mia Manager | approving timesheets and leave |
| HR / admin | Ayan (System Administrator) | reopening timesheets, Retry sync, admin pages |

**Logging in as another user:** as the admin, open Setup > Users, click the user's name, then *Login*. Use a second
browser (or a private window) for the second user so both stay logged in. Click *Log out as ...* at the top to return.

**Where things are** (app *Timesheet*):
- **Timer:** the *Timer* button in the bar at the bottom of the screen. While a timer runs, the button shows the
  clock and the project, e.g. `00:12:40 · Dev`.
- **Weekly grid:** open a timesheet (*Timesheets* tab), then the *Timesheet Line Items* tab on the record.
- **Leave:** the *PTO* tab, with sub-tabs Overview / Apply / Past and, for managers, *Approve (n)*. It takes up to
  30 seconds to load.
- **Bell:** the bell icon at the top right shows timer notifications.

**Test data:** an active project assigned to the employee (e.g. *Dev*, activity *Development*) and a timesheet for the
current week with status New. "Accrual" means the employee record has an Accrual Start Date. For items 4 and 5,
give the test employee an Accrual Start Date and remove it again afterwards.

**When something fails,** note the user, the page, the exact message (screenshot) and the time.

---

## 1. Saving the weekly timesheet is now all-or-nothing
**Before:** Save first deleted rows, then saved the rest. If the second part failed, the deleted rows were gone.
Example: a timer was running on Project A / Development today. User clicked *Copy previous timesheet* (last week also
had Project A / Development on today's weekday) and *Save*. An error appeared, but the other rows of the week had vanished.

**Now:** The whole save succeeds or nothing changes, and the message says why.

**Test**
1. Start a timer on Project A / Development. Open the current week's timesheet, pick last week (that has the same
   project and activity on today's weekday) and click *Copy*, then *Save*.
   - **Observe:** error "A timer is running on Project A / Development ... Nothing was saved."
   - Reload the page (F5). **Observe:** every row that was there before is still there with the same hours.
2. Normal edit: change hours on one row, add a row, delete a row, Save.
   - **Observe:** green "Records saved". After a reload all three changes are still there.
3. Open the same timesheet in two browser tabs. In tab 2 change the hours of a row and Save. In tab 1 delete that
   same row and Save.
   - **Observe:** tab 1 shows "A row was changed elsewhere ... Reload". After a reload the row is still there with
     tab 2's hours.
4. With a timer running (its row shows 0 h in the grid), remove that row and Save.
   - **Observe:** saved without an error. The timer keeps running (bottom bar clock still ticking), and after a
     reload the timer's row is still there (it is never deleted while its timer runs).
5. Open a timesheet in the grid. In another tab (or on the phone) save a running timer on one of its rows, so that row
   gets more hours. Back in the first tab, edit a *different* row and Save.
   - **Observe:** saved. Reload: the timer's row shows the hours the timer saved, not the old number.
6. Same as 5, but this time edit the row the timer just saved (the grid still shows the old hours) and Save.
   - **Observe:** "A row was changed elsewhere ... Reload". Nothing is saved; after a reload you see the timer's hours.
7. Submit a timesheet (or have it approved), open it in the grid, change hours and Save.
   - **Observe:** "This timesheet is already submitted/approved ... Ask your manager or HR to reopen it". Reload:
     hours unchanged.
   - As HR set the status back to New, then try again. **Observe:** saved.

## 2. "Copy previous timesheet" copies project hours only
**Before:** It also copied last week's leave (e.g. approved PTO) into this week, and Save then deleted this week's
real leave rows.

**Now:** Only project/activity hours are copied. This week's leave rows stay untouched.

**Test:** Last week has project hours and 8 h approved PTO. This week has 8 h approved PTO on another day. In this
week's grid, pick last week, click *Copy*, then *Save*.
- **Observe in the grid:** last week's project hours appear on the same weekdays; last week's PTO row does NOT appear;
  this week's PTO row is still there with 8 h.
- **Observe in the PTO tab** (as the employee, *Past* tab, open this week's request): the day still shows
  "On timesheet".

## 3. Approved leave is no longer pushed into a Submitted/Approved timesheet
**Before:** Approving leave for a week whose timesheet was already submitted or approved silently added the leave to
it and changed its totals.

**Now:** That leave day is held and flagged instead.

**Test**
1. As the employee, submit the timesheet of week X. Apply for leave on a day in week X. As the manager, approve it in
   *PTO > Approve*.
   - **Observe:** the request is Approved, but its day shows a sync error: "The timesheet for this week is already
     submitted. Reopen it, then use Retry sync...".
   - Open the submitted timesheet. **Observe:** no new leave row; Absence Hours unchanged.
2. As HR, set that timesheet back to New. In the PTO tab open the request and click *Retry timesheet sync*.
   - **Observe:** the day changes to "On timesheet" and the leave row appears in the timesheet grid.
3. Repeat 1 and 2 with an Approved timesheet. Same result.

## 4. Leave balance shown in the PTO tab is correct
**Before:** Leave that was approved but whose week was not yet approved was not subtracted, so the balance looked too
high and the same hours could be requested twice.

**Now:** The balance subtracts waiting leave and approved leave not yet counted on an approved timesheet. Requests
over the balance are still allowed.

**Test (employee with accrual and a 10 h balance).** Read the number "X h available" under the PTO title after each step:

| Step | Observe "available" |
|---|---|
| Start | 10 h |
| Request 8 h (submitted) | 2 h |
| Manager approves it | still 2 h (not back to 10) |
| Request another 8 h | warning "goes over the leave balance by 6 hours"; after submitting: -6 h |
| Manager rejects the second request | back to 2 h |
| The week's timesheet with the first 8 h gets approved | still 2 h (not 10, not -6) |

**Note:** an employee **without** accrual shows a negative number (e.g. "-156 h available") because nothing is
accrued. That is a known display issue (findings item 4), not a failure of this test.

## 5. Clear messages when leave goes over the balance
**Before:** Employees only saw "goes over the balance"; managers saw nothing, and later the employee could not submit
the timesheet and nobody knew why.

**Now:** The employee warning adds that the timesheet may be blocked until the manager adds extra accrued hours.
The manager sees a yellow note on the request.

**Test (employee with accrual)**
1. As the employee, request more hours than the balance. Click *Next*, *Review*, *Submit*.
   - **Observe:** the message (it disappears after a few seconds) says "This goes over the leave balance by X hours.
     Your timesheet for that week may not be submitted or approved until your manager adds extra accrued hours to
     your balance."
2. As the manager, open *PTO > Approve* and click the request.
   - **Observe:** a yellow note: "With all their waiting and approved leave, <name> will be X h over their leave
     balance. You can still approve this request, but ... add Extra Accrued Hours on their Employee record".
3. Balance 10 h: Request 1 = 4 h, then Request 2 = 8 h. As the manager open Request 1.
   - **Observe:** the note says 2 h over and talks about all their leave, not "after this request" (Request 2 caused it).
4. Employee **without** accrual: request any hours.
   - **Observe:** no extra sentence for the employee and no yellow note for the manager.

## 6. A timesheet cannot be submitted while a timer is running
**Before:** It could be, and then the timer could no longer be saved ("already submitted"), so the tracked time was lost.

**Test**
1. As the employee, start a timer. Open the week's timesheet and click *Submit for Approval*.
   - **Observe:** refused with "A timer is still running on this timesheet. Save or discard it in the timer first...".
     The status stays New.
2. Save or discard the timer, then submit again. **Observe:** status Submitted.
3. As the manager, approve a timesheet that is already Submitted. **Observe:** approval works, even if a timer row is
   left on it (only the employee could clear a timer, so the manager is never blocked).
4. As the employee, open the timer and try to START on a day whose week is Submitted or Approved.
   - **Observe:** refused with "already submitted" (or approved); no timer starts.

## 7. If the timer cannot be saved, the user is told what to do
**Before:** A plain "exceeded 24 hours" error with no hint.

**Now:** The message gives the measured time and says to type the hours in by hand, then discard the timer. The timer
stays so nothing is lost.

**Test:** In the grid enter 23.9 h today on another project and Save. Start a timer, let it run about 15 minutes,
press STOP, then *Save*.
- **Observe:** "... The timer measured 0.2x h. Type these hours into that project and activity row of the timesheet,
  then discard the timer."
- **Observe:** the timer is still there (Save / Continue / Discard still shown).

## 8. Starting the timer twice at the same time creates only one timer
**Test**
1. Double-click *START* quickly, or press START in two browser tabs at the same moment.
   - **Observe:** one timer runs; the other attempt says a timer is already running. As admin, the timesheet shows
     one 0 h row for that project/activity, not two.
2. Save that timer. **Observe:** the row gets the hours.
3. Employee presses START while the manager approves the same week.
   - **Observe:** both finish within a few seconds, with no "unable to lock row" error. Either the timer starts, or
     START is refused with "already submitted/approved".

## 9. A day can no longer go above 24 hours
**Before:** Editing a row was checked, but a new row on a day that already had hours was not, and neither were
several rows saved together.

**Test**
1. A day has 20 h. Add a new row (other activity) with 6 h and Save.
   - **Observe:** refused with "Duration entered for the date has exceeded 24 hours". With 4 h it saves.
2. On a fresh week enter two rows for the same day with 15 h each, then Save once.
   - **Observe:** refused with the same message (it used to save 30 h). With 10 h + 10 h it saves.

## 10. Timer notifications still work (changed from scheduled jobs to a flow)
**Test (needs about 1 hour, or ask the developer to shorten the workday limit in a test org):**
1. Start a timer and leave it running.
   - **Observe:** about 1 hour before the 8 h workday limit, a bell notification "warning" arrives.
2. Keep it running. **Observe:** at the limit the timer stops by itself, a second bell notification says it was
   stopped, and the timer shows `08:00:00` with Save / Continue / Discard.
3. Click *Save*. **Observe:** the row has 8 h.
4. Start a new timer on the same project/activity/day. **Observe:** it continues on the same row (no second row).
   *Discard* it: the row keeps its 8 h.
5. STOP (pause) a timer and wait past the warning time. **Observe:** no notification while paused; after *Continue*
   notifications resume.

## 11. Employee Details card now shows data for everyone (new fix)
**Before:** On *Employee Overview* the *Employee Details* card was empty for every user who is not a system
administrator (a settings record could not be read).

**Test:** Log in as the employee, then as the manager, and open *Employee Overview*.
- **Observe:** the card shows Name, Client Manager, Projects, Total Emp Accrued Hours, Total Absence Hours Available,
  All Billable / Non Billable / Absence Hours. No red error message.
- As the manager use *Select Employee* to pick a direct report. **Observe:** the card switches to that person.

## 12. Charts no longer show "undefined" (new fix)
**Before:** In the *Overall Time* pie chart, hours on a project the viewer cannot see were labelled "undefined".

**Test:** As the employee open *Employee Overview* and look at the *Overall Time* legend (Year view).
- **Observe:** legend entries are project names, Duration, Remaining, Absence and, if there are hours on projects you
  can't see, "Other projects". Never "undefined".

## 13. Small fixes
- **HR Admin only user:** open *Employee Overview*. **Observe:** the profile/leave card loads without an error.
- **Admin without an Employee record:** open the app and switch between browser tabs a few times. **Observe:** no red
  error appears from the timer bar.
- **Demo data:** generate demo data, create a PTO request for a demo employee, then *Delete Demo Records*.
  **Observe:** succeeds (it used to fail).

---

## Full regression checklist (should behave as before)
Run these once per release. Use the employee unless the line says otherwise.

| # | Steps | Observe |
|---|---|---|
| R1 | As admin, manager and employee, click every tab: Employee Overview, Timesheets, PTO, Reports, Dashboards (and Employees, Projects, Charge Codes for admin) | every page loads; no red error box or "Something went wrong" |
| R2 | Timer: START, STOP, Continue, Save | clock runs/pauses; Save adds the time to the row of that project/activity/day |
| R3 | Timer: START, STOP, Discard | timer gone; no hours added |
| R4 | Grid: add, edit, delete rows; Save | "Records saved"; reload shows the same data |
| R5 | Submit a timesheet; as manager approve it (then try reject on another) | status Submitted -> Approved / Rejected; approval history on the *Approvals* tab |
| R6 | PTO: apply 1 day (Apply: dates, category, hours, Next, Review, Submit) | request in *Past* as Submitted; "available" goes down by the hours |
| R7 | As manager approve it in *Approve* | Approved; leave row appears on the employee's timesheet for that day |
| R8 | Apply again; manager *Reject* with a reason | Rejected; the reason is shown on the request |
| R9 | Open a timesheet record, click *Generate PDF* | a PDF downloads with the employee name and week (note: absence rows are not in the table, findings item 9) |
| R10 | Admin: open a Project, click *Assign Employees* | window opens with the project pre-selected; Cancel closes it |
| R11 | Employee Overview: Year / Month / Week / Day and Previous / Next on the charts | charts redraw for the chosen period |
| R12 | Bell icon after a timer warning | the warning (and later the "stopped" message) is listed |
