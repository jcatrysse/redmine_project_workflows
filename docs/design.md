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

A **scope** records the decision itself:

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

| Action | Scope | Rules |
| --- | --- | --- |
| Enable a project's own workflow | created | copied from generic, or none — the operator chooses, copy preselected |
| Return to inheritance | deleted | deleted |
| Empty the matrix | kept | deleted |

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

| Core code | Concern | Treatment |
| --- | --- | --- |
| `Issue#new_statuses_allowed_to` | which transitions a user may make | replaced by the plugin when a scope applies |
| `Issue#workflow_rule_by_attribute` | field permissions | same |
| `Project#rolled_up_statuses` | fills the status filter and the status report | project-aware, and **no role filter** — core has none either, and adding one empties the list for projects without members |
| `Tracker#issue_status_ids` | whether a status survives a tracker change | left as a global union on purpose: narrowing it to generic rules would strip a status from an issue in a project whose own workflow uses it. The two call sites in `Issue` are made project-aware instead |
| `WorkflowsController#index` | the summary page | counts per scope rather than mixing project and generic rows |
| `WorkflowRule.copy` (role and tracker copy) | duplicating a role or tracker | project rules and their scopes are copied along, so a copied role is a working copy |
| `IssueStatus#delete_workflow_rules` | deleting a status | no change needed — it deletes by status id, which covers project rows too |

## Views

Five Deface overrides, all on admin screens:

| View | Anchor | Adds |
| --- | --- | --- |
| `workflows/edit` | `div.autoscroll` | hidden `project_id[]` fields |
| `workflows/edit` | the `submit_tag l(:button_edit)` expression | the project selector |
| `workflows/permissions` | `div.autoscroll` | hidden `project_id[]` fields |
| `workflows/permissions` | the `submit_tag l(:button_edit)` expression | the project selector |
| `workflows/copy` | the `source_role_id` / `target_role_ids` select expressions | source and target project selectors |

All five anchors exist verbatim in Redmine 5.1, 6.1 and 7.0, and
`workflows/edit`, `permissions` and `copy` are byte-identical between 6.1 and
7.0. `spec/integration/deface_overrides_spec.rb` asserts that each override
actually reaches the rendered page (**INV-9**).

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
