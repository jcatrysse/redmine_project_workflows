# Review run — 2026-10-14 — claude-migration-test

- **Reviewer:** Claude Code, session C of the Jira to Redmine test migration
- **Commit reviewed:** `f2c1c2f` (0.1.6), against `d61b1de` on `main` (0.0.3, what production runs)
- **Ran the test suite:** yes. Redmine 7.0-stable-GEOxyz (`1d8c2a3`) on PostgreSQL 16 and
  Redmine 5.1-stable-GEOxyz (`bcf917c`) on PostgreSQL 16; numbers in the Summary.
- **Scope covered:** the points session B2 of the migration read in the code (untested), each
  reproduced against 0.0.3 and pinned against 0.1.6; the upgrade from 0.0.3's data model; the
  migration runner `tools/apply_workflows.rb` (jira2redmine_migration `9d11a90`) run end to end
  against 0.1.6 on 7.0 and checked in a browser.
- **Scope NOT covered:** MySQL and MariaDB (not required since Jan's decision of 2026-10-07);
  Redmine 6.1; the 45-plugin host (A1).

## Summary

The question was whether the renewed plugin can replace the old one in production and carry the
migrated per-project workflows. Both answers are yes, measured. Every defect B2 found in the old
release is real (all five reproduced on a 5.1-GEOxyz host running 0.0.3) and none of them exists
in 0.1.6 (six regression examples, `spec/integration/legacy_release_defects_spec.rb`). The
upgrade keeps every project workflow: migration 004 creates a scope for every combination 0.0.3
treated as overridden, at exactly 0.0.3's granularity, and `dev/check-release-upgrade.sh` proves
the old and new code give the same answers on the same data. The runner works through 0.1.6
unchanged: a GEOS Task does not offer *Create RMA*, a LABO Task does, a project without its own
workflow gets the union, and a second run changes nothing.

The most important thing in this file for production is F01: until the upgrade, saving the
generic workflow for more than one role at once on 0.0.3 can silently delete author or assignee
transitions.

**Counts:** blocker 0 · major 0 · minor 0 · nit 0 · question 0 (in 0.1.6). The five items below
are defects of 0.0.3 only, recorded so they are not re-found and so production knows what it runs
until the upgrade. `dev/legacy/check-legacy-defects.sh` reproduces all five against 0.0.3 on any
host `dev/setup.sh` builds (measured: five "DEFECT REPRODUCED" lines on 5.1-stable-GEOxyz).

---

### F01 — 0.0.3: saving the generic matrix for several roles deletes author/assignee-only transitions

- **Status:** fixed in 0.1.6 (open in 0.0.3, which this repository does not change)
- **Severity:** major (in 0.0.3)
- **Confidence:** confirmed
- **Category:** correctness
- **Where:** `origin/main:lib/redmine_project_workflows/services/transition_writer.rb:64-82`
- **Invariant touched:** none

**What is wrong**

0.0.3 deletes every row of a submitted (old status, new status) cell, for every selected role,
whatever the author and assignee flags. Core's form for two roles where only one has an
author-only transition renders the author column as "no change" and the "always" column as an
unchecked box, so an unchanged save submits `always => 0` and the author row goes.

**How I verified it**

On 0.0.3, 5.1-stable-GEOxyz, PostgreSQL: R1 holds only an author transition a -> b, R2 holds
nothing; `WorkflowTransition.replace_transitions([t], [r1, r2], {a => {b => {'always' => '0'}}})`
leaves 0 author rows. On 0.1.6 the same flow is driven through the real rendered form
(`legacy_release_defects_spec.rb`, "keeps an author-only transition when two roles are saved
unchanged"); with `TransitionWriter#rows_for_cell` made to ignore the stored flags it goes red.

### F02 — 0.0.3: a project workflow cannot be emptied, it falls back to the generic one

- **Status:** fixed in 0.1.6 (the scope table, ADR-001)
- **Severity:** minor (in 0.0.3) · **Confidence:** confirmed · **Category:** correctness
- **Where:** `origin/main:lib/redmine_project_workflows/services/resolver.rb`

Measured on 0.0.3: own workflow a -> c, switch it off, the issue offers a -> b from the generic
workflow. 0.1.6 keeps the scope and offers nothing. Relevant for the migration: on 0.0.3 a
project role without approved transitions follows the global workflow (the runner counts these);
after the upgrade it still does, until the runner is run again on 0.1.6, which then creates the
empty own workflow.

### F03 — 0.0.3: an Integer 1 cell value is read as "off" and deletes the transition

- **Status:** fixed in 0.1.6 (rejected and counted in `MatrixSaveResult#rejected`, nothing deleted)
- **Severity:** minor · **Confidence:** confirmed · **Category:** correctness
- **Where:** `origin/main:lib/redmine_project_workflows/services/transition_writer.rb:92-94`

### F04 — 0.0.3: a project without members gets an empty status list

- **Status:** fixed in 0.1.6 (external F08)
- **Severity:** minor · **Confidence:** confirmed · **Category:** correctness
- **Where:** `origin/main:lib/redmine_project_workflows/patches/project_patch.rb:6-15`

### F05 — 0.0.3: `POST /workflows/duplicate` with a missing target project is a 500

- **Status:** fixed in 0.1.6 (core's copy screen has no project dimension any more, ADR-003; the
  plugin's copy screen refuses with a message and writes nothing)
- **Severity:** minor · **Confidence:** confirmed (`AbstractController::DoubleRenderError` in the
  test log) · **Category:** correctness
- **Where:** `origin/main:lib/redmine_project_workflows/patches/workflows_controller_patch.rb:196-200`

---

## Upgrade from 0.0.3

0.0.3 decided "this project overrides" per (project, tracker, role, rule model) by the presence of
rows (`Resolver#overridden_role_ids_for`). Migration 004's backfill creates one scope per
distinct (project, tracker, role) with rows, per rule type: the same granularity, so behaviour is
unchanged, author/assignee-only rows included. Migrations 001-003 are byte-identical in effect
(003 only gained a row count in its output). 0.0.3 registered no permissions, so 006 has nothing
to rename. Measured: `dev/check-release-upgrade.sh origin/main` on 5.1-stable-GEOxyz, PostgreSQL:
"release upgrade rehearsal OK".

## The migration runner against 0.1.6

`tools/apply_workflows.rb` on a scratch database of the 7.0-stable-GEOxyz host, with a plan of a
union (generic), LABO and GEOS own workflows, an inheriting project and a managed project without
transitions: preview `+12 -0, scopes to create 3`; apply; preview again `+0 -0, scopes 0`. Issue
answers: LABO `Open, In Progress, Create RMA`; GEOS `Open, In Progress`; inheriting project the
union; the managed empty project nothing. In Chromium: the project's Workflow screen shows "Own
workflow" with the runner's rows for GEOS and LABO, "Follows the generic workflow" for the
inheriting project, and the GEOS issue's status list has no *Create RMA*.

Two notes for the runner, neither a plugin defect: rows are inserted with `insert_all` outside the
plugin's writers, so status ids are not whitelisted (fine while the plan's ids come from Redmine);
and `have` is computed before `ScopeWriter.enable`, which deletes rows that have no scope, so on a
database that holds such rows the first run leaves them missing and the second run adds them. On a
database upgraded through migration 004 there are none.
