# Timesheet Testing Pipeline: Design

Status: draft for build. Target repo: `AyanBhunia/SF-TimeSheet`. Integration branch: `appexchange`.

## 1. Purpose

Stop two kinds of failure from reaching customers:

1. **Claimed work that did not ship, or files that shipped by accident.** The guidance-flow fix (681afb0) sat on a local branch through versions 2.27 to 2.30 while a commit message said it was included. 585cc7b blanked the package namespace.
2. **An app that works from source but breaks once packaged or upgraded.** A flow that passed on `tsorg` faulted once installed from a package (`ActionOutput ... incompatible LightningComponentOutput`). A deploy from source cannot show this.

**The key rule: a version is only promotable if it was built by CI from a commit on `appexchange`, installed as a package, upgraded from the last released version, and passed the scenario catalogue.**

## 2. Current state (verified 2026-11-06)

| Item | Value | Consequence |
|---|---|---|
| CI | None; no `.github/`, no repo secrets | Everything here is new |
| `appexchange` protection | None | Direct pushes possible |
| Repo | Public fork; default branch `main` | Unlimited Actions minutes. Secrets must be guarded. Schedules run only from the default branch (they can check out `appexchange`); `workflow_dispatch` needs its file on the default branch but can target any branch |
| Dev Hub (`PBO`) scratch orgs | 3 active (2 in use now), 6 per day | **No scratch org per PR.** Budget in section 5 |
| Validated package builds | 6 per day (`Package2VersionCreates`, read from the Dev Hub) | One nightly, the rest for release candidates |
| Skip-validation builds | 500 per day | Not used for install tests: installability is unproven (Phase 0) |
| App size | 28 Apex classes, 21 test classes, 25 LWC, 14 flows, 5 triggers, 12 objects, 5 permission sets | |
| LWC Jest tests on `appexchange` | **0** | Largest untested area |
| Package version | 2.33.0.NEXT, namespace `dbt`, ancestor HIGHEST | |

## 3. Pipeline

```
 PR to appexchange
   G1 Scope guard ─ G2 Static ─ G3 Jest            no org, every PR, ~5 min
   G4 Apex in scratch org                          gated, see section 5
        │ merge
 Nightly (and on demand)
   G5 Package install test  (validated build with coverage, fresh org)
   G6 Flow scenarios        (run as installed package)
 Release candidate (manual, `release/*`)
   G7 Validated build with coverage
   G8 Upgrade test          (last released → candidate, with data, same org as G9)
   G9 UI E2E as personas    (Playwright, on the upgraded org)
   G10 Evidence + manual approval → promote + tag
```

### Gates

| Gate | What it does | Blocks | Secrets |
|---|---|---|---|
| G1 Scope guard | Junk paths (`.sfdx/`, `.claude/`, `data/`, `*.zip`); `namespace` must stay `dbt`; `packageAliases` and `versionNumber` only on `release` PRs; destructive removals listed; PR file list compared with "Files expected" in the PR body | PR | No |
| G2 Static | ESLint; Prettier check on changed files; Salesforce Code Analyzer (PMD, flow rules); metadata XML well-formed | PR | No |
| G3 Jest | `sfdx-lwc-jest` with coverage | PR | No |
| G4 Apex | Scratch org with `dbt`, deploy, then `sf apex run test` **standalone** after the deploy (deploy-time test runs do not fire the org's record-triggered flows the same way), 75% minimum org-wide, 85% target per class | PR | Yes |
| G5 Install | Fresh no-namespace org, install the managed build; assert components through a **manifest check**: subscriber-visible items in the org (objects, fields, tabs, flows, permission sets, global classes), and the full list from `sf package version retrieve` where that permission is available | Nightly | Yes |
| G6 Flow scenarios | Run scheduled flows with `Flow.Interview.createInterview('dbt', ...)` against seeded data in the installed org | Nightly | Yes |
| G7 Validated build | `sf package version create --package Timesheet --code-coverage` from a clean CI checkout. Every CI command names `--package Timesheet`, because `TimesheetUnlocked` shares the same path | Release | Yes |
| G8 Upgrade | Install last released version, seed data, upgrade to the candidate, re-run the smoke and data checks | Release | Yes |
| G9 UI E2E | Playwright as Employee, Manager, HR Admin | Release | Yes |
| G10 Promote | Evidence report, GitHub Environment approval, promote, tag `vX.Y` with the `04t` | Release | Yes |

### Why the claim is checked three ways

| Question | Check |
|---|---|
| Did the developer change what they said? | G1 compares the PR body with the file list; review through CODEOWNERS |
| Did merged work reach the build? | Builds only from a clean CI checkout; the build records the commit in the version description |
| Did it reach the package? | G5 manifest check on the installed org. Release notes are generated from merged PRs, never written by hand |
| Was work left behind? | `check-unmerged` lists branches holding commits newer than the last tag, shown in the G10 report (informational: many old branches are intentionally unmerged) |

## 4. Repository layout

```
.github/
  workflows/  pr-checks.yml  pr-apex.yml  nightly.yml  release.yml  budget-cleanup.yml
  CODEOWNERS
  pull_request_template.md
ci/
  scope-guard.js        G1 (with tests)
  check-unmerged.sh
  org-budget.js         reads limits, refuses a run that would exceed budget
  manifest-check.js     G5, expected components versus the org
  expected-manifest.json
  report.js             G10 evidence report
tests/
  org/
    seed/               anonymous Apex seed scripts, one per scenario set
    flows/              F-* scenarios (seed, run, assert)
    upgrade/            P-* scenarios
  e2e/
    playwright.config.js
    personas.js
    specs/              E-* scenarios
Timesheet/main/default/lwc/*/__tests__/   J-* Jest
Timesheet/main/default/classes/*Test.cls  A-* additions
```

`.forceignore` already excludes `__tests__`. `tests/` and `ci/` sit outside the `Timesheet` package directory, so they can never enter the package.

## 5. Scratch-org budget

Current Dev Hub (`PBO`): 3 active, 6 per day. It will be replaced by an org with higher limits later, so the Dev Hub alias and limits are configuration, not hard-coded.

### Reused org versus new org

| Gate | Org | Why |
|---|---|---|
| G4 PR Apex | **Reused `dbt` namespaced CI org** | A check-only deploy with tests leaves the org unchanged, so PRs cannot affect each other |
| G4b merged-code Apex (nightly) | **Same reused org** | Real deploy, then `sf apex run test` standalone, so record-triggered flows run properly |
| G5, G6 install and flows | **New no-namespace org** | A fresh install can only be tested on an org that has never had the package. An installed package cannot simply be reset |
| G8, G9 upgrade and E2E | **New no-namespace org** | Must start from the last released version |

So the reused org saves a new org on every PR and every nightly Apex run. Package gates still create one org each when they run.

### Reused org rules

- **Lifetime:** 30 days, the scratch-org maximum. `ci-org.js` reads `ActiveScratchOrg.ExpirationDate` first; with under 3 days left, or if the org is missing, it creates and migrates to a replacement. This uses 1 daily and, briefly, 1 extra active slot.
- **Dedicated:** nobody develops in it. Hand edits would make results untrustworthy. One of the 2 current `dbt` scratch orgs (expiring 2026-11-28 and 2026-11-29) can become it, if no developer depends on it.
- **PRs use `sf project deploy start --dry-run --test-level RunLocalTests`.** Known limit: flows are not activated in a dry run, so a flow changed in a PR is exercised only after merge, by G4b and G6. Phase 0 compares dry-run and standalone results.
- **Drift:** source deletions do not remove components from the org. The nightly job compares org and repo; on drift, or monthly at the latest, the org is rebuilt.
- **One job at a time:** all jobs on this org share a concurrency group and queue.
- **Auth:** JWT through the CI user to the Dev Hub, then to the scratch org, so a replacement org needs no new secret.

### Budget on the current limits

| Consumer | New orgs | Rule |
|---|---|---|
| G4, G4b | 0 per run, 1 per month | Reused org |
| Nightly G5 and G6 | 1 per day, plus 1 of 6 validated builds | Skipped if `appexchange` has no new commits. Holds the second active slot while running |
| Release G8 and G9 | 1 per run, shared | Manual |
| Developers | 1 active | The third slot |

Rules:
- `org-budget.js` runs before any org is created. With no slot free, the job **fails with a clear "no budget, re-run later" message, never a pass or a skip**, because a skipped required check blocks merging anyway.
- Temporary orgs are deleted in an `if: always()` step, with `--duration-days 1` as a backstop. The reused org is never deleted by these steps.
- New-org jobs share one concurrency group, so they queue instead of competing.
- Path filters must not hide a required check: the job always reports, and passes immediately when `Timesheet/**` did not change.

## 6. Security (public repo)

- Secret-using jobs run only on `pull_request` from the same repo, `push`, `schedule` or `workflow_dispatch`. Fork PRs get G1 to G3 only; before merging one, a maintainer pushes it to an internal branch so G4 runs. `pull_request_target` is banned.
- Auth is JWT with the **teammate account on `PBO`** (decided by the owner). That account has more access than a CI job needs, so the connected app is limited to pre-authorized use and the key is held only in protected Environments. Rotate the key if the account changes.
- `SF_JWT_KEY` and `SF_CONSUMER_KEY` live in GitHub **Environments** (`ci`, and `release` with required reviewer).
- Logs: never print the auth URL or frontdoor URLs. Screenshots and traces can contain org data, so uploaded artifacts use seeded fake data only and are kept 7 days.
- Actions are pinned by commit SHA. `permissions:` is minimal in each workflow.

## 7. Known environment facts the tests must respect

| Fact | Effect on tests |
|---|---|
| `In_app_Guidence_using_STF` catches its faults and ends quietly | Assert the **assignments produced**. "No exception" proves nothing |
| Expired assignments are hidden from normal SOQL but block inserts | Query with `ALL ROWS` |
| Frontdoor URLs are single-use; a second switch in one session fails | One persona per fresh browser context; reuse `storageState` |
| Run `sf` per platform; CI is Ubuntu so the Windows path issue does not apply | Scripts must run on both for local use |
| Grid inputs are formatted text; `fill()` appends | Click, Ctrl+A, type, Tab |
| The timer exists twice on Employee Overview | Use the `visible=true` selector |
| Mobile user agents get Classic | Phone layouts are out of E2E scope; covered by Jest |
| Package components are `dbt__` in an installed org | Selectors and SOQL use the namespace; helpers read it from config |
| `PostInstallScript` emails a hard-coded external address on every install | **Scratch orgs must keep deliverability at "system email only"** so CI does not send it. **The scratch default is unproven: Phase 0 checks it before the first CI install** |
| Schedules fire in org time zone | Set the time zone explicitly in the scratch definition; add one non-UTC org run |
| 2GP beta upgrade rules are unproven here | G8 goes released → candidate. Phase 0 must prove this before G8 is built |

## 8. Scenario catalogue

Level: **J** Jest, **A** Apex, **F** flow in installed org, **E** browser, **P** packaging.
Priority: **P0** blocks merge or release from day one, **P1** added in the phase's second pass, **P2** nice to have.
"Audit" in Phase 2 marks which A rows the existing 21 test classes already cover, so nothing is written twice.

### 8.1 Packaging and upgrade (P)

| ID | Scenario | Pass condition | Pri |
|---|---|---|---|
| P-01 | Fresh install of candidate in no-namespace org | Succeeds; `PostInstallScript` does not fail it | P0 |
| P-02 | Upgrade from last released version with seeded data | Succeeds; record counts and key field values unchanged | P0 |
| P-03 | Upgrade from the oldest supported version (2.26 or as decided) | Succeeds | P1 |
| P-04 | Manifest: every class, flow, LWC, object, permission set present | Matches `expected-manifest.json` | P0 |
| P-05 | Every packaged flow is active after install and after upgrade | Active version matches package | P0 |
| P-06 | Flow deactivated by the customer, then upgrade | Behaviour recorded; no install failure | P1 |
| P-07 | Upgrade backfill: blank `Employment_Type__c`, null totals | Set to Full Time and 0 | P0 |
| P-08 | Install by a non-owner admin; installer has no email access | Install succeeds | P1 |
| P-09 | Customer has own permission set named `Timesheet_Reminder_Access` | Flow uses the `dbt` one | P0 |
| P-10 | Permission sets assign cleanly to Salesforce and Salesforce Platform licences | No licence error | P1 |
| P-11 | Org without demo data; org with demo data; both upgrade | Succeeds | P1 |
| P-12 | Namespace-sensitive code: `hasPermission`, `Flow.Interview`, prompt link, dashboards | Works with `dbt__` | P0 |
| P-13 | Non-UTC org (e.g. Asia/Kolkata and America/Los_Angeles) | Weekly dates correct | P1 |
| P-15 | Upgrade across a version that removed or deprecated a component, with data in it | Upgrade succeeds; outcome recorded | P1 |
| P-14 | Custom metadata defaults present after install; missing or null values fall back | 8 and 24 defaults used | P1 |

### 8.2 Scheduled and automated flows (F)

| ID | Scenario | Pass condition | Pri |
|---|---|---|---|
| F-01 | Guidance: user with a New timesheet, no assignment | Assignment created, expires in 3 days | P0 |
| F-02 | Guidance: expired assignment exists | Renewed, no `DUPLICATE_VALUE` | P0 |
| F-03 | Guidance: active assignment exists | Expiry updated, one row only | P0 |
| F-04 | Guidance: employee with no User among valid ones | Others still processed | P0 |
| F-05 | Guidance: inactive User among valid ones | Others still processed; document outcome | P0 |
| F-06 | Guidance: same user with several timesheets | One assignment | P0 |
| F-07 | Guidance: demo, Submitted and Approved timesheets | Skipped | P0 |
| F-08 | Guidance: no timesheets this week | Ends cleanly, no assignments | P0 |
| F-09 | Guidance: 200+ users | No limit error | P1 |
| F-10 | Timesheet creation: active employee with active User | Timesheet: Monday start, End = start + 6, owner and manager set | P0 |
| F-11 | Creation: inactive employee, no User, inactive User, demo | Skipped | P0 |
| F-12 | Creation: employee with no manager | Record created | P1 |
| F-13 | Creation: approved leave waiting in the new week | Absence line appears | P0 |
| F-14 | Reminder: New timesheet with email | Email attempted | P0 |
| F-15 | Reminder: blank email; demo; Submitted | No send, no fault | P0 |
| F-16 | Deactivate: last working date passed | Employee inactive; linked User stays active | P0 |
| F-17 | Deactivate: future or null date; demo | Unchanged | P0 |
| F-18 | Duration flow: new row over daily maximum | `Hours_Limit_Exceeded__c` true | P0 |
| F-19 | Duration flow: exactly at maximum; reduced below it | Not flagged; record whether the flag resets | P0 |
| F-20 | Timer notification flow: `Next_Notify_At__c` set then cleared | Scheduled path armed, then cancelled | P1 |
| F-21 | Submission follow-up, billable amount, type and name flows | Field results correct | P1 |
| F-22 | Inactive-employee flow removes the reminder assignment | Assignment gone | P1 |

### 8.3 Timesheet and grid (A, J)

| ID | Scenario | Lvl | Pri |
|---|---|---|---|
| T-01 | Line item takes employee from parent, billable from project | A | P0 |
| T-02 | Duplicate same date, project, activity, category rejected; update of self allowed | A | P0 |
| T-03 | Two rows in one save exceed the daily max; boundary exact | A | P0 |
| T-04 | Save on Submitted or Approved blocked; falsified parent Id refused | A | P0 |
| T-05 | Stale grid (hours changed elsewhere) rolls back whole save, null vs 0 | A | P0 |
| T-06 | One bad row: nothing saved | A | P0 |
| T-07 | Timer row protected from delete; save collision with running timer blocked | A | P0 |
| T-08 | Submit with running timer blocked; approve from Submitted allowed | A | P0 |
| T-09 | Accrual: billable attendance only, from start date, divisor 0 or null | A | P0 |
| T-10 | Approved → reopened resets accrued hours; rollup updates on delete and undelete | A | P0 |
| T-11 | User without object or field access gets the access error | A | P0 |
| T-12 | Bulk: 200 line items across timesheets within limits | A | P1 |
| T-13 | Grid renders by date; non-Monday timesheet keeps hours on their own day | J | P0 |
| T-14 | Grid totals, copy week, rows outside the 7 days left alone | J | P0 |
| T-15 | Grid validation, read-only when closed, save error messages | J | P0 |
| T-16 | Rejection note shows; date pickers refuse past dates | J | P1 |

### 8.4 PTO (A, J)

| ID | Scenario | Lvl | Pri |
|---|---|---|---|
| L-01 | Defaults: status Submitted, approver from manager; no manager warning | A | P0 |
| L-02 | Status only Submitted → Approved or Rejected; all reverse moves blocked | A | P0 |
| L-03 | Employee on a request and core line fields immutable; sync fields editable | A | P0 |
| L-04 | Self-approval blocked for manager and HR | A | P0 |
| L-05 | Direct-report rule when `Manager__c` and `User.ManagerId` disagree | A | P0 |
| L-06 | Reject needs a reason; blank and whitespace refused | A | P0 |
| L-07 | Rejected then re-apply same day and category succeeds | A | P0 |
| L-08 | Overlap with Submitted or Approved blocked; with Rejected allowed | A | P0 |
| L-09 | Hours: 0, negative, null; category max; daily max across items and leave | A | P0 |
| L-10 | Duplicate day and category within a request; two categories same day | A | P0 |
| L-11 | Notes 2,000 and 2,001 characters; range 62 and 63 days; Holiday refused | A | P0 |
| L-12 | Approve converts to absence lines; no timesheet leaves "Waiting" | A | P0 |
| L-13 | Closed timesheet: stays Approved, Sync Error; reopen and retry clears | A | P0 |
| L-14 | Retry only for HR and only on Approved | A | P0 |
| L-15 | Manual absence blocked while same leave pending | A | P0 |
| L-16 | Delete rules: Rejected, or PTO_Admin_All only | A | P0 |
| L-17 | Balance: pending counts; negative warning with and without accrual | A | P0 |
| L-18 | Org with and without an active approval process | A | P1 |
| L-19 | Sharing: approver gets read; reassign moves share; inactive approver | A | P1 |
| L-20 | Team view and approvals gated by custom permission | A | P0 |
| L-21 | Apply wizard, review step, warnings, approve dialog, past tab | J | P0 |

### 8.5 Timer (A, J)

| ID | Scenario | Lvl | Pri |
|---|---|---|---|
| R-01 | Start: no employee, unassigned or inactive project, no timesheet, closed timesheet | A | P0 |
| R-02 | Only one running timer; second tab refused | A | P0 |
| R-03 | Reuse existing row vs new row at duration 0 | A | P0 |
| R-04 | Pause twice is a no-op; another user's timer refused | A | P0 |
| R-05 | Continue only on the start day; limit 8 then cap 24; settings null or 0 | A | P0 |
| R-06 | Auto-stop at limit, computed on read | A | P0 |
| R-07 | Save adds hours; project deactivated; daily-max rejection keeps the timer | A | P0 |
| R-08 | Discard: new empty row deleted; existing row kept and cleared | A | P0 |
| R-09 | Notification stages 1-4; early wake re-arms; under one hour skips warning | A | P0 |
| R-10 | Corrupt timer JSON and one bad row do not stop the others | A | P0 |
| R-11 | Component states, picker, label in the utility bar | J | P0 |

### 8.6 Demo data, assignment, dashboard, access (A, J)

| ID | Scenario | Lvl | Pri |
|---|---|---|---|
| D-01 | Full demo build in order; missing prerequisite messages | A | P0 |
| D-02 | Run twice: no duplicates; existing-employee clash reported | A | P0 |
| D-03 | Delete only the current user's demo records, in dependency order | A | P0 |
| D-04 | Demo records excluded from all scheduled flows | F | P0 |
| D-05 | Production warning shows; demo works in a scratch org | A, J | P1 |
| D-06 | Assign: only active projects and employees; group members resolved | A | P0 |
| D-07 | Assign: rate updates only for existing; duplicate rows collapse | A | P0 |
| D-08 | `projectEmployeeCreator`, `searchableDropdown` behaviour | J | P0 |
| D-09 | Dashboard: employee vs manager vs HR see correct data; profile config absent | A, J | P1 |
| D-10 | `createPDF`, `relatedTimesheets`, `createEmployeeTimesheet` | J | P1 |
| D-11 | Permission matrix: for each of 5 permission sets, allowed and denied object, field, class access | A | P0 |

### 8.7 End-to-end journeys in the browser (E)

| ID | Persona | Journey | Pri |
|---|---|---|---|
| E-01 | Employee | Open timesheet, enter hours, save, reload, values kept | P0 |
| E-02 | Employee → Manager | Submit; manager approves; employee cannot edit; accrual updated | P0 |
| E-03 | Employee → Manager | Reject with note; note visible; fix and resubmit | P0 |
| E-04 | Employee | Timer start, pause, continue, save; hours on grid; submit blocked while running | P0 |
| E-05 | Employee → Manager | Apply PTO; manager approves; absence line on timesheet; balance changes | P0 |
| E-06 | Employee → Manager | PTO rejected; re-apply same day | P1 |
| E-07 | HR Admin | Assign employees to a project; employee sees it in pickers | P0 |
| E-08 | Admin | Demo data create and delete | P0 |
| E-09 | Manager, HR | Dashboards load without component errors for each persona | P0 |
| E-10 | User with only Timesheet_User | Admin-only tabs and actions denied cleanly | P0 |
| E-11 | User with reminder access | Guidance prompt appears; button link opens with `dbt__` filter | P1 |
| E-12 | All | Sweep every tab and record page: no Aura error modal | P0 |
| E-13 | Employee | Timesheet with non-Monday start keeps hours after two saves | P0 |

E-12 catches most "the whole app broke" failures cheaply, so it is built first.

### 8.8 Not covered

Native mobile, Classic, real email delivery, real notification delivery on devices, third-party customer automation, and timed waits on real schedules (flows are run on demand, with one nightly check that schedules exist). Timer limitations already accepted as-is are not re-raised as failures.

## 9. Data strategy

- `tests/org/seed` builds a named set: HR admin, manager, employee, employee with no User, employee with inactive User, demo employee, billable and non-billable projects, activities, this week's timesheets.
- Users: created through `sf org create user` or Apex with fake addresses.
- All tests clean up by Id. Scratch orgs are thrown away, so cleanup failures do not spread.
- Dates are relative to the org's today. Never hard-coded. Week start is computed.

## 10. Build phases

Each phase ends with something that runs. Each task below goes to agy as one small job; the orchestrator verifies by running it, reviews the diff, then commits. One agy job at a time (memory limit).

| Phase | Output | Needs from you |
|---|---|---|
| 0 Spikes | Confirm: CI auth; released → candidate upgrade; skip-validation installability; deliverability default; component manifest source; `Flow.Interview` on scheduled flows in the installed package | JWT setup, free scratch slot |
| 1 No-org checks | G1, G2, G3 workflows, PR template, CODEOWNERS, Jest config working | Nothing |
| 2 Jest | J scenarios for the riskiest LWC first: grid, timer, PTO apply, assign, dashboard | Nothing |
| 3 Apex | Audit existing tests, fill P0 gaps, G4 | Phase 0 auth |
| 4 Package | G5, manifest, G6 flow scenarios, nightly (plus trigger on `main`) | `main` file approval |
| 5 Upgrade | G7, G8 | Scratch slots |
| 6 E2E | Playwright: E-12, then E-01 to E-05, then others, G9 | Scratch slots |
| 7 Release | G10, tagging, release notes, protection on `appexchange` turned on | Your approval for protection |

**Protection goes on last, or a broken new check would block all merges.** New gates start as non-blocking for a week, then become required once they have proven stable.

Existing code bugs found while testing are logged in `findings and issues.md` and reported, not fixed under this work. A test for a confirmed bug is committed with `skip` and a reference.

## 11. Decisions needed

| # | Decision | Default if no answer |
|---|---|---|
| 1 | CI user on `PBO` | **Decided:** the teammate account. Connected app and key still to be set up before Phase 3 |
| 2 | Which current `dbt` scratch org becomes the dedicated CI org | Needed before Phase 3; otherwise CI creates one in the free slot |
| 3 | A small workflow file on `main`, because schedules only run from the default branch. Or change the fork's default to `appexchange` | Scheduled workflow on `main` that checks out `appexchange` |
| 4 | Oldest customer version to support in P-03 | 2.26 |
| 5 | Should `PostInstallScript` keep emailing a fixed address on every install from CI, if deliverability cannot stop it? | Keep deliverability off |

## 12. Success measures

- Every P0 scenario automated by the end of Phase 6.
- PR feedback without an org in under 10 minutes.
- No version promoted without a G10 evidence report.
- A re-run of the original incident as a test: a flow that passes from source but faults when packaged is caught by G6, and a PR claiming a file it did not change is flagged by G1.
