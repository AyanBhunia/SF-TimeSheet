# Timesheet Approval Table — Design Plan

---

## 1. Core Concepts

### Column Types

| Type | Button Icon | Behavior |
|------|-------------|----------|
| **Expanded** (Group By) | ☰ (3 vertical bars `|||`) | Each distinct value creates its own row; identical adjacent values in this column are **merged** (rowspan) |
| **Collapsed** | ≡ (3 horizontal bars `≡`) | All values that fall under the same left-context are **concatenated** into a single summarised cell |

> **Toggle rule:** Clicking the button on a column header switches it between Expanded ↔ Collapsed, then immediately recalculates all columns to its right.

---

## 2. Default State

| Col | Type | Note |
|-----|------|------|
| Employee | **Expanded** | Only column expanded by default |
| Date | Collapsed | Shows Count of distinct dates |
| Project | Collapsed | Shows Count of distinct projects |
| Activity | Collapsed | Shows Count of distinct activities |
| Duration | Collapsed | Shows **Sum** (not count) of duration hours |
| Status | Collapsed | Shows Count of distinct statuses |

---

## 3. Collapse / Expand Rules

### 3a. Expanded Column
- Within the same left-context (i.e. same values in all columns to the left of it), each distinct value in this column gets its **own row**.
- When multiple adjacent rows share the same left-context AND same value in this column, they are displayed as a **single merged cell** (rowspan).

### 3b. Collapsed Column
- Within the same left-context, all rows are collapsed into **one cell** per distinct group on the left.
- **Duration column:** Show `Sum` of all Duration values in context.
- **All other columns:** Show `Count: N` where N = number of distinct values in context.

### 3c. Recalculation Direction
- Changes always flow **left → right**.
- When column X changes type: columns X+1, X+2, … are recalculated based on the new grouping context that X produces.
- After all rows are computed, **cell height (rowspan)** flows **right → left** — the leftmost expanded column's merged cell height is determined by how many rows its children occupy.

---

## 4. Full Dataset (Reference)

```
Employee    Date          Project     Activity    Duration    Status
Alice       01-08-2026    Project A   Coding      5           Approved
Alice       01-08-2026    Project B   Testing     8           Approved
Alice       01-08-2026    Project C   Design      6           Approved
Alice       02-08-2026    Project D   Design      9           Approved
Alice       02-08-2026    Project A   Coding      5           Approved
Alice       02-08-2026    Project B   Testing     8           Approved
Bob         01-08-2026    Project C   Design      6           Approved
Bob         01-08-2026    Project A   Coding      5           Approved
Bob         02-08-2026    Project B   Testing     8           Approved
Bob         03-08-2026    Project C   Design      6           Approved
Bob         03-08-2026    Project D   Coding      10          Approved
Charlie     01-08-2026    Project A   Testing     7           Approved
Charlie     01-08-2026    Project C   Design      6           Approved
Charlie     02-08-2026    Project D   Coding      10          Approved
Charlie     03-08-2026    Project A   Testing     7           Approved
Charlie     04-08-2026    Project B   Design      9           Approved
```

---

## 5. Example Scenarios

---

### Scenario A — Default State
**Employee=Expanded, Date=Collapsed, Project=Collapsed, Activity=Collapsed, Duration=Collapsed, Status=Collapsed**

Context chain: `Employee` only.

| Employee (merged) | Date | Project | Activity | Duration | Status |
|---|---|---|---|---|---|
| Alice *(rowspan 1)* | Count: 2 | Count: 4 | Count: 2 | Sum: 41 | Count: 1 |
| Bob *(rowspan 1)* | Count: 3 | Count: 4 | Count: 2 | Sum: 35 | Count: 1 |
| Charlie *(rowspan 1)* | Count: 4 | Count: 4 | Count: 2 | Sum: 39 | Count: 1 |

**How Date=Count is derived per employee:**
- Alice: distinct dates → {01-08, 02-08} → **Count: 2**
- Bob: distinct dates → {01-08, 02-08, 03-08} → **Count: 3**
- Charlie: distinct dates → {01-08, 02-08, 03-08, 04-08} → **Count: 4**

---

### Scenario B — Employee + Date both Expanded
**Employee=Expanded, Date=Expanded, Project=Collapsed, Activity=Collapsed, Duration=Collapsed, Status=Collapsed**

Context chain: `Employee → Date`.

| Employee (merged) | Date (merged) | Project | Activity | Duration | Status |
|---|---|---|---|---|---|
| Alice *(rowspan 2)* | 01-08-2026 *(rowspan 1)* | Count: 3 | Count: 2 | Sum: 19 | Count: 1 |
| Alice | 02-08-2026 | Count: 3 | Count: 2 | Sum: 22 | Count: 1 |
| Bob *(rowspan 3)* | 01-08-2026 | Count: 2 | Count: 2 | Sum: 11 | Count: 1 |
| Bob | 02-08-2026 | Count: 1 | Count: 1 | Sum: 8 | Count: 1 |
| Bob | 03-08-2026 | Count: 2 | Count: 2 | Sum: 16 | Count: 1 |
| Charlie *(rowspan 4)* | 01-08-2026 | Count: 2 | Count: 2 | Sum: 13 | Count: 1 |
| Charlie | 02-08-2026 | Count: 1 | Count: 1 | Sum: 10 | Count: 1 |
| Charlie | 03-08-2026 | Count: 1 | Count: 1 | Sum: 7 | Count: 1 |
| Charlie | 04-08-2026 | Count: 1 | Count: 1 | Sum: 9 | Count: 1 |

**Alice merged cell height = 2 rows** (spans her 2 date rows).
**Bob merged cell height = 3 rows**. **Charlie merged cell height = 4 rows**.

---

### Scenario C — Employee=Collapsed, Date=Collapsed, Project=Expanded
**Employee=Collapsed, Date=Collapsed, Project=Expanded, Activity=Collapsed, Duration=Collapsed, Status=Collapsed**

With Employee collapsed, there is no left-context grouping — all employees are collapsed into a single global context. Then Project is the first expanded column.

| Employee | Date | Project (merged) | Activity | Duration | Status |
|---|---|---|---|---|---|
| Count: 3 | Count: 4 | Project A | Count: 2 | Sum: 29 | Count: 1 |
| Count: 3 | Count: 4 | Project B | Count: 2 | Sum: 33 | Count: 1 |
| Count: 3 | Count: 4 | Project C | Count: 3 | Sum: 24 | Count: 1 |
| Count: 3 | Count: 4 | Project D | Count: 2 | Sum: 38 | Count: 1 |

**Employee Count: 3** = distinct employees = {Alice, Bob, Charlie}.
**Date Count: 4** = distinct dates across all = {01-08, 02-08, 03-08, 04-08}.

---

### Scenario D — Employee=Expanded, Date=Collapsed, Project=Expanded (as shown by the user)
**Employee=Expanded, Date=Collapsed, Project=Expanded, Activity=Collapsed, Duration=Collapsed, Status=Collapsed**

Context chain: `Employee → (Date collapsed) → Project`.

| Employee (merged) | Date | Project (merged) | Activity | Duration | Status |
|---|---|---|---|---|---|
| Alice *(rowspan 4)* | Count: 2 | Project A | Count: 1 | Sum: 10 | Count: 1 |
| Alice | Count: 2 | Project B | Count: 1 | Sum: 16 | Count: 1 |
| Alice | Count: 2 | Project C | Count: 1 | Sum: 6 | Count: 1 |
| Alice | Count: 2 | Project D | Count: 1 | Sum: 9 | Count: 1 |
| Bob *(rowspan 4)* | Count: 3 | Project A | Count: 1 | Sum: 5 | Count: 1 |
| Bob | Count: 3 | Project B | Count: 1 | Sum: 8 | Count: 1 |
| Bob | Count: 3 | Project C | Count: 1 | Sum: 12 | Count: 1 |
| Bob | Count: 3 | Project D | Count: 1 | Sum: 10 | Count: 1 |
| Charlie *(rowspan 4)* | Count: 4 | Project A | Count: 1 | Sum: 14 | Count: 1 |
| Charlie | Count: 4 | Project B | Count: 1 | Sum: 9 | Count: 1 |
| Charlie | Count: 4 | Project C | Count: 1 | Sum: 6 | Count: 1 |
| Charlie | Count: 4 | Project D | Count: 1 | Sum: 10 | Count: 1 |

This matches the user's expected output. ✅

**Alice merged rowspan = 4** because she has 4 distinct projects across her 2 dates.
**Date "Count: 2"** for Alice = 2 distinct dates (01-08, 02-08), shown repeated per project row (collapsed cell spans all 4 project rows but displays same value — it's a single merged cell).

---

### Scenario E — All Expanded (Full Detail View)
**Employee=Expanded, Date=Expanded, Project=Expanded, Activity=Expanded, Duration=Expanded, Status=Expanded**

Context chain: `Employee → Date → Project → Activity → Duration → Status`. Every row is a unique leaf. No collapsing — pure data.

| Employee | Date | Project | Activity | Duration | Status |
|---|---|---|---|---|---|
| Alice *(r6)* | 01-08 *(r3)* | Project A | Coding | 5 | Approved |
| ↑ | ↑ | Project B | Testing | 8 | Approved |
| ↑ | ↑ | Project C | Design | 6 | Approved |
| ↑ | 02-08 *(r3)* | Project D | Design | 9 | Approved |
| ↑ | ↑ | Project A | Coding | 5 | Approved |
| ↑ | ↑ | Project B | Testing | 8 | Approved |
| Bob *(r5)* | 01-08 *(r2)* | Project C | Design | 6 | Approved |
| ↑ | ↑ | Project A | Coding | 5 | Approved |
| ↑ | 02-08 *(r1)* | Project B | Testing | 8 | Approved |
| ↑ | 03-08 *(r2)* | Project C | Design | 6 | Approved |
| ↑ | ↑ | Project D | Coding | 10 | Approved |
| Charlie *(r5)* | 01-08 *(r2)* | Project A | Testing | 7 | Approved |
| ↑ | ↑ | Project C | Design | 6 | Approved |
| ↑ | 02-08 *(r1)* | Project D | Coding | 10 | Approved |
| ↑ | 03-08 *(r1)* | Project A | Testing | 7 | Approved |
| ↑ | 04-08 *(r1)* | Project B | Design | 9 | Approved |

*(↑ = merged cell, r# = rowspan)*

---

## 6. Data Calculation Algorithm

```
function computeRows(data, columns):
    // Step 1: Group data left to right based on expanded columns
    // Collapsed columns are transparent to grouping — they show aggregated value within current group context

    groupedRows = group(data, expandedColumnsInOrder)

    // Step 2: For each leaf node (row), compute collapsed column values
    for each row in groupedRows:
        for each collapsed column C:
            context = values in current group
            if C == Duration:
                cell.value = "Sum: " + sum(context[C])
            else:
                cell.value = "Count: " + distinctCount(context[C])

    // Step 3: Assign rowspans right → left
    for each expanded column C (from rightmost to leftmost):
        mergeAdjacentCellsWithSameValue(C)
        propagateHeightToLeft(C)

    return groupedRows
```

---

## 7. Implementation Impact on Current Code

| Area | Change Required |
|------|----------------|
| **`MAIN_COLUMN_DEFS`** | Add `isExpanded: bool` property per column (default: only Employee = `true`) |
| **Column header button** | Replace checkbox with `☰ / |||` toggle button; clicking fires new `handleColTypeToggle` handler |
| **`enrichTimesheets()`** | Remove — entirely replaced by new `computeTableRows(data, columns)` |
| **`activeMainGroups` getter** | Remove — replaced by `expandedColumns` computed from column defs |
| **`groupedMainTimesheets` getter** | Remove — replaced by `computeTableRows()` result stored in `@track tableRows` |
| **HTML template** | Remove 3-level nested group template; replace with flat `for:each={tableRows}` using `rowspan` attributes via `data-rowspan` props and CSS `display:none` for spanned rows |
| **CSS** | Add merged-cell visual treatment; no left sidebar needed |

---

## 8. Open Questions to Align Before Implementation

1. **What is the default collapsed value format?**
   - Suggestion: `Count: N` for non-duration, `N hrs` for duration — is this correct?
   - Answer: USe 'Distinct: N' for no-duration, `N hrs` for duration.
   
2. **What happens when ALL columns are collapsed?**
   - Suggestion: Show a single summary row for the entire dataset.
   - Answer: when all collapsed still a row will visible with counts which will be same as summary row. This scenario will automatically solved. Using the example, data wil look like this,
   Employee Date Project Activity Duration Status
Count: 3 Count: 4 Count: 4 Count: 2 Sum: 115 Count: 1

3. **Can Duration column be Expanded?**
   - If yes: each unique duration value gets its own row (unusual but possible). Recommend: allow it.
   - Answer: Yes. each collumn will have similar functionality.

4. **Drag-to-reorder columns — keep or remove?**
   - Current code supports drag-to-reorder headers. Should this stay?
   - Answer: Yes, user will able to change the position of the collumns. In that case, there may be a huge recalculation needed. We will discuss about this implementing the design.

5. **Column visibility toggle (the old checkbox) — keep or remove?**
   - Current code has per-column checkboxes to hide/show. Replaced by the new `≡ / |||` button?
   - Answer: Repalce the checkbox with this Icon buttons. Though both are practically same.

6. **Checkbox for row selection — stays the same?**
   - The existing checkbox for bulk approve/reject selection on the leftmost column — keep?
   - Answer: we need the checkboxes so that user can make bulk modification. But, we will revisit this discussion later too.
