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
discard what the first press produced. Deleting the last rule of a project
leaves the scope standing, which is exactly what makes the empty state
expressible.

**Saving a matrix never creates a scope.** The three actions above are the only
way to take a workflow over, on *every* screen — the project's own tab, where
`ProjectWorkflowsController` has refused a save while inheriting since WP4, and
the administration matrices, which used to accept one. `ScopeWriter.ensure_scopes`
created the scope a project write implied and is gone; the writers call
`touch_scopes` and write only into the (tracker, role) combinations the project
has already taken over, returning the number they refused.

The reason is that the administration grid shows what the selection *stores*, so
a project that inherits renders as an empty matrix. Pressing Save on it — even
with nothing touched — therefore wrote that emptiness back as an own **empty**
workflow, in which no issue in the project can change status at all. That is the
state ADR-001 names as the one to keep unreachable by accident, and the reason
"enable" defaults to copying the generic rules. The panel above the grid now says
how many combinations of the selection inherit, that they are the empty-looking
ones, and that Save will not change them; after a save, a warning says how many
were left alone.

"Enable" defaults to copying because a scope **replaces**: an empty scope means
no transition is permitted at all, and arriving there by accident would freeze
every issue in the project.

### Two of the three actions at once

Each of the three is one transaction, and between them they may not produce a
state the three-way distinction cannot describe. The one that mattered is rules
with no scope over them: the resolver reads such a project as following the
generic workflow (INV-3), so the rules are invisible, they are never cleaned up,
and the save that wrote them reported success.

It arose because a rule write asked whether the project had taken this
combination over and wrote the rules afterwards, on the strength of an answer
that another request could have invalidated in between. The two are now one
decision: `MatrixScope#writable_pairs` locks the scope rows with
`SELECT … FOR UPDATE` inside the transaction that then writes, and
`ScopeWriter.return_to_inheritance` and `.clear_rules` take the same locks before
either of their deletes. Every path therefore takes scope rows before workflow
rows, which is also what keeps a save and a return to the generic workflow from
deadlocking rather than queueing.

Two consequences worth knowing. A save that loses the race is *refused* for that
combination and counted among the ones it left alone, exactly as if the project
had been following the generic workflow when the form was opened — which by then
it is. And "give own workflow" reports only the combinations whose scope row it
actually inserted: the other administrator's press created the rest, their rules
belong to that press, and this one leaves them alone.

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
| `projects/:project_id/workflow/compare` | this project's workflow against the generic one | either |
| `PATCH` on either matrix | save that matrix | manage |
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
| `WorkflowsController#update`, `#update_permissions` | saving a matrix | routed through `TransitionWriter` / `PermissionWriter` (INV-1, INV-2), which delete **per rule** rather than per cell: one cell of the transitions grid is three controls over two stored rows, each of which can independently be left at core's *no change*, so a delete keyed on the cell removed rows nobody had submitted a value for |
| `WorkflowsController#duplicate` | the copy screen | `WorkflowRule.copy_for_project`, with the scopes recorded for whatever was copied. Without plugin parameters it falls through to core's `.copy`, which stays generic-only — but not before `invalid_copy_selection?`, which runs on **every** request and rejects a source tracker or role, or a target tracker or role, that was supplied and did not resolve. Core reads such an id as "any" or drops it from its `where`, so the copy that ran was not the copy that was asked for (codex F01, F02) |
| `WorkflowTransition.replace_transitions`, `WorkflowPermission.replace_permissions` | core's own write API | routed through the two writers, so the generic path is validated as well |
| `WorkflowRule.copy` / `.copy_one` | the copy screen's generic path | `copy_one` is project-scoped, so a generic copy deletes only generic rows. Core's own body has no `project_id` predicate in its delete and would take a project's rules with it |
| `Role#copy_workflow_rules`, `Tracker#copy_workflow_rules` | duplicating a role or tracker | replaced by `WorkflowRule.copy_with_projects`: the project rules and their scopes come along, an own *empty* workflow included, so a copied role is a working copy |
| `WorkflowPermission.rules_by_status_id` | core's `permissions` action | project-blind, and unreachable once the plugin is installed because that action is replaced. Left alone; a plugin that calls it directly gets every project's rows |
| `IssueStatus.new_statuses_allowed` and `IssueStatus#new_statuses_allowed_to` | a status's own transition list | project-blind, and core no longer calls either — `Issue#new_statuses_allowed_to` is the only caller and the plugin replaces it. There is no project in scope at that call, so there is nothing to narrow it with; left alone |
| `IssueStatus#delete_workflow_rules` | deleting a status | no change needed — it deletes by status id, which covers project rows too. Worth knowing rather than fixing: a project whose own workflow used only that status is left with a scope and no rules, which is an own *empty* workflow. That is the scope model answering correctly — the project did decide to run its own workflow — and nothing warns |
| `issue_statuses/index.html.erb` | the *not used by any workflow* badge beside a status | **left alone.** It asks `WorkflowTransition.where('old_status_id = ? OR new_status_id = ?').exists?` with no `project_id` predicate, on 5.1, 6.1 and 7.0 alike, so with the plugin installed the badge is computed across the generic rules and every project's. That is the better answer for a status a project uses, and the wrong one for a project row with no scope, which applies to nothing (INV-3). It is a badge, not a gate — the Delete link beside it is rendered unconditionally — and correcting it would mean a sixteenth Deface override, one more anchor to go stale (INV-9), for a hint |
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

### What an administration save costs

The administration screens take a selection, and "all projects" is one of the
things they take. A save then writes the whole matrix once per project: for each
one, a `touch_scopes` UPDATE, one DELETE per rule group and the inserted rows in
batches of a thousand. The row count is the honest part of that — a matrix of
*s* statuses is about *s²* cells, and the operator asked for it — but the round
trips are not, so the whole save is one transaction rather than one per project.

Scope creation is deliberately *not* batched — Jan's decision of 2026-08-27,
not merely the safe default — and was briefly batched by mistake.
0.1.1 wrote the rows with `insert_all`, which the forbidden-constructs table in
`CLAUDE.md` allows only in the two rule writers — and which, being the skipping
form of the statement, reported a row it had silently dropped as created. It is
one validated `save!` per combination again: `ScopeWriter.create_scopes` returns
the combinations it actually inserted, and *give own workflow* clears and copies
rules only for those.

What remains one statement per combination is `WorkflowRule.copy_generic_to_project`,
which *give own workflow* calls once per (project, tracker, role) it enables. It
is an `INSERT ... SELECT` whose only difference between calls is the target
project id, so the set-based form would be a join against a literal list of
triples — spelled three different ways across PostgreSQL, MySQL and MariaDB.
Accepted rather than fixed, for the same reason as the `OR` growth below: it is
one administration action, the growth is linear, and the confirmation dialog
already says how many combinations it is about to touch.

The project selector the plugin adds to those screens materialises every project
in the installation, archived ones included, as `<option>` elements — on the
summary page, both matrices, the copy screen and the inventory's filters. Core's
workflow screens have no such control, so this is a cost the plugin introduces.
Accepted at this size: it is the administration section, the list is the same one
Redmine renders on its own project pages, and narrowing it would mean deciding
which projects an administrator may not configure.

`Issue#tracker=` is the one place the resolution sits on a user's path, and only
when the tracker actually changes — an ordinary issue save asks nothing. A
single tracker change is two queries. A **bulk** tracker change is two per
distinct project in the selection, where core is one for the whole selection,
because core hands the same `Tracker` instance to every issue and memoises on
it. The plugin's request cache is keyed by (project, tracker), so it collapses
the repeats inside a project but not across projects. Recorded as finding G02.

## Views

Fifteen Deface overrides in twelve files. Eleven are on the administration
screens; two are on `workflows/_form`, which the project matrices render as
well, so one pair serves both; and the last two are on the issue form, one per
branch of the way core renders the status control:

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
| `issues/_attributes` | the `f.select :status_id` expression (after) | the link to the workflow panel (WP8) |
| `issues/_attributes` | the `l(:field_status)` expression (after) | the same link, where core renders no select — the own-empty case |

The summary page's count cell is a *surround* on one side and a *replace* on the
other because the two halves belong on either side of core's heading, and
because the cell itself differs between versions: 5.1 renders an `icon-not-ok`
span instead of a zero, 6.0 and later colour the number. The anchor is the part
the two shapes have in common — the url hash — and
`RedmineProjectWorkflows::VersionHelper` decides which shape to reproduce.

The scope panel renders only when the selection contains at least one real
project. An administrator who does not use the plugin sees core's screens
unchanged.

The fifteen overrides in the table above hang on twelve distinct anchors -- ten
on the administration screens, where three of them serve `workflows/edit` and
`workflows/permissions` alike, and two on the issue form. All twelve exist
verbatim in Redmine 5.1, 6.1 and 7.0, and `workflows/edit`, `permissions` and
`copy` are byte-identical between 6.1 and 7.0. The two on `workflows/_form` are header *cells* rather than the toggle
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

### Comparing a project's workflow with the generic one

A scope **replaces** (**INV-5**), so the only question there is to ask about the
relationship between the two workflows is *which cells differ*: there is no merge
to explain and no precedence to work out. The comparison screen answers exactly
that, read-only, at
`projects/:project_id/workflow/compare?tracker_id=&role_id=&rule_type=`.

`Services::WorkflowComparison` reads both populations with an explicit
`project_id` — the project's id and `nil` (**INV-4**) — in **three** queries
whatever the size of the matrix: one per side, plus one for the statuses either
side names. The rule counts come out of the rows already plucked rather than out
of a `COUNT` of their own, and they count **rows** — duplicates included — because
that is what the settings tab and the inventory count, and two screens must not
describe the same combination with different numbers.

**The unit of comparison is the grid, not the row.** Core's transitions screen
draws three: the plain one, plus *additional transitions when the user is the
author* and *…the assignee*. `WorkflowsController#edit` partitions the rows as
`reject { author || assignee }`, `select(&:author)` and `select(&:assignee)`, so a
row with **both** flags set appears in two grids at once. The comparison
partitions them the same way and compares grid against grid, which is what makes
its answer match what the screen shows rather than what the table holds.

Field permissions have a third state transitions cannot have — both sides say
something about a (status, field) and they disagree — so a permissions difference
carries each side's rules as well as the label.

Each side's rules is a **list**, not a value, and that is load-bearing. Nothing
stops the table holding two rows for the same (status, field) that disagree; it
is a contradiction for an administrator to settle rather than a difference to
show, and `rake redmine_project_workflows:deduplicate_workflow_rules` only
removes *exact* duplicates. Picking one of the two would make the page depend on
the order the database returned them, so the same installation would compare
differently on PostgreSQL and on MySQL — a cross-database divergence hiding
behind a green nine-cell matrix, which is worse than a red one. Core does not
pick either: `WorkflowsHelper#field_permission_tag` renders such a cell as "no
change" precisely because it cannot. So the comparison shows both.

A difference may also name a field the project's own matrix cannot show — a core
field the tracker has since had disabled, or a custom field removed from it. The
rule is still in the table and still a difference, and there is no control
anywhere on a project screen that can change it, so the page says so in a
footnote rather than leaving the reader hunting for one.

Every line says which side it is on, in words, with the class carrying nothing
but colour: *Only in this project*, *Only in the generic workflow*, *Different*.
There is no "wins" column, because there is no contest: with a scope in place the
generic rules do not apply at all, which is what the sentence above the table
says.

Two states of the screen are not tables:

- A combination the project **inherits** has nothing to compare — its workflow
  *is* the generic one — and the page says so. This also keeps a pre-WP1 database
  honest: rows stored against a project with no scope apply to nothing
  (**INV-3**), so listing them as differences would name rules that are not in
  force.
- An own workflow **identical** to the generic one says that in a sentence rather
  than showing an empty table.

The ordering is computed in Ruby — core's own order, "new issue" first and then
by status position, with the ids as a tiebreaker — because CI runs on three
databases with a random seed and an order that falls out of a query is not an
order.

Three entry points, all built by one helper so they cannot drift about when the
link is offered: the project settings tab, the header of either project matrix,
and the administration inventory. The inventory's link leads out of the
administration section into a project screen, and a project whose configuration
has moved on since the scope was created refuses it — honestly, because the
combination still has a scope and the project no longer offers the matrix to
compare it against:

| What changed | Answer | Where it comes from |
| --- | --- | --- |
| the issue tracking module was disabled | **403** | `authorize` → `Project#allows_to?` → `deny_access` |
| the project was archived | **403** | the same, with core's archived message |
| the tracker was taken off the project | **404** | `find_tracker_and_role`, which matches against `ProjectOptions.trackers` |
| the role lost its last member in the project | **opens** | the same, against `ProjectOptions.visible_roles`, which adds every role that already has a scope for this project |
| …and the role has no scope here either | **404** | there is nothing for the project to decide or undo |
| the combination has no scope and the role has no member | **403 on *give own workflow* only** | `require_offered_role`; every other action acts on a scope that already exists |

Rendering the link conditionally instead would mean preloading each row's enabled
modules, trackers and member roles to answer a question the link itself answers.
*(This table read "404" for all four until the WP6 review checked it against
core's `ApplicationController`; the role rows changed again for finding F05,
which found that refusing a role with no member hid a workflow that was still in
force.)*

### The audit trail

`project_workflow_scopes` has carried `created_by_id` and `updated_by_id` since
WP1's migration. They answer two different questions, and that is why a repeated
save moves one and not the other:

| Columns | What they record |
| --- | --- |
| `created_by_id`, `created_at` | who decided this project runs its own workflow here — never rewritten |
| `updated_by_id`, `updated_at` | who last changed the rules |

`ScopeWriter.touch_scopes` is the only stamp, and `ensure_scopes` calls it
*before* it creates anything, so a row inserted by the same call is not
immediately stamped a second time with an `updated_at` later than its own
`created_at`. Emptying a matrix goes through the same method, and so does the
**copy screen** — a copy into a project that already has a scope deletes and
rewrites its rules and creates nothing, so without a stamp the audit line would
go on naming whoever last saved that matrix by hand. Only existing scopes are
touched: a combination that inherits has no row, and creating one there would
collapse "save" into "enable" (**INV-3**).

`ScopeCopier`, which duplicates scopes along with a role or a tracker, needs no
stamp: core calls `Role#copy_workflow_rules` and `Tracker#copy_workflow_rules`
only on one it has just created, so the target cannot already carry a scope, and
every row it writes is created rather than overwritten.

The touch covers every combination in the write's selection rather than only the
ones whose rules end up different. A matrix save submits and rewrites the whole
matrix for the whole selection, so *this workflow was saved by this person* is
true of all of them; distinguishing a rewrite that changed nothing would mean
diffing every cell on a path that already writes the lot.

`InventoryQuery` carries the pair into its `Cell`, and the sentence is core's own
`authoring` helper with `label_updated_time_by` — already translated in every
language Redmine ships, so there is no string of the plugin's own here. Nothing
is rendered where there is nothing to say: an inheriting cell has no scope, and a
scope the WP1 backfill wrote has a time and **no** author, which would otherwise
read as "Updated by Anonymous" and name somebody who was not there.

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
page — the deviating combinations, the scopes, one count per rule type, and the
users its audit line names.

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
single project, so the tab costs a fixed number of collection queries whatever
the number of trackers and roles, and never one per row: three for the lists of
trackers and roles, and three or four for the rows — the scopes, one count per
rule type, and, since WP6, the users the audit line names. *(The number here
read "four" until WP6 measured it; the constant-cost property was right and the
count was not.)*

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

## Telling the end user what the workflow is (WP8)

An issue's status dropdown lists the statuses the workflow permits and says
nothing about why. With per-project workflows that gap gets worse rather than
better: two projects on the same tracker now offer different choices, and the
person editing the issue has no way to see which rules govern them. This section
is what WP8 built.

### What Redmine already does — do not rebuild it

**Core already ships a status help icon on the issue form**, on 5.1, 6.1 and 7.0
alike. `issues/_attributes.html.erb` renders, next to the status select:

- an `icon-help` link (a `sprite_icon('help', …)` from 6.0, a CSS icon on 5.1)
  labelled `label_open_issue_statuses_description`;
- opening core's own `#issue_statuses_description` modal — a `<dl>` of status
  name and `IssueStatus#description`, where clicking a name *applies* that
  status to the form;
- and the current status's description as the select's own `title` tooltip.

`IssueStatus#description` is a real core column on every supported version — a
255-character string an administrator fills in at *Administration → Issue
statuses*. The icon renders **only** when at least one of the available statuses
has one, which is why an installation that has never filled them in concludes
the feature does not exist.

Two consequences for this plugin:

1. **The first half of the requirement is already met, and this plugin is what
   makes it correct.** The modal lists `@allowed_statuses`, which is
   `Issue#new_statuses_allowed_to` — a method the plugin *replaces* in full. So
   the help icon already describes the project's own effective workflow rather
   than the generic one. That is worth a spec of its own (INV-4: the icon must
   never name a status another project's rules reach) and a paragraph in the
   README, not new code.
2. **What is missing is the map.** Nothing in core draws the transitions as a
   graph, and nothing in core says *why* a status is absent from the dropdown.

### The transition map

A second icon beside core's, opening a modal of the plugin's own: **the workflow
this issue is actually governed by.** Two parts, because they answer two
different questions. **The local one is what shipped**, per the decision below;
the whole map is what the drawing option would need.

**From here.** The local view, and the one an end user wants: the current status,
the statuses it may move to, and per edge the condition core stores on it —
unconditional, *only as author*, *only as assignee* — together with which of the
user's own roles grants it. Plus the statuses that can reach the current one, so
"how did this issue get here" is answerable.

**The whole map.** Every status in the effective workflow for this issue's
project, tracker and the user's roles, and every transition between them,
including core's `old_status_id = 0` row — the *new issue* pseudo-status, which
is where a Jira-style diagram starts. *(Out of WP8 as built, per the decision
below: the local view is what ships, and the whole map is what the SVG option
would need.)*

### Which workflow is this, and where do I change it

Nothing on the issue form says today whether an issue is governed by its
project's own workflow or by the generic one. Core cannot say it — core has no
concept of a project workflow — and WP8 is the first thing this plugin puts on
that form at all, so the panel is where it belongs.

It is the first thing somebody debugging *why can I not close this issue* needs,
and it is the difference between a user filing a bug report and a user opening the
right screen.

**The words are the ones the rest of the plugin already uses** — *Own workflow*,
*Own empty workflow*, *Inherits the generic workflow* (**INV-3**). The project
settings tab, the administration inventory and the comparison screen all name the
three states in exactly those words, and an issue form that invented a fourth
phrasing for the same thing would make the two screens look like they were
describing different mechanisms.

**Per role, because resolution is per role.** A user holding two roles in a
project can have one of them overridden and the other inheriting, and the
transitions they see are the union (**INV-5**, and the *Roles resolve
independently* rule above). One sentence where the roles agree; a line per role
where they do not. The panel already knows the answer: it resolves the scope to
build the transition list at all, and that resolution is one cached point lookup
(**INV-6** — there is no parent project in the sentence, ever, so it never has to
say "inherited from").

**The state that most needs saying is the empty one.** A project with its own
*empty* workflow offers no transition at all, and an empty status dropdown with
no explanation is indistinguishable from a broken plugin. That is the one case
where this sentence stops being a convenience.

**Where to change it, gated by permission.** The sentence carries a link:

| Who is reading | Link |
| --- | --- |
| `manage_project_workflow` on this project | the project's **Workflow** tab, at this tracker and role |
| `view_project_workflow` only | the same tab, which is read-only for them anyway |
| a system administrator | *Administration → Workflow*, pre-filled with this project, tracker and role |
| anybody else | no link — the sentence alone |

The link is a convenience, not a capability: every screen it leads to authorizes
again (**INV-7**), so the gate is a UX decision rather than a security boundary.
Offering a link that answers 403 is worse than offering none, which is why the
last row exists.

### The map must not contradict the dropdown

This is the part that decides whether the feature helps or hurts.
`new_statuses_allowed_to` does more than read the workflow: it drops closed
statuses when `closable?` is false (an open subtask, a blocking issue) and open
ones when `reopenable?` is false (a closed parent), and it filters the author and
assignee variants by who the current user actually is. A map drawn from the
workflow rows alone therefore shows edges the dropdown does not offer.

So the map states which it is showing. An edge the workflow permits but this
issue and this user cannot take now is drawn as permitted **and** marked with the
reason — the same sentence core puts in `Issue#transition_warning` where core has
one. The dropdown stays the authority for "what may I do this minute"; the map
answers "what does this workflow allow, and why is that not on offer". Anything
less honest is worse than no map, because it invites a support ticket per edge.

### The empty case is worse than it sounds

`new_statuses_allowed_to` appends the issue's own status to its answer *only when
the workflow permitted something* — `statuses << initial_status unless
statuses.empty?`. So an **own empty workflow** does not give the reader an empty
dropdown: it gives them **no status control at all**, because
`issues/_attributes` renders the select only `if @allowed_statuses.present?` and
otherwise falls back to `<p><label>Status</label> New</p>`. No select, no help
icon, no modal, and nothing anywhere on the form saying why.

**And it is not only the empty-workflow case.** The same thing happens on a
plain generic workflow with no scope anywhere, for any status with nothing
leading out of it for the reader's roles — a terminal *Closed*, most obviously.
So the branch is not a plugin corner at all: it is where a reader is *most*
likely to want the panel, because nothing else on the form explains it. That is
why the link is anchored in **both** branches of core's `if`, and why the
INV-9 count is fifteen rather than fourteen.

Measured rather than assumed, on all three versions:
`spec/integration/issue_status_help_spec.rb` and the `IssuesController` group in
`spec/integration/deface_overrides_spec.rb`. It is the strongest argument for
the panel, and the reason the panel's own sentence about the empty case is not
optional.

### How it is drawn

Server-side, lazily: the issue form gets a link and runs no extra query, and the
modal's content comes from an action of the plugin's own — filling core's
`#ajax-modal`, exactly as core's own *New version* and *New category* links on
the same form do, so the modal, its close behaviour and its styling are
Redmine's and the plugin ships no JavaScript for it. A browser without
JavaScript follows the link to the same content as a page of its own. The
resolver's hot path (**INV-6**, **G6**) is untouched — an ordinary issue edit
costs exactly what it costs today.

**The renderer is the local view and nothing else** — decided **C** by Jan on
2026-08-26. A `table.list` of *from → to → condition*: the statuses this issue
can move to, the statuses that can lead into it, and what each move requires. No
layout pass, no drawing, readable by anything.

That is a deliberate narrowing of the requirement, not a shortcut around it. The
two rejected options were a **layered inline SVG** — what Jira draws, and what
needs a layering pass, a crossing-reduction pass, a plan for long status names
and for both Redmine themes, *and* this same table beside it, because no `aria`
attribute makes a drawing readable by a screen reader — and a **read-only copy of
the administration tick-box grid**, which is nearly free and is a matrix rather
than a map.

A is still reachable from here: a layered diagram is exactly this data with a
layout pass added, so building the table first makes the drawing an increment
rather than a gamble, and the table remains the accessible representation
underneath it.

### Scope, authorization and cost

| Decision | Why |
| --- | --- |
| The single-issue form, new and edit — `issues/_form` through `issues/_attributes` | one issue, one project, one tracker: one map that is true |
| **Not** the bulk-edit form | a selection can span projects and trackers, so one map would be a lie about most of the selection |
| **Not** the issue show page in WP8 | worth doing, and a scope of its own — the reader there may have no permission to change anything |
| Authorization: the issue through `Issue.visible`, or for an unsaved issue the project plus `add_issues` | the map reveals the workflow governing an issue the user is already looking at, so it needs no permission of its own |
| The tracker comes from the issue; on the new-issue form it arrives as a parameter and is **matched against the project's own trackers** | **INV-7** — no request parameter may widen the scope, and Rails resolves `where(id: ['1e5'])` to record 1 |
| The roles are the user's own roles in that project | the dropdown reflects exactly those, and the map's whole job is to explain the dropdown |
| One scope lookup plus one transitions query, both carrying an explicit `project_id` | **INV-4** |
| No permission of its own, and a controller of its own rather than an action on `ProjectWorkflowsController` | every action there is behind `view_project_workflow`; requiring that to read the workflow governing your own issue would hide the panel from the people it is for |
| The condition of one *move* is worded "only when the user is the author", not the comparison screen's "also when…" | there the label names a whole grid, which is core's framing; here the conditions of one move have been collapsed, so a move naming only the author grid is one only the author may make, and "also" would say the opposite |

The anchor is core's `f.select :status_id` expression in
`issues/_attributes.html.erb`, which is byte-identical in 5.1, 6.1 and 7.0 — the
help icon beside it is *not*, because 6.0 replaced its CSS icon with a sprite.
That override raises the count of **INV-9** overrides, which is written down in
`CLAUDE.md`, in this document and in the spec's own comment, and it needs an
assertion in `spec/integration/deface_overrides_spec.rb` that only it can
satisfy.

## Supported versions

| Redmine | Rails | Ruby used in CI |
| --- | --- | --- |
| 5.1 | 6.1 | 3.2 |
| 6.1 | 7.2 | 3.3 |
| 7.0 | 8.1 | 3.3 |

Against PostgreSQL, MySQL and MariaDB. The break in core is between 5.1 and
6.0 (SVG sprite icons replaced CSS icons), not between 6.1 and 7.0.
Version-conditional code stays behind one helper.
