# Changelog

## 0.1.0

The release that makes "this project has its own workflow" a thing the database
records rather than something inferred from whether rows happen to exist. That
inference could not tell a deliberately empty workflow from an absent one, and
it silently returned a project to the generic workflow when its last rule was
deleted.

**Upgrading:** the migration backfills the new table, so a project that was
already working keeps working. Read
[Upgrading and uninstalling](README.md#upgrading-and-uninstalling) first —
especially before uninstalling, which removes every project-specific rule.

**Breaking:** the declared minimum is now Redmine **5.1**. It was 5.0, which
nothing had ever tested.

### The model

- A project's decision to run its own workflow is a row in
  `project_workflow_scopes`, separately for status transitions and for field
  permissions. Three states are now distinguishable and stay distinguishable:
  *inherits the generic workflow*, *own workflow*, *own empty workflow*.
- A project workflow **replaces** the generic one for the tracker and role it
  covers. There is no merging and there are no negative rules.
- No inheritance between projects: a subproject has its own workflow or uses the
  generic one.
- Every query against `workflows` names a `project_id`, so one project can never
  read another's rules — or have them counted into its totals.

### Correctness at Redmine's own seams

- `Project#rolled_up_statuses` is computed per project across the tree and
  unioned, with no role filter — which is what core does, and what stops the
  status filter coming back empty for a project without members.
- The two `Issue` call sites that asked a tracker which statuses it uses now ask
  the issue's own project's effective workflow. `Tracker#issue_status_ids` stays
  a global union on purpose.
- Copying a role or a tracker carries the project rules and their scopes along,
  so a copied role is a working copy.
- `rake redmine_project_workflows:deduplicate_workflow_rules` repairs a database
  that already has duplicate rules; the writers cannot produce new ones within a
  save.
- Redmine's own `WorkflowTransition.replace_transitions` and
  `WorkflowPermission.replace_permissions` are routed through those writers, so a
  generic save can never delete a project's rules. **This changes the generic
  screens slightly even on an installation with no per-project workflow:** the
  writers whitelist `rule`, `field_name` and status ids against server-built
  lists, which is narrower than core, and a rejected entry is dropped before the
  delete so it leaves the rule it names alone rather than clearing it. The
  matrices cannot produce a rejected value; a hand-built request can.

### Screens

- The **Summary** page counts the workflow you selected instead of mixing
  populations, and its links carry the selection.
- A **Workflow inventory**: one line per project, tracker and role, with the
  state in words, filters, and a link into each matrix.
- A **Workflow** tab in project settings, behind two new permissions
  (`view_project_workflow`, `manage_project_workflow`), so a project can run its
  own workflow without a system administrator. Every action authorizes against
  the project it acts on.
- **Row and column actions** on every transition matrix — Yes, No and
  *(No change)* — which reach the mixed-value cells Redmine's own check-all
  toggle cannot. With a count of what changed, an **Undo**, and a line saying
  nothing is written until Save.
- A **comparison** screen: which rules a project's own workflow has that the
  generic one does not, and the other way round, for one tracker and role.
- **Who last changed a workflow, and when**, on the project tab and in the
  inventory, kept separately from when the decision was taken.

### Settings

- One setting: *Ask before a row or column action changes more than* — 50
  workflow rules by default, `0` to ask every time.

## 0.0.3

- Fix migration/index guards and controller 404 return safety.
- Add workflow project foreign key with cascade cleanup behavior.
- Improve i18n coverage and selector/role-resolution robustness.

## 0.0.2

- Refactor "Only display statuses that are used by this tracker" to only display statuses that are used by the selected project.

## 0.0.1

- Initial release.
