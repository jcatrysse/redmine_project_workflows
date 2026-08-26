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
| `WorkflowsController#index` | the summary page | **still core's.** Counts mix project and generic rows — WP3 |
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
| `Issue#project=` | moving an issue to another project | **not handled, deliberately.** It re-checks the *tracker* against the new project and never the *status*, so an issue moved into a project whose own workflow does not use its status lands on a status that project cannot leave. Core has the same asymmetry — it is not a regression — but per-project workflows make it reachable without an administrator changing anything. Repairing it changes behaviour a user can see, which is a WP4 conversation and not a query fix; recorded as finding G03 |

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

Eight Deface overrides in seven files, all on admin screens:

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

The scope panel renders only when the selection contains at least one real
project. An administrator who does not use the plugin sees core's screens
unchanged.

All eight anchors exist verbatim in Redmine 5.1, 6.1 and 7.0, and
`workflows/edit`, `permissions` and `copy` are byte-identical between 6.1 and
7.0. `spec/integration/deface_overrides_spec.rb` asserts that each override
actually reaches the rendered page (**INV-9**), with an assertion that only
that override can satisfy — the selector and the hidden field both render
`project_id[]`, so a shared assertion would have let either of them stop
matching unnoticed.

The project settings screen is not a Deface override: it is a tab added by
patching `ProjectsHelper#project_settings_tabs`, rendering the plugin's own
views.

## Supported versions

| Redmine | Rails | Ruby used in CI |
| --- | --- | --- |
| 5.1 | 6.1 | 3.2 |
| 6.1 | 7.2 | 3.3 |
| 7.0 | 8.1 | 3.3 |

Against PostgreSQL, MySQL and MariaDB. The break in core is between 5.1 and
6.0 (SVG sprite icons replaced CSS icons), not between 6.1 and 7.0.
Version-conditional code stays behind one helper.
