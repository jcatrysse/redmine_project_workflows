# ADR-004 — *Give own workflow* writes in bulk, under a lock, and refuses above a ceiling

- **Status:** accepted, 2026-08-29 (Jan, after the measurement below: "write down
  and build as recommended: b + c")
- **Supersedes:** the decision of 2026-08-27 ("Whether creating scopes in bulk may
  use one statement for many rows — **A**, leave it"), which said in its own
  Notes that if the slow case were ever actually met it is **B** that gets
  re-opened, *with an ADR*, rather than the code. This is that ADR.
- **Does not touch:** ADR-001's scope model, INV-1, INV-3, INV-4, INV-5 or INV-6.
  Nothing here changes what a scope means or what a write is allowed to reach.

## Context

*Give own workflow* creates one scope row per (project, tracker, role) and copies
the generic rules under it. Both halves were deliberately one row at a time:
`ScopeWriter.create_scopes` does one validated `save!` per combination, and
`WorkflowRule.copy_generic_to_project` is one `INSERT … SELECT` per combination.

The reason was **attribution**, and it is a good reason. `enable` acts on the
combinations it actually created, not on the ones it set out to create: it
deletes and re-copies rules for exactly those, and reports exactly those. When a
second administrator pressed the button first, that scope is theirs and their
freshly copied rules must not be cleared and rewritten by this request. A
per-row `save!` answers "did *I* create this row?" one row at a time.
`insert_all` — the skipping form — does not, and 0.1.1 shipped precisely that
bug: a scope somebody else had just created was reported as created here too.

### What was measured, on 2026-08-29

500 projects × 5 trackers × 8 roles = **20,000 combinations**, a generic
workflow of 30 transitions per (tracker, role), so **600,000 rule rows** to copy.
Redmine 7.0; one scenario per process, each in its own transaction, because a
first pass that ran them all in one transaction measured the accumulated undo of
the earlier ones instead of the work.

| | PostgreSQL 16 | MariaDB 10.11 | statements |
| --- | --- | --- | --- |
| per-row, copy of the generic workflow | **110 s** and **294 s** (two samples) | **99 s** | 60,042 |
| batched prototype, same work | **28 s** | **23 s** | 105 |
| per-row, own *empty* workflow | 60 s | 47 s | 40,042 |
| batched, own *empty* workflow | **3.4 s** | **2.8 s** | 104 |

At 200 projects × 3 trackers × 4 roles (2,400 combinations, 72,000 rules):
13.2 s → 3.2 s on PostgreSQL, 9.6 s → 2.2 s on MariaDB.

Four things follow, and the third is the one that decides the shape:

1. **Batching is portable.** Identical scope and rule counts on both adapters.
2. **The empty variant's cost was entirely round trips** — 60 s to 3.4 s.
3. **Batching does not make the large case fast.** What is left is the data:
   600,000 rows at roughly 21,000 a second, the same throughput the matrix
   writer already measures. **A ceiling is needed whether or not the write is
   batched.**
4. **The per-row path is not linear and not stable** — 5.5 ms per combination at
   2,400, 14.7 ms at 20,000 in one sample and 5.5 ms in another. The batched path
   is flat at ~1.4 ms in every run. A ceiling can only mean something against a
   cost that is predictable.

## Decision

**Three changes, and they only make sense together.**

### 1. `enable` takes the generic coordination rows first

`Services::WriteCoordinator.lock_generic` is the first statement inside
`enable`'s transaction, for the (tracker, role) pairs of the selection. That is
**trackers × roles rows and never per project** — 40 rows for the shape measured
above, whatever the number of projects.

This is what makes bulk insertion safe, and it replaces the per-row `save!` as
the answer to attribution rather than merely working around it: with the rows
held, no other write path of the plugin can create a competing scope for those
pairs, so *the combinations that were missing when this request looked are
exactly the ones it creates*. `insert_all!` — the **raising** form — is therefore
correct, and a conflict is a defect rather than a row silently skipped.

Two administrators pressing the button together no longer race at all: the second
one waits, and its `missing_combinations` then runs against a table the first has
already committed to, so it creates what is left and reports what it created.

**It also closes a hole nobody had raised.** The rules being copied were read
under no lock at all, so an administrator saving the generic workflow while the
copy ran gave projects copied early the old rules and projects copied late the new
ones — silently, in one action. The lock covers the generic workflow for the
duration.

**Lock order stays what WP13 defined** (ascending primary key within a table;
generic rows after project scope rows) and no cycle is introduced: `enable` takes
generic rows and then *inserts* scope rows that by definition do not exist, so it
never waits on a scope row another writer holds.

### 2. The two writes become set operations

- **The decisions:** `ProjectWorkflowScope.insert_all!` in chunks of
  `INSERT_CHUNK` rows. This is the **widening of the forbidden-constructs table**
  that this ADR exists to authorise, and it is deliberately narrow: `insert_all`
  stays banned everywhere else, including `ScopeWriter`'s own
  `create_scopes`, which the copy screen uses **without** this lock and where the
  per-row skipping behaviour is still the correct one.

  What the skipped validations would have checked: `presence` of the three ids
  (the columns are `NOT NULL`), `inclusion` of `rule_type` in `RULE_TYPES` (a
  server-built list, checked in Ruby before the insert), and `uniqueness` (the
  table's own unique index, which is the real arbiter in either shape). The
  values are ids resolved from the database and a constant — no request parameter
  reaches a row hash (INV-2).

- **The rules:** `WorkflowRule.copy_generic_to_projects`, one `INSERT … SELECT`
  per (tracker, role) per chunk of projects, joining the generic rows to the
  scope rows just created. **Restricted to one pair per statement on purpose:** a
  join written as `project_id IN (…) AND tracker_id IN (…) AND role_id IN (…)`
  spans the whole cross product, which would re-copy the generic rules into a
  combination that already had a scope of its own and duplicate its rules. The
  prototype had that shape and only passed because every combination in it was
  new. A spec pins the case.

- **The defensive delete stays, and is asked first whether it has anything to
  do.** `enable` clears rules under a combination it has just created, because a
  database predating the scope table may carry orphan rows. Measured, that costs
  0.05 ms per combination on both adapters — about a second at 20,000 — and one
  `EXISTS` answers it in 0.00 s in the normal case, where there is nothing.

### 3. The action refuses above a ceiling, in the unit the settings already use

`Services::WriteBudget.projected_enable_rules` counts what the copy would write:
for each (tracker, role) pair, the number of generic rules of that type times the
number of combinations of that pair that are missing. One grouped `COUNT` over
the generic population (INV-4: `project_id: nil`), and the missing combinations
are already in hand.

Above `bulk_write_ceiling` the action raises `WriteBudget::TooLarge` before
anything is written, and both controllers report it with the number, the limit
and what to do instead. **The same setting as the matrix save, meaning the same
thing:** batched, this action writes at roughly the rate the matrix writer does,
so 200,000 rules is about the same wall clock on both screens. That equivalence
is only true *because* of change 2 — on the per-row path the same number meant
between 36 and 96 seconds depending on the size of the selection.

**The empty variant writes no rules, so it is never refused** — and at 3.4 s for
20,000 combinations it does not need to be. That is deliberate: it makes the safe
bulk action the one that is also unbounded.

## Consequences

- *Give own workflow* over 20,000 combinations goes from one to five minutes to
  about 25 seconds, and from 60,042 statements to about 100.
- The empty variant goes from a minute to three seconds.
- A selection above the ceiling is refused in one query instead of failing after
  minutes, and the message points at the empty variant as well as at the setting.
- One more shape is permitted in `ScopeWriter`, and `CLAUDE.md`'s
  forbidden-constructs table names it with its conditions:
  `insert_all!` (raising), in `enable`, under the coordination lock.
  `spec/plugin_conventions_spec.rb` pins the file list, so a third caller cannot
  appear quietly.
- The residual conflict, and it is chosen rather than overlooked: two paths
  create scope rows without this lock — duplicating a tracker or a role
  (`ScopeCopier`) and copying a project (`ProjectWorkflowCopier`). Both act only
  on a record that has just been created, so a collision needs a project or
  tracker created between one administrator opening the screen and another
  pressing Save. If it happens, `insert_all!` raises, the transaction rolls back
  and nothing is half-written; the administrator presses the button again and it
  succeeds. **Raise rather than skip** was the choice: a rollback that says so
  beats a silent miscount, which is the defect 0.1.1 shipped.

## Considered and rejected

- **Optimistic locking (`lock_version`), which is what was first suggested.** It
  protects one existing row from two concurrent *updates*. This race is two
  concurrent *inserts*: there is no row and no version. What already arbitrates
  it is the unique index, and what was missing was not safety but attribution.
- **A claim token column** — stamp a per-request id into every inserted row and
  read back the rows carrying it. It works, is portable, and needs no lock. It
  also needs a migration and a column that matters for one second in the life of
  a row, and it would leave the generic rules unlocked during the copy, which is
  the hole change 1 closes. Kept on the record as the answer if the lock ever
  proves too coarse.
- **Batching without a ceiling.** 25 seconds is still past what a front-end proxy
  will wait for, and a timeout rolls the whole transaction back.
- **A ceiling without batching.** It closes the hazard, but the number has to be
  counted in *combinations* rather than in workflow rules — the empty variant
  writes no rules and still took a minute — so the plugin would carry a third
  setting in a third unit, and its wall-clock meaning would vary threefold with
  the size of the selection.
- **A background job.** Redmine 5.1's default ActiveJob backend is the async
  adapter, which loses its queue when the process restarts. WP13 rejected it for
  the matrix save for the same reason and the reasoning has not changed.
