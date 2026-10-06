# Findings — WP2, noticed while building and by the independent review

- **Run:** 2026-08-26
- **Reviewed:** `claude/dev` at `c382b3f` .. `1bfa70d` (WP2)
- **How:** two sources. G01 was noticed while working on WP2 and recorded rather
  than fixed. G02..G05 come from the independent review role, run in a fresh
  context on the WP2 diff, which ran all three PostgreSQL cells, four random
  seeds, RuboCop and a live migration round trip. Its other findings were fixed
  in the same session and are listed at the bottom.

---

### G01 — The workflow screens tell an anonymous visitor which project ids exist

- **Status:** fixed
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** security
- **Where:** `lib/redmine_project_workflows/patches/workflows_controller_patch.rb`,
  `find_trackers_roles_and_statuses_for_edit` and `load_project_options`;
  core `app/controllers/workflows_controller.rb:23-25`
- **Invariant touched:** INV-7 (at the edge of it — the screen itself stays
  admin-only)

**What is wrong**

Core declares its callbacks in this order:

```ruby
before_action :find_trackers_roles_and_statuses_for_edit, only: [:edit, :update, :permissions, :update_permissions]
before_action :require_admin
```

The plugin overrides the first one and calls `render_404` from it when a
`project_id[]` value does not resolve. Rendering from a `before_action` halts
the callback chain, so `require_admin` never runs and the 404 is returned to
whoever asked. The answer therefore depends on data the caller is not entitled
to see.

**Why it matters**

Measured on Redmine 7.0 (see below), `/workflows/edit`:

| Caller | `project_id[]=1` (exists) | `project_id[]=99999999` |
| --- | --- | --- |
| anonymous | 302 to `/login` | **404** |
| logged in, not an administrator | 403 | **404** |

So an unauthenticated visitor can enumerate project ids one request at a time,
and a logged-in non-administrator can too. It is a small leak — Redmine exposes
project *identifiers* freely and numeric ids in plenty of other places — and the
matrix itself is still unreachable without administrator rights, so nothing but
existence escapes. It is nonetheless the plugin's leak and not core's: core takes
no project parameter here, so it always answers 302 or 403.

`load_project_options` also runs `Project.sorted` for an unauthenticated
request, which is a query core would not have made.

**How I verified it**

A throwaway controller spec against the real 7.0 host, printing the status for
each of the four cases in the table; it produced exactly those four answers. The
spec was deleted again — recording a defect is not the same as pinning it.

**Suggested direction**

Do not render from the callback. Collect the invalid ids there, as it already
does, and let each action decide — every action that uses them already runs
after `require_admin`. Alternatively prepend a `require_admin` of the plugin's
own so that authorization is settled first, but that duplicates a core callback
and would have to be kept in step with it.

The natural home is **WP4**, which introduces the project settings tab and the
two permissions and therefore has to touch every authorization decision in this
controller anyway. Fixing it earlier is cheap; it is only listed here because it
is not WP2's.

**Resolution:** **fixed**, not deferred. The independent review measured the
same four answers, agreed the leak is small, and argued that "plugin code runs
for anonymous requests on an admin-only screen" is the kind of thing that grows
— and that the repair is a few lines, since every action that needs the invalid
ids already runs after `require_admin`. So: the callback no longer renders, it
only collects, and `edit`, `update`, `permissions`, `update_permissions` and
`copy` each start with `return if invalid_project_selection?`.
`spec/controllers/workflows_controller_spec.rb` now pins all four answers in the
table; three of its five new examples fail if the callback is put back.

---

### G02 — A bulk tracker change queries once per project, where core queries once

- **Status:** wont-fix for now — **answered A by Jan on 2026-08-27**
- **Severity:** minor (reported as major)
- **Confidence:** confirmed
- **Category:** performance
- **Where:** `lib/redmine_project_workflows/patches/issue_patch.rb`, `#tracker=`;
  `lib/redmine_project_workflows/services/status_list_query.rb`,
  `.effective_status_ids`
- **Invariant touched:** none; quality gate G6

**What is wrong**

The comment on the request cache claimed core "builds a fresh Tracker instance
per issue". It does not: `IssuesController#bulk_edit` does
`edited_issues.each {|issue| issue.tracker = @target_tracker}` with one instance
for the whole selection, so core's `@issue_status_ids` memo makes it exactly one
query however many issues are selected. The plugin's cache is keyed by
(project, tracker), so it collapses the repeats inside a project and not across
projects.

**Why it matters**

Measured by the reviewer: ten issues in ten projects, 21 queries; ten issues in
one project, 2. A cross-project bulk tracker change of 200 issues is ~400
queries where core does 1.

**How I verified it**

Read `app/controllers/issues_controller.rb:303` in the 7.0 checkout (`:298` on
5.1) — one `@target_tracker` for the whole loop, confirmed. The query counts are
the reviewer's measurement.

**Suggested direction**

Two shapes were considered and both rejected for now. Resolving the whole
`edited_issues` set in one call needs a hook in `IssuesController`, which is a
patch surface WP2 has no other reason to open. Filling the cache for a whole
tracker on the second distinct project of a request works without a hook, but it
reads every scope for that tracker — which is the system-wide read external F07
was raised to remove, and it would land on a user's path.

Severity lowered to minor because this is not the issue hot path: `#tracker=`
queries only when the tracker actually changes, so an ordinary issue save asks
nothing. What it needs is a batching pass with a controller hook, which belongs
with WP6's performance work.

**Resolution:** the false rationale is corrected in the code, in
`docs/DECISIONS.md` and in `docs/design.md`, which now states the cost. The
batching itself is _(open — WP6)_.

**Re-measured 2026-08-27** (F11 session), on `4162e7f`, 7.0-stable + PostgreSQL
16, because WP6 has since been marked done and this was quietly left behind:
**the finding still stands, unchanged.** Ten issues in ten projects, each issue
on a status that is *not* the old tracker's default: **22 statements**, against
the reviewer's 21. Ten issues in one project: **2**. With all ten projects
overriding that tracker: **20**. So it is two statements per distinct project
either way — one against the scope table, one against `workflows` — and the
request cache collapses the repeats inside a project only, exactly as reported.

One trap found in the measuring, worth more than the figures: **an issue whose
status *is* the old tracker's default status never reaches the query at all.**
`Issue#tracker=` sets `status = nil` on that branch before asking anything, so
the first attempt at this measurement reported *2 statements for ten projects
and 0 for one* — a tenfold improvement that was really a fixture arranging for
the wrong branch to run. Any future batching test has to pick a non-default
status, and say why.

What is *not* re-opened here: F11's grouping does not help this path, because
each call still resolves exactly one pair. A real fix needs the whole
`edited_issues` set in one call, which needs a hook in `IssuesController` — a new
patch surface, and one more copied core method in the F03 digest table. That is
a Class B decision for Jan rather than a fixer's, and it was written up in
`docs/DECISIONS.md` with the two cheaper partial options and what each costs.

**Answered by Jan on 2026-08-27: A for now, B if it becomes an issue later.**
This finding is therefore **not** going to be fixed as it stands, and that is a
decision rather than a backlog item — a later review does not need to re-file it.
Two things follow, which is why this paragraph exists rather than a one-line
status change:

* **The eventual fix is named, and it is B, not C.** When somebody does feel it —
  a Redmine where changing the tracker of a few hundred issues spread across many
  projects is routine — the answer is to resolve the whole `edited_issues` set in
  one call, which means patching `IssuesController`. The half measure **C** (share
  one answer between the projects that have *not* taken the tracker over, ~11
  statements instead of 22) was **not** chosen, so a later session must not reach
  for it as "the cheap version of what Jan asked for": it adds a second cache to a
  path every issue save touches and still leaves the cost linear in the number of
  projects. If C is ever wanted, it is a fresh question.
* **B has a price that has to be paid deliberately.** A new patch surface on a
  core controller is one more copied method for `spec/upstream/core_drift_spec.rb`
  to digest, on a controller whose `bulk_edit` and `bulk_update` differ between
  5.1 and 6.x — so it needs the digest table re-measured on all three Redmine
  minors, and it is a change to how much of core this plugin reimplements rather
  than a performance tweak. Read `docs/design.md`'s core-code table before
  starting it.

---

### G03 — `Issue#project=` does not re-check the status against the new project

- **Status:** wont-fix — **answered A by Jan on 2026-08-26**, after this line was
  written. `docs/DECISIONS.md` carries the answer: leave it as Redmine already
  behaves. The line below still reads "open" in the Resolution because that is
  what it said when the finding was filed; the status here is the current one.
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** correctness
- **Where:** core `app/models/issue.rb:432-470` (7.0), not patched

**What is wrong**

`Issue#project=` is the symmetric partner of the `#tracker=` seam WP2 repaired.
It re-checks the *tracker* against the new project and never the *status*.

**Why it matters**

The reviewer measured an issue moved into a project whose own workflow is empty:
it keeps status Resolved and then has no allowed transitions at all — it can
never leave. For a non-empty own workflow that simply does not use the incoming
status the same thing happens. Core has the identical asymmetry, so this is not
a regression; what changed is that per-project workflows make it reachable
without anyone editing a workflow.

**How I verified it**

The reviewer's measurement, on 7.0: `before move: status=Resolved
allowed=["Assigned", "Resolved"]`, `after move: status=Resolved allowed=[]`.

**Suggested direction**

Deciding what should happen — reset to the new project's default, refuse the
move, or leave it — is a user-visible behaviour change and belongs with WP4's
project-scoped work, not with a query fix. `docs/design.md` now carries the row
saying so, which is what its claim to be a complete walk required.

**Resolution:** WP4 examined it and left core's behaviour in place, on purpose.
The repair sits on the path of every issue save and every bulk move, and
`safe_attributes=` assigns `project_id` before `tracker_id` deliberately, so a
wrong ordering would reset statuses that should have been left alone — a data
change that is not easily undone, where doing nothing is exactly what Redmine
does today. Recorded as open choice 1 in `docs/DECISIONS.md`, with the three
options, what each would feel like to a user, and a recommendation. It stays
open until Jan answers.

---

### G04 — The used-statuses filter builds one OR branch per overriding project

- **Status:** wont-fix
- **Severity:** minor
- **Confidence:** confirmed
- **Category:** performance
- **Where:** `lib/redmine_project_workflows/services/status_list_query.rb`,
  `#build_conditions`; `patches/workflows_controller_patch.rb`, `#find_statuses`

**What is wrong**

Selecting "all projects" on a matrix screen produces one `OR` branch per
(project, tracker) pair that overrides something — about 75 bytes each,
measured. Five thousand overriding projects would be a ~370 KB statement.

**Why it matters**

It is accepted by every supported database, but the planning cost is not free,
and the class comment's "the number of queries does not grow with the size of
the tree" quietly trades query count for statement size.

**How I verified it**

The reviewer measured 30 overriding projects → 2 202 bytes of SQL with 30 OR
terms, and confirmed the growth is linear.

**Suggested direction**

A tuple predicate (`(project_id, role_id) IN (VALUES …)`) collapses it, but it
is spelled differently on PostgreSQL and MySQL, and this is one administration
screen behind an explicit "all projects" choice.

**Resolution:** wont-fix, recorded in `docs/design.md` under "What the
resolution costs" so the trade is written down rather than implied.

---

### G05 — Migration 005 could abort on MySQL if migration 002's index is gone

- **Status:** fixed
- **Severity:** minor
- **Confidence:** probable (no MySQL server in the container)
- **Category:** portability
- **Where:** `db/migrate/005_drop_redundant_workflow_indexes.rb`

**What is wrong**

Migration 003 adds a foreign key on `workflows.project_id`. InnoDB requires an
index with `project_id` leftmost and refuses to drop the last one (error 1553).
005 dropped two such indexes, relying on migration 002's remaining one.

**Why it matters**

On a database where 002's index had been dropped by hand, the migration would
abort. Noisy rather than silent, but avoidable.

**How I verified it**

Reproduced the *guard*, not the MySQL error: with 002's index removed by hand on
PostgreSQL, 005 now says "index_workflows_on_project_tracker_role_old_status_type
is missing, so the redundant indexes are the only ones left with project_id
leftmost; leaving them in place" and leaves both in place. The MySQL refusal
itself is read from the InnoDB documentation, not executed.

**Resolution:** fixed. 005 checks for the replacement index and declines to drop
anything if it is missing.

---

## What the review found and this session fixed

Not carried as findings, because they were repaired in the same session:

1. **The request cache went stale after a rule-only write** (major, confirmed).
   `StatusListQuery`'s cached status list is derived from the rules, but only
   `ScopeWriter`'s scope-creating paths reset it — so `clear_rules`, a project
   save into an existing scope, a generic save, the copy paths and the duplicate
   sweep all left the old answer in place. Not reachable over HTTP today,
   because every writing action redirects, but wrong for anything scripted and
   wrong the moment WP4 renders after a write. Both rule writers, `clear_rules`,
   `enable`, the two raw copy statements and the duplicate sweep now reset, and
   seven new examples in `spec/services/workflow_idempotency_spec.rb` pin it;
   four of them fail if the resets are removed.
2. **Copying a role or tracker cost O(trackers × projects) round trips**
   (major, confirmed — 381 statements for 3 trackers and 30 projects). The rule
   copy is now one `INSERT … SELECT` per (tracker, role) carrying `project_id`
   through unchanged, and the scope copy is one `INSERT … SELECT` per rule type
   with a `NOT EXISTS` guard instead of one `create!` per project.
3. **A `workflows` delete with no `project_id` predicate** in the duplicate
   sweep — a G7 grep failure. Already corrected in `3432efd`.
4. **Two Deface overrides shared one assertion.** The selector and the hidden
   field both render `project_id[]`, so `include('project_id[]')` could not tell
   them apart and either could have stopped matching unnoticed. Each of the
   eight overrides now has an assertion only it can satisfy. The count itself
   was wrong in two documents: `CLAUDE.md` said five and `docs/design.md`
   tabulated seven.
5. **`StatusListQuery` coerced a malformed pair to tracker 0** and answered `[]`
   instead of raising; `Integer()` now says the caller is wrong.
6. **`status_ids_for_project` had no caller outside its own spec** and is gone;
   the specs use the pairs API.
7. **The plan's WP2 done-condition** could not be met. Already corrected in
   `3432efd`.
8. **One new example does not discriminate against the old code** — core has no
   role filter there either. It is a guard against a future narrowing, and now
   says so; the regression evidence is the other 25 examples that do fail.

---
