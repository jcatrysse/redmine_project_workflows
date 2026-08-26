# ADR-001 — Explicit override scopes

- **Status:** accepted, 2026-08-26
- **Supersedes:** the implicit model ("a project row exists, therefore this
  project overrides"), which shipped in 0.0.1–0.0.3

## Context

The plugin stores project workflow rules in Redmine's `workflows` table with a
`project_id`. Until now it decided whether a project overrides the generic
workflow by asking whether any project row exists for that tracker and role.

That works until you ask it a question it cannot answer. Measured on a running
Redmine 5.1 and confirmed on 6.1 and 7.0:

- Adding **one** project rule removes **all** generic transitions for that
  tracker and role in that project. There is no such thing as a partial
  override, and nothing says so.
- Removing the last project rule silently returns the project to the generic
  workflow. "No transitions allowed here" cannot be configured at all.
- An inventory of which projects deviate cannot be built, because deviating and
  having-no-rules look the same.

The administration UI hides the first two: selecting a project with no rules of
its own shows an *empty* matrix, so an administrator naturally ticks the
complete set they want and ends up with a full override that behaves correctly.
That is why the defect survived production use. It becomes visible the moment
anything reasons about inheritance per rule — which is exactly what the planned
overview and bulk editing do.

## Decision

Introduce `project_workflow_scopes`: one row per
(project, tracker, role, rule type) that records the *decision* to override,
independent of whether any rules exist.

- Absent scope → the project inherits the generic workflow.
- Present scope with rules → those rules apply, and only those.
- Present scope without rules → nothing applies. A valid, visible state.

A scope **replaces**; there is no additive mode and there are no negative
rules. Scopes do not inherit between projects. Transitions and field
permissions scope separately.

## Alternatives considered

**A sentinel rule row** ("no transition allowed") in the existing table. Solves
only the empty case, not the partial one, and the partial case is the one users
actually meet. Rejected.

**An STI marker row** in `workflows` with its own `type`. Avoids a new table and
inherits the existing cascade, but leaves `old_status_id` and friends unused,
gives audit fields nowhere to live, and makes the one place that needs to be
unambiguous depend on a convention about empty columns. Rejected.

**A separate table** — this decision. Costs a migration and a backfill, and
means two tables must stay consistent. Buys an unambiguous model, a point
lookup on the hot path in place of the current system-wide "does any override
exist anywhere" query, and somewhere to put `created_by` / `updated_by`.

## Consequences

- Existing installations are backfilled: every (project, tracker, role) that
  has rules gets a scope of the matching type. Behaviour does not change.
- `override_active?` becomes an indexed lookup on the current project instead
  of a table-wide existence check.
- Enabling a project's own workflow needs a starting point. It offers a copy of
  the generic workflow (preselected) or an empty start, because with replacing
  semantics an accidental empty scope freezes every issue in the project.
- The UI has to say which of the three states a scope is in, everywhere it
  shows one. "Empty" is not an error state and must not be coloured like one.
- Deleting a project, tracker or role cascades to its scopes.
