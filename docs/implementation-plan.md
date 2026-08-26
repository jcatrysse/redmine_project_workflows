# Implementation plan — WP0..WP7

> Work in this order. Each package is one commit (or a small run of them) on
> `claude/dev`, green at every commit. `docs/design.md` describes the target;
> this file describes the route.

## Reference

- **Decision:** [`adr/ADR-001-scope-model.md`](adr/ADR-001-scope-model.md)
- **Design:** [`design.md`](design.md)
- **Choices already made:** [`DECISIONS.md`](DECISIONS.md) — do not re-open one
- **Findings this plan answers:** [`review/findings/`](review/findings/)

## Progress

| Package | Title | Status |
| --- | --- | --- |
| WP0 | Immediate repairs | not started |
| WP1 | Scopes: table, model, resolver, backfill | not started |
| WP2 | Correctness at the core seams | not started |
| WP3 | Summary and inventory | not started |
| WP4 | Project settings tab and permissions | not started |
| WP5 | Bulk editing in the matrix | not started |
| WP6 | Compare, audit, undo | not started |
| WP7 | Documentation, locales, release | not started |

---

## WP0 — Immediate repairs

Everything here is independent of the data model and none of it has to be
redone later.

- The project selector renders the SVG sprite core expects since 6.0, behind a
  `respond_to?` fallback for 5.1. Without it `toggleMultiSelectIconInit()`
  calls `updateSVGIcon(undefined, …)` and the page's JavaScript initialisation
  aborts. *(claude F04)*
- Patches move from `after_initialize` to `to_prepare`, with an idempotent
  prepend guard. *(claude F05)*
- `return if performed?` after every `load_project_options`, plus strict
  validation of target project ids: only `global` or digits, loaded in one
  query, de-duplicated, reported as a translated validation error. *(external
  F03)*
- `project_context?` derives from the presence of plugin parameters rather than
  from a non-empty project list, so "copy to the generic workflow only" stops
  falling through to core. *(external F02)*
- Server-side whitelisting of `rule`, `field_name` and status ids in both
  writers — this restores validations that core had and the plugin's routing
  removed. *(external F05)*
- The `Thread.current` cache fallback is removed; `RequestStore` only.
  *(external F09)*

**Done when** the matching characterization examples have been inverted and
moved out, and 6.x/7.0 show no JavaScript error on the workflow page.

## WP1 — Scopes: table, model, resolver, backfill

- Migration creating `project_workflow_scopes` as specified in `design.md`,
  with the backfill: every (project, tracker, role) that has rules gets a scope
  of the matching type. Reversible, and tested up → down → up.
- `ProjectWorkflowScope` model with validations and a lookup by
  (project, tracker, role, rule type).
- `Resolver`, `TransitionQuery`, `PermissionQuery` and `StatusListQuery` decide
  on scopes instead of on row existence. `override_active?` becomes a lookup on
  the current project, cached per request.
- The writers create or keep a scope on a project write and never remove one
  implicitly.
- The three actions from `design.md`, wired into the admin screens: enable
  (copy or empty), return to inheritance, empty the matrix.

**Done when** the characterization examples about override semantics have been
inverted: an empty scope allows no transition, and a project rule no longer
silently converts the whole tracker/role to project control without a scope
saying so.

## WP2 — Correctness at the core seams

- `Project#rolled_up_statuses` loses the role filter and computes effective
  statuses per project across the tree, then unions. Fixes both the empty
  status filter for member-less projects and the incomplete subproject
  handling. *(external F08)*
- The two `Issue` call sites that consult `Tracker#issue_status_ids` become
  project-aware; the tracker method itself stays a global union. *(claude F02 —
  see its `Resolution:` for why the obvious fix is the wrong one)*
- `WorkflowRule.copy` carries project rules and their scopes, so copying a role
  or tracker produces a working copy. *(claude F03)*
- Unique index on the scope table. For the workflow rows themselves: an
  idempotency test, and a unique index only where the canonical key is
  unambiguous, with a cleanup step first. *(external F06)*
- Walk the remaining core queries against `workflows` (default data loader,
  status deletion) and record the outcome in `design.md`.

**Done when** `spec/characterization/` is empty.

## WP3 — Summary and inventory

- `WorkflowsController#index` counts per scope instead of mixing populations,
  with a project selector above the existing grid. Default: generic, so the
  page behaves as before for anyone who does not use the plugin. *(claude F01)*
- An inventory view: one row per (project, tracker, role), columns for
  transitions and field permissions, counts, and the state as a **text** label
  — *Own workflow*, *Inherits generic*, *Own empty workflow* — with colour only
  supporting it.
- Filters on project, tracker, role, rule type, and "deviations only" versus
  everything. Default: deviations only.
- An empty state with a sentence and two actions rather than an empty table.
- Rows link into the existing matrices, pre-filled.

## WP4 — Project settings tab and permissions

- Permissions `view_project_workflow` and `manage_project_workflow` under the
  issue tracking module. Managing includes enabling and returning to
  inheritance.
- A tab in project settings, via a patch on
  `ProjectsHelper#project_settings_tabs`, listing per tracker and role the
  current state with the three actions. Editing opens the matrix.
- The plugin's own controller, authorizing per project. The matrix is reused
  but narrowed to the trackers enabled in the project and the roles with
  members there.
- The generic workflow is visible read-only, as a reference.

**Done when** authorization specs cover: no permission, view only, manage, and
an attempt to write to another project. This is the only place where
non-administrators write workflow data; it carries the heaviest test coverage.

## WP5 — Bulk editing in the matrix

- Mixed-value cells get the same CSS classes and data attributes as ordinary
  checkboxes, so Redmine's own row and column toggles reach them. *(claude F06)*
- Explicit per-row and per-column actions Yes / No / Unchanged — toggling is
  not the same as setting to No, and setting to No is the case that needs it.
- The size of the selection shown above the matrix, and a confirmation once an
  action would touch more than a configured number of workflows.
- Keyboard operation, visible focus and `aria-label`s from the start.
  "Unchanged" gets clearer wording and a legend.

## WP6 — Compare, audit, undo

- A "project versus generic" view showing which cells differ, reachable from
  the inventory and from the matrix.
- `created_by_id` / `updated_by_id` maintained on every write path and shown in
  the inventory and the project tab.
- Bulk actions change the screen first, with a counter and an undo control;
  only Save writes.

Out of scope: workflow templates, rectangle and drag selection.

## WP7 — Documentation, locales, release

- README: that a scope **replaces** the generic workflow, what the three states
  mean, what "generic" is, and what happens with several projects selected.
  *(external F11)*
- All new strings in `en` and `nl` by hand; the other six locale files carry
  the keys.
- Terminology fixed: **Generic workflow**, **Own workflow**, **Inherits the
  generic workflow**.
- Version-conditional code consolidated into one helper.
- Version bump, CHANGELOG, and an upgrade note about the backfill.
- Work down `.rubocop_todo.yml` where the fix is mechanical and safe.

---

## Sequencing

WP0 is independent. WP1 gates everything after it. WP3 needs WP1's scopes to
report anything true; WP4 needs WP1 and reuses WP3's state labels. WP5 touches
different files from WP4 and can run alongside it. WP6 needs WP1 (audit
columns) and WP3 (where the compare view is reached from). WP7 comes last,
after all strings exist.

## Definition of done

`spec/characterization/` is empty, the nine-cell CI matrix is green, a project
administrator can give their project its own workflow and see at a glance which
projects deviate, and the README describes what the plugin actually does.
