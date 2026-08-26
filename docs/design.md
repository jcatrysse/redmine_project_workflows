# Design — project-specific workflows

> What the plugin does, how it decides, and which shapes the data takes.
> Binding: code that disagrees with this document is either a bug or an
> amendment that has to be written down here first.

## The problem

Redmine has one workflow per (tracker, role): which status transitions are
allowed, and which fields are required or read-only in each status. That is a
global setting. Organisations that run many different kinds of project in one
Redmine end up with either a workflow that fits nobody, or a tracker per
project.

This plugin lets a project override that workflow, while every project that
does not override it keeps using the generic one, unchanged.

## The mechanism

Redmine's `workflows` table gets a nullable `project_id`:

| `project_id` | Meaning |
| --- | --- |
| `NULL` | a generic rule — exactly what stock Redmine stores |
| an id | a rule that applies only to that project |

Rules for both live in the same table, as the same STI classes
(`WorkflowTransition`, `WorkflowPermission`). Stock Redmine reads and writes
only the `NULL` rows; the plugin routes core's own write methods through its
writers so a generic save can never delete a project's rules (**INV-1**).

## Scopes — the part that carries the meaning

Row existence is not enough to express what a project wants. Three states have
to be distinguishable, and only two of them have rows:

| State | Scope row | Workflow rows | What applies |
| --- | --- | --- | --- |
| Inherits the generic workflow | absent | — | the generic rules |
| Has its own workflow | present | one or more | only the project rules |
| Has its own **empty** workflow | present | none | nothing — no transition is allowed |

A **scope** records the decision itself. The table exists as of WP1; the
`rule_type` values are the strings `ProjectWorkflowScope::TRANSITIONS` and
`::PERMISSIONS`:

```
project_workflow_scopes
  id
  project_id      not null   -> projects   (on delete cascade)
  tracker_id      not null   -> trackers   (on delete cascade)
  role_id         not null   -> roles      (on delete cascade)
  rule_type       not null   'transitions' | 'permissions'
  created_at, updated_at
  created_by_id, updated_by_id  -> users   (on delete nullify)

  unique index (project_id, tracker_id, role_id, rule_type)
  index        (project_id, rule_type)            -- inventory, project tab
  index        (tracker_id, role_id, rule_type)   -- overview per tracker/role
```

Transitions and field permissions are scoped separately (`rule_type`), because
they are edited on separate screens: taking over the transitions of a project
should not force you to take over its field permissions as well.

### The three actions

They must never mean the same thing in the database (**INV-3**):

| Action | Scope | Rules | Implemented by |
| --- | --- | --- | --- |
| Enable a project's own workflow | created | copied from generic, or none — the operator chooses, copy preselected | `ScopeWriter.enable` |
| Return to inheritance | deleted | deleted | `ScopeWriter.return_to_inheritance` |
| Empty the matrix | kept | deleted | `ScopeWriter.clear_rules` |

`ScopeWriter` is the only place that creates or removes a scope. "Enable" acts
only on the combinations that currently inherit, so pressing it twice does not
discard what the first press produced. Saving a project matrix goes on calling
`ScopeWriter.ensure_scopes`, which creates a scope where there is none and never
removes one — deleting the last rule of a project leaves the scope standing,
which is exactly what makes the empty state expressible.

"Enable" defaults to copying because a scope **replaces**: an empty scope means
no transition is permitted at all, and arriving there by accident would freeze
every issue in the project.

## Resolution

For one issue, one tracker and the roles the user holds in that project:

```
for each role:
    scope exists for (project, tracker, role, rule_type)?
        yes -> use only the project rules for that role
        no  -> use only the generic rules for that role
union the results
```

Three properties follow, and all three are deliberate:

- **A scope replaces** (**INV-5**). There is no merge and there are no negative
  rules. Adding one transition to a project means its scope now describes the
  whole workflow for that tracker and role.
- **Roles resolve independently.** A project may override the workflow for one
  role and inherit it for another; the effective set is the union across the
  user's roles. This is why the overview lists (project, tracker, role) rather
  than just (project, tracker).
- **Projects do not inherit from projects** (**INV-6**). A subproject either has
  its own scope or uses the generic workflow. Resolving is one indexed lookup,
  which matters: it sits on the path of every issue edit. For project trees,
  the copy screen can apply a workflow to subprojects.

## Who may change what

| Screen | Who | What |
| --- | --- | --- |
| Administration → Workflow | system administrator | everything, generic and per project |
| Project settings → Workflow | `view_project_workflow` | read the project's effective workflow |
| Project settings → Workflow | `manage_project_workflow` | enable, edit and return to inheritance, for that project only |

The project screen reuses the familiar matrix but narrows it to the trackers
enabled in that project and the roles that actually have members there. Every
action authorizes against the project it acts on, and no request parameter can
widen that (**INV-7**).

Both permissions live under the issue tracking module and both map
`projects#settings` as well as the plugin's own actions, because the tab is
rendered from that action. `manage_project_workflow` requires membership;
`view_project_workflow` is a read permission, so it keeps working in a closed
project while managing does not.

As built:

| Path | Action | Permission |
| --- | --- | --- |
| `projects/:project_id/workflow/transitions` | the transitions matrix | either |
| `projects/:project_id/workflow/permissions` | the field permissions matrix | either |
| `PATCH` on either | save that matrix | manage |
| `projects/:project_id/workflow/scope` | enable (`POST`) / return to inheritance (`DELETE`) | manage |
| `projects/:project_id/workflow/scope/clear` | empty the matrix | manage |

The project matrix edits **one tracker and one role at a time**. The
administration screens edit a selection at once and need a third "no change"
state in every cell for it; the settings tab is the list here, and each line
opens its own matrix, so every cell is a plain yes or no. The tracker and the
role are matched against the two lists above rather than queried, because Rails
resolves `where(id: ['1e5'])` to record 1 and the shape of an id is therefore
not something to rely on.

The generic workflow is the read-only reference: a combination the project has
not taken over renders the generic rules as disabled checkboxes, which is how
core already draws a cell that cannot be changed, with the three actions above
it. Once the project has a scope the grid is core's own `workflows/_form`
partial, unchanged, so the project matrix cannot drift from the administration
one. Saving while the project still inherits is refused rather than accepted:
the writers create the scope a project write implies, so accepting it would
turn "save" into "enable", and the three actions of INV-3 stay the only way to
take a workflow over.

## Integration points in Redmine core

These are the places where core reads workflow data without knowing about
projects. Each one is either handled or deliberately left alone.

This is the complete list: every place in Redmine 5.1, 6.1 and 7.0 that names
`WorkflowRule`, `WorkflowTransition` or `WorkflowPermission`, walked in WP2.

| Core code | Concern | Treatment |
| --- | --- | --- |
| `Issue#new_statuses_allowed_to` | which transitions a user may make | **always** replaced by the plugin, inheritance included — core's own query carries no `project_id` predicate, so falling back to it would let one project read another's rules (INV-4). The body is core's, byte-identical in 5.1, 6.1 and 7.0, with the two project-blind lookups replaced |
| `Issue#workflow_rule_by_attribute` | field permissions | same |
| `Issue#tracker=` | whether the issue keeps its status when the tracker changes | replaced. Core asks `Tracker#issue_status_ids`, a union across every project, and resets the status to the new tracker's default when the answer is no; the plugin asks the issue's own project's effective workflow, with no role filter, exactly as core has none |
| `Project#rolled_up_statuses` | fills the status filter and the status report | replaced: one (project, tracker) pair per project in the tree, each resolved against its own scope and then unioned (INV-6), with **no role filter** — core has none either, and adding one empties the list for projects without members. Two queries whatever the size of the tree |
| `Tracker#issue_status_ids`, `Tracker#issue_statuses` | which statuses a tracker's workflow uses | left as a global union on purpose: narrowing them to generic rules would strip a status from an issue in a project whose own workflow uses it. Both call sites in `Issue` are project-aware instead. Core itself no longer reads `issue_statuses`; a plugin that does gets the wide answer |
| `WorkflowsController#index` | the summary page | replaced: the count carries an explicit `project_id` predicate for the selection, so a project's rules can never be added into the generic totals. Without plugin parameters the selection is the generic workflow alone, which is exactly what core counted before any project had its own |
| `WorkflowsController#edit`, `#permissions` | the two matrices | replaced, with an explicit `project_id` predicate for the selection |
| `WorkflowsController#find_statuses` | the "only used statuses" checkbox | replaced: the effective workflow of the selection, not the rows physically stored against it. A selection whose workflow is genuinely empty still falls back to every status, which is the only way an empty matrix can be filled in |
| `WorkflowsController#update`, `#update_permissions` | saving a matrix | routed through `TransitionWriter` / `PermissionWriter` (INV-1, INV-2) |
| `WorkflowsController#duplicate` | the copy screen | `WorkflowRule.copy_for_project`, with the scopes recorded for whatever was copied. Without plugin parameters it falls through to core's `.copy`, which stays generic-only |
| `WorkflowTransition.replace_transitions`, `WorkflowPermission.replace_permissions` | core's own write API | routed through the two writers, so the generic path is validated as well |
| `WorkflowRule.copy` / `.copy_one` | the copy screen's generic path | `copy_one` is project-scoped, so a generic copy deletes only generic rows. Core's own body has no `project_id` predicate in its delete and would take a project's rules with it |
| `Role#copy_workflow_rules`, `Tracker#copy_workflow_rules` | duplicating a role or tracker | replaced by `WorkflowRule.copy_with_projects`: the project rules and their scopes come along, an own *empty* workflow included, so a copied role is a working copy |
| `WorkflowPermission.rules_by_status_id` | core's `permissions` action | project-blind, and unreachable once the plugin is installed because that action is replaced. Left alone; a plugin that calls it directly gets every project's rows |
| `IssueStatus.new_statuses_allowed` and `IssueStatus#new_statuses_allowed_to` | a status's own transition list | project-blind, and core no longer calls either — `Issue#new_statuses_allowed_to` is the only caller and the plugin replaces it. There is no project in scope at that call, so there is nothing to narrow it with; left alone |
| `IssueStatus#delete_workflow_rules` | deleting a status | no change needed — it deletes by status id, which covers project rows too |
| `Role#workflow_rules`, `Tracker#workflow_rules` (`dependent: :delete_all`) | deleting a role or tracker | no change needed — the association covers project rows, and migration 004's foreign keys cascade the scopes |
| `Project` destroy | deleting a project | no change needed — migration 003's foreign key cascades the rules, migration 004's the scopes |
| `Redmine::DefaultData::Loader` | the default workflow on a fresh install | no change needed — it creates rows without a `project_id`, which is exactly the generic workflow |
| `Issue#project=` | moving an issue to another project | **not handled, deliberately.** It re-checks the *tracker* against the new project and never the *status*, so an issue moved into a project whose own workflow does not use its status lands on a status that project cannot leave. Core has the same asymmetry — it is not a regression — but per-project workflows make it reachable without an administrator changing anything. WP4 looked at it and left it: the repair sits on the path of every issue save and every bulk move, and `safe_attributes=` assigns `project_id` before `tracker_id` on purpose, so a wrong order would reset statuses that should have been left alone. Finding G03, and an open choice in `DECISIONS.md` |

### Why there is no unique index on `workflows`

The canonical key would have to be
(`project_id`, `tracker_id`, `role_id`, `old_status_id`, `new_status_id`,
`author`, `assignee`, `field_name`, `rule`, `type`), and two of those columns
are nullable: `project_id` is NULL for every generic row and `field_name` is
NULL for every transition. PostgreSQL, MySQL and MariaDB all treat NULLs in a
unique index as distinct, so such an index would not constrain the generic
rows at all — and those are the majority. PostgreSQL 15 could say
`NULLS NOT DISTINCT` and MySQL 8 could index an expression; MariaDB can do
neither, and Redmine 5.1 has to run on older PostgreSQL. Core has no unique
index here either.

What the plugin does instead: the writers cannot produce a duplicate within one
save (`spec/services/workflow_idempotency_spec.rb` holds them to it, generic and
project), and `rake redmine_project_workflows:deduplicate_workflow_rules`
repairs a database that already has some — exact duplicates only, because two
field-permission rows that disagree are a contradiction for an administrator to
settle, not a duplicate to delete. Two administrators saving the same matrix at
the same moment can still produce duplicates; that race is core's as well
(external F06).

### The indexes on `workflows`

Migrations 001 and 002 added four; migration 005 drops the two that could never
be chosen over the others, because every index is paid for on every insert and a
workflow save inserts a whole matrix. What remains is one index per query shape:

| Index | Serves |
| --- | --- |
| (`project_id`, `tracker_id`, `role_id`, `old_status_id`, `type`) | the transition queries |
| (`project_id`, `tracker_id`, `role_id`, `old_status_id`, `field_name`, `type`) | the field-permission queries |

Migration 005 declines to drop anything if the first of those two is missing:
migration 003's foreign key needs an index with `project_id` leftmost, and
InnoDB refuses to drop the last one.

### What the resolution costs

`StatusListQuery` resolves a set of (project, tracker) pairs in two queries: one
against the scope table and one OR of the reachable populations. The query
*count* does not grow with the number of pairs, but the second statement does —
one `OR` branch per pair that overrides something, about 75 bytes each. The
worst case is the administration matrix with "all projects" selected in an
installation where thousands of projects have their own workflow: a large
statement, accepted by every supported database, with a planning cost that is
not free. Accepted rather than fixed: it is one admin screen, the growth is
linear, and the alternative (a tuple `IN (VALUES …)` predicate) is spelled
differently on each of the three databases.

`Issue#tracker=` is the one place the resolution sits on a user's path, and only
when the tracker actually changes — an ordinary issue save asks nothing. A
single tracker change is two queries. A **bulk** tracker change is two per
distinct project in the selection, where core is one for the whole selection,
because core hands the same `Tracker` instance to every issue and memoises on
it. The plugin's request cache is keyed by (project, tracker), so it collapses
the repeats inside a project but not across projects. Recorded as finding G02.

## Views

Thirteen Deface overrides in eleven files. Eleven are on the administration
screens; the last two are on `workflows/_form`, which the project matrices
render as well, so one pair serves both:

| View | Anchor | Adds |
| --- | --- | --- |
| `workflows/edit` | `div.autoscroll` (top) | hidden `project_id[]` fields |
| `workflows/edit` | `div.autoscroll` (before) | the scope panel: state and the three actions |
| `workflows/edit` | the `submit_tag l(:button_edit)` expression | the project selector |
| `workflows/permissions` | `div.autoscroll` (top) | hidden `project_id[]` fields |
| `workflows/permissions` | `div.autoscroll` (before) | the scope panel |
| `workflows/permissions` | the `submit_tag l(:button_edit)` expression | the project selector |
| `workflows/copy` | the `select_tag('source_role_id'` expression | the source project selector |
| `workflows/copy` | the `select_tag 'target_role_ids'` expression | the target project selector |
| `workflows/index` | the `title [l(:label_workflow)` expression (**surround**) | the link to the inventory above the heading, the project selector below it |
| `workflows/index` | the count cell's url hash | the project selection, carried into the link |
| `workflows/_action_menu` | `div.contextual` (bottom) | the link to the inventory |
| `workflows/_form` | the column header (`td[data-erb-style]`, bottom) | the column's three actions |
| `workflows/_form` | the row header (`td.name`, bottom) | the row's three actions |

The summary page's count cell is a *surround* on one side and a *replace* on the
other because the two halves belong on either side of core's heading, and
because the cell itself differs between versions: 5.1 renders an `icon-not-ok`
span instead of a zero, 6.0 and later colour the number. The anchor is the part
the two shapes have in common — the url hash — and
`RedmineProjectWorkflows::VersionHelper` decides which shape to reproduce.

The scope panel renders only when the selection contains at least one real
project. An administrator who does not use the plugin sees core's screens
unchanged.

All ten anchors exist verbatim in Redmine 5.1, 6.1 and 7.0, and
`workflows/edit`, `permissions` and `copy` are byte-identical between 6.1 and
7.0. The two on `workflows/_form` are header *cells* rather than the toggle
expression inside them, because 5.1 writes that toggle as a bare
`link_to_function` and 6.0 and later as `toggle_checkboxes_link` — while the two
cells are identical on all three, and anchoring on the cell puts the actions
after the status name, where they read as belonging to it. Deface renames an
attribute whose value contains ERB, which is why the column header is matched as
`td[data-erb-style]`. `spec/integration/deface_overrides_spec.rb` asserts that each override
actually reaches the rendered page (**INV-9**), with an assertion that only
that override can satisfy — the selector and the hidden field both render
`project_id[]`, so a shared assertion would have let either of them stop
matching unnoticed.

### Bulk editing a matrix

Core puts a check-all/uncheck-all toggle in every row and column header of a
transition grid, selecting on `input[type=checkbox]:not(:disabled).new-status-N`.
A cell whose value differs across the selection is not a checkbox but a
`<select>` carrying a third, "no change" option — so the toggle silently skipped
exactly the cells with the manual work in them (finding claude F06). No selector
of the shape core uses can match a `<select>`, whatever classes it is given, so
the plugin does two things: the mixed cell gets the same `old-status-N
new-status-N` classes a checkbox cell has, and each row and column header gets
three actions of the plugin's own, which select on the class alone and therefore
reach both kinds of control. Core's toggle is left exactly as it was.

Three actions, not a toggle: **Yes**, **No** and core's own no-change label.
Toggling is not the same as setting, and setting a whole row to No is the case
with the clicking in it. No change restores the value the control was rendered
with — for a mixed cell its own no-change option, for a checkbox its
`defaultChecked` — which is what a mixed cell means, and it is offered only where
a cell can hold it: a project matrix is one workflow per cell by construction
(WP4), so a third state there would name something the matrix cannot be in.

They are links calling one small function, not a select that applies on change: a
`<select>` acting on its own `change` event fires once per step when a keyboard
user arrows through it, which would apply values nobody asked for and prompt for
confirmation on the way past. Links are one tab stop each, they keep the
browser's own focus ring — Redmine's stylesheet removes the outline on form
controls and on two tab buttons, never on `a`, on any supported version — and
they carry the whole sentence in `title` and `aria-label`. The function is
written once per page, from whichever header renders first, because the
transitions page renders the same grid three times and an anchor of its own
carrying nothing but a script would be one more thing to go stale.

How many workflows one cell stands for is the plugin's answer to core's
`@roles.size * @trackers.size`, multiplied by the scopes the selection covers.
`BulkActionsHelper` owns it and core's two cell helpers ask the same method, so
a cell and the actions on it cannot disagree about whether it is mixed. A
sentence above the matrix gives the number and explains no change, on both
administration screens, whenever a cell stands for more than one workflow — with
the half of it that describes the row and column actions only on the transitions
page, because the field-permissions matrix renders core's no-change cells but has
no such actions. It is
rendered from the scope panel's anchor rather than one of its own, and unlike the
panel it does not wait for a project to be selected: core's own no-change cells
appear for a selection of several trackers or roles alone.

The **inventory** is not a Deface override either: it is a screen of the
plugin's own, at `/project_workflow_inventories`, listing one row per (project,
tracker, role) with a column per rule type. The state is a text label — *Own
workflow*, *Own empty workflow*, *Inherits the generic workflow* — and the
number next to it is the project's own rule count, never the generic one, so it
always matches the matrix the cell links to. It defaults to the combinations
that have decided something; asked for everything, it addresses the product of
projects, trackers and roles arithmetically rather than building it, so a page
costs the same on an installation with three projects and one with three
thousand. `Services::InventoryQuery` answers it in at most five queries per
page.

The project settings screen is not a Deface override: it is a tab added by
overriding `project_settings_tabs`, rendering the plugin's own views. The tab
list is data, so adding an entry to it is an append rather than a match against
rendered markup, with no anchor to go stale. Its entry names the controller
action it leads to rather than a permission, because two permissions reach it and
somebody who may manage a workflow must see the tab without also holding the
permission to view it.

**Where that override attaches is load-bearing.** It goes into
`ProjectsController._helpers`, via `ProjectsController.helper`, and never into
`ProjectsHelper` itself. Many Redmine plugins take `project_settings_tabs` over
with a classic alias chain (`alias_method :x_without_y, :x`, then
`alias_method :x, :x_with_y`), and `alias_method` resolves the name through
`ProjectsHelper.ancestors` -- which, with anything prepended there, *starts* at
the prepended module. The neighbour therefore copies the plugin's method into its
`_without_` alias, and that copy, now owned by `ProjectsHelper`, has no `super`
to reach: core's own method drops out of the chain and every project's settings
page raises `NoMethodError`. Attaching beside `ProjectsHelper` rather than inside
it is immune by construction, in either load order -- applying later would fix
one order and leave the trap for the other. `redmine_ai_triage` measured this
(its K-29); `spec/controllers/projects_settings_tab_spec.rb` holds both load
orders and the structural assertion.

What that narrows, stated rather than left implicit: the tab reaches
`projects/settings` through `ProjectsController` only. A plugin rendering that
view from a controller of its own would not see it -- and would not see core's
own tabs either, since the view reads `@project` straight from
`ProjectsController`.

Redmine renders **every** tab's partial on every visit to the settings page --
`showTab` only hides and shows what is already there -- so the tab's rows are
built by `ProjectWorkflowsHelper#project_workflow_settings_rows`, memoised per
project for the length of the render. A helper rather than an instance variable
set in a patched `ProjectsController#settings`: the plugin patches no method of
that controller at all, which is one seam fewer of exactly the kind above, and a
helper runs whenever the view does -- including when `#update` re-renders the
settings page after a failed save. The rows are `Services::InventoryQuery` over a
single project, so the tab costs four collection queries whatever the number of
trackers and roles, and never one per row.

## Settings

One plugin setting, `bulk_confirm_threshold`: the number of workflow rules a
single row or column action may change before it asks for confirmation. 50 by
default, 0 to ask every time. The number is written down twice on purpose — as
the setting's default in `init.rb` and as `BulkActionsHelper`'s fallback, which is
what answers for a settings hash an administrator saved before the key existed —
and `spec/plugin_conventions_spec.rb` asserts the two agree. The browser does the
counting, from the multiplier and the threshold the helper writes into the
action's data attributes, and it counts only the controls whose value would
actually change.

## Supported versions

| Redmine | Rails | Ruby used in CI |
| --- | --- | --- |
| 5.1 | 6.1 | 3.2 |
| 6.1 | 7.2 | 3.3 |
| 7.0 | 8.1 | 3.3 |

Against PostgreSQL, MySQL and MariaDB. The break in core is between 5.1 and
6.0 (SVG sprite icons replaced CSS icons), not between 6.1 and 7.0.
Version-conditional code stays behind one helper.
