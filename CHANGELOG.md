# Changelog

## 0.1.1

Two defects on the path "an administrator presses Save", found by a review of
0.1.0 and fixed here. Both could lose configuration silently, and one of them
changed what stock Redmine does.

**Upgrading:** no migration. Nothing in the database changes.

### Fixed

- **A cell left at *(No change)* is left alone.** One cell of the transitions
  matrix is three controls — the plain grid and the *author* and *assignee* grids
  below it — over two stored rows. The writer deleted on the cell rather than on
  the rule, so a single changed column deleted the rows of the other two: a
  selection where one workflow permitted a transition and another did not lost
  that transition on the next save, and reported "Successful update". Because the
  plugin routes Redmine's own `WorkflowTransition.replace_transitions` through
  that writer, this applied to the generic workflow as well as to a project's.
- **Saving a matrix no longer gives a project a workflow of its own.** The
  administration grid shows the rules the selection holds *itself*, so a project
  that inherits renders empty — and pressing Save wrote that emptiness back as an
  own **empty** workflow, in which no issue in the project can change status.
  Saving now writes only into combinations the project has already taken over,
  says how many it left alone, and the panel above the matrix says so before
  anything is pressed. The three state actions are the only way to take a
  workflow over, on every screen; the project's own tab already worked this way.
- A malformed matrix submission is rejected instead of raising, on the
  administration screens as it already was on a project's own.
- A matrix save is one transaction over the whole selection, so a failure part
  way through no longer leaves half of it rewritten.
- `Issue#workflow_rule_by_attribute` is private again, as it is in Redmine.
- The link the plugin adds to the issue form no longer raises if another plugin
  renders Redmine's issue form from a controller of its own.
- The threshold field on the settings screen refuses anything that is not a
  whole number, rather than accepting it and quietly using the default.
- Spanish, Portuguese and Polish used two or three different words for *tracker*
  and *role* between them; all three now use Redmine's own.

### Changed

- Giving many projects their own workflow at once no longer makes one database
  round trip per combination.

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
- The copy screen rejects a source or target tracker or role that does not
  exist, instead of reading it as "any" or quietly dropping it. Redmine spells
  "copy from every tracker" and "that tracker is gone" the same way — both are
  `nil` — and drops an unknown target id from its query, so a stale form could
  copy from a source nobody chose, or report success for a selection it had only
  half applied. **This applies to the generic copy screen too,** with or without
  a per-project workflow: a selection that names something real still behaves
  exactly as before.
- The copy screen's **target project** control preselects *Generic*. A
  multiple-choice control with nothing selected sends nothing at all, so a copy
  form that showed no target project still copied into the generic workflow and
  reported success. What runs is now what the form shows. The **source** project
  control is unchanged: blank there already means the generic workflow and
  destroys nothing.

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
- On the issue form, a **Workflow for this issue** panel beside Redmine's own
  status help icon: which of the three states governs the reader — per role,
  because a role can be overridden while the next inherits — what the workflow
  lets this issue move to, what leads into its current status, and, for anything
  the workflow permits but the status list is not offering, the reason. Redmine's
  own sentence where Redmine has one (an open subtask, a blocking issue, a closed
  parent), the plugin's where the reason is who the reader is. The link is there
  even when Redmine renders no status control at all — which an own empty
  workflow produces, and so does a plain generic workflow at any status with
  nothing leading out of it. Loaded when it is opened, so an ordinary issue edit
  costs nothing extra.
- Redmine's own status help icon on that form needed no change and is now
  covered by specs: the statuses it lists are the project's own effective
  workflow, never another project's. It is invisible until an administrator fills
  in **Administration → Issue statuses → Description**, which the README now
  says.

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
