# Redmine plugin: Project Workflows

*WARNING: alpha stage, do not use in production!*

This plugin adds project-specific workflows to Redmine by extending the core
`workflows` table with a nullable `project_id`. Generic rules
(`project_id = NULL`) behave exactly like Redmine core, while a project's own
rules **replace** the generic ones for the trackers and roles it has taken over.

The specs pass on Redmine 5.1, 6.1 and 7.0, against PostgreSQL 16, MySQL and
MariaDB. Redmine 5.1 with PostgreSQL is the combination in day-to-day use; the
others are covered by CI only.

## What to know before you install it

Everything here is a consequence of the design rather than a defect, and every
one of them has surprised somebody.

- **A project workflow replaces the generic one; it never adds to it.** Once a
  project has its own workflow for a tracker and a role, the generic rules for
  that combination do not apply at all — not as a fallback, not for the
  transitions the project did not mention. Adding one transition to a project
  means its workflow is now the whole answer for that tracker and role.
- **An empty own workflow permits nothing**, and that is a state you can reach
  deliberately. For transitions it means no issue in that project can change
  status for that role. This is why *give own workflow* starts from a copy of
  the generic one by default.
- **Nothing is inherited between projects.** A subproject does not get its
  parent's workflow; it either has its own or uses the generic one. Use the
  copy screen to apply one workflow to several projects.
- **Roles resolve independently, and the result is a union.** A user who holds
  two roles in a project may make any transition either role permits. A project
  can override one role and inherit for another.
- **An issue can end up on a status its project cannot leave.** Move an issue
  into a project whose workflow does not use its current status, or change a
  workflow under issues that are already open, and those issues sit on a status
  with no transition out of it for that role. Redmine behaves the same way when
  an administrator edits the generic workflow; per-project workflows just make
  it reachable more often. The comparison screen (below) is the fastest way to
  see it coming.
- **The plugin answers `Issue#new_statuses_allowed_to` itself**, for inheriting
  projects too, rather than falling back to Redmine's own query — Redmine's
  carries no `project_id` and would let one project read another's rules. If
  another plugin patches the same method, load order decides which of you wins.
- **Installing it changes the generic workflow screens too, slightly.** The
  plugin routes Redmine's own `WorkflowTransition.replace_transitions` and
  `WorkflowPermission.replace_permissions` through its writers — it has to, or a
  generic save would delete projects' rules along with the generic ones. Those
  writers validate what they are given against server-built lists, which is
  narrower than core: core accepts any run of digits as a field name, the plugin
  accepts only a core field or an existing custom field id. An entry that fails
  is dropped before anything is deleted, so it leaves the rule it names alone
  rather than clearing it. In practice this only shows up for a hand-built
  request; the matrices themselves cannot produce a rejected value.
- **Uninstalling is a data change, not just a code change.** See
  [Upgrading and uninstalling](#upgrading-and-uninstalling).

## Features

- Project-specific status transitions and field permissions.
- A **Workflow** tab in project settings, so a project can run its own workflow
  without a system administrator — behind two permissions.
- A **Workflow inventory** answering which projects have taken a workflow over.
- Row and column actions on every transition matrix, which reach the mixed cells
  Redmine's own check-all toggle skips — with a count of what they changed, an
  **Undo**, and a reminder that nothing is written until you press Save.
- A **comparison** screen saying exactly which rules a project's own workflow has
  that the generic one does not, and the other way round.
- **Who last changed it, and when**, on the project's Workflow tab and in the
  inventory.
- On the issue form, a **Workflow for this issue** panel: which workflow governs
  you, what it lets this issue move to, what leads into its current status, and
  why anything the workflow permits is not on offer right now.
- Optimised SQL performance for bulk workflow transition/permission updates.

## Installation

1. Copy this plugin directory into `plugins` of your Redmine installation.
2. Run dependencies and plugin migrations:
   ```
   bundle install
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows
   ```
3. Restart Redmine.

`RAILS_ENV` is not optional. Redmine's plugin migration task loads the
environment it is given and defaults to **development**, so leaving it off
migrates the wrong database and tells you it worked.

## Usage

1. Go to **Administration → Workflow**.
2. Select Role, Tracker, and Project.
   - **Generic** means the workflow every project uses unless it overrides it.
   - Selecting a real project shows that project's own workflow.
3. A project has its own workflow only once you give it one. The panel above the
   matrix says which of three states the selection is in and offers the three
   actions that move between them:
   - **Inherits the generic workflow** — nothing is stored for this project.
   - **Own workflow** — only the project's own rules apply; the generic ones do
     not. A project workflow *replaces*, it never adds.
   - **Own empty workflow** — the project has its own workflow and it permits
     nothing. This is a deliberate state, not an error.

   Giving a project its own workflow starts from a copy of the generic one by
   default, because an empty one would allow no transition at all.

4. **Summary** counts the workflow you selected. Without a project selected that
   is the generic workflow, exactly as before; select a project and the grid
   counts that project's own rules.
5. **Workflow inventory**, reached from the link next to *Summary*, answers the
   question the grid cannot: which projects have taken a workflow over. One line
   per project, tracker and role, with the state in words and a link into the
   matrix it describes. It shows only the projects that decided something unless
   you ask for everything.

### Selecting more than one project

The administration screens take a selection, not one project: several trackers,
several roles, and several projects, with **Generic** as one more entry in that
list. What that means when you save:

- **Every cell you leave alone stays alone.** A cell whose value differs across
  the workflows in the selection carries a *(No change)* option, and saving with
  that option selected leaves each of those workflows exactly as it was. On the
  transitions matrix such a cell becomes a dropdown where an agreeing cell is a
  plain checkbox, so you can see at a glance which cells disagree; on the field
  permissions matrix every cell is a dropdown already, and *(No change)* is one
  more entry in it. On the transitions matrix one cell is three of these — the
  plain grid and the two below it, *when the user is the author* and *…the
  assignee* — and each of the three is left alone on its own, whatever the other
  two say. (Before 0.1.1 it was not: one changed column dragged the other two
  down with it.)
- **Every cell you do change is written to all of them.** One click on a
  checkbox with three trackers, two roles and ten projects selected writes sixty
  workflows. Whenever one cell stands for more than one workflow, a sentence above
  the matrix gives that number for the selection you have; and a row or column
  action asks for confirmation once it would pass the threshold in the plugin's
  settings.
- **The three state actions act only where they mean something.** *Give own
  workflow* touches only the combinations that currently inherit, so pressing it
  twice does not discard what the first press produced. *Empty this workflow*
  touches only combinations that already have their own. *Return to the generic
  workflow* deletes both the rules and the record of the decision.
- **Saving does not give a project a workflow of its own.** Those three actions
  are the only thing that does. A combination that still inherits shows as an
  empty matrix — the grid shows the rules the selection holds *itself*, and an
  inheriting one holds none — and Save leaves it exactly as it was rather than
  writing that emptiness back. The panel above the matrix says how many
  combinations of your selection are in that state, and a message after the save
  says how many it left alone.
- **Generic is not a project.** Selecting it alongside real projects edits the
  generic workflow as one more member of the selection; it cannot be given its
  own workflow, emptied as a scope, or returned to inheritance, because it *is*
  what inheritance points at.

### Letting a project manage its own workflow

Two permissions, under *Issue tracking* in **Administration → Roles**:

- **View the project's workflow** — read the project's own **Workflow** tab.
- **Manage the project's workflow** — give the project its own workflow, edit
  it, empty it, and return it to the generic one. For that project only.

A role that has either one gets a **Workflow** tab in **Project settings**, with
one line per tracker the project has enabled and role that somebody holds in it.
Each line says which of the three states above that combination is in, how many
rules the project holds itself, and offers the actions that would change it.
Clicking the number opens that combination's matrix.

Three things are worth knowing:

- **One combination at a time.** The project matrix edits one tracker and one
  role; the tab is the list. The administration screens are still where you edit
  many at once.
- **A combination the project has not taken over is read-only**, and shows the
  generic workflow — which is exactly what applies to it — so you can see what
  you would be copying before you copy it.
- **The builtin roles are not on the tab.** *Non member* and *Anonymous* have no
  members in any project, so they go on following the generic workflow. A system
  administrator can still give a project its own workflow for them from
  **Administration → Workflow**.

### Filling a matrix in fewer clicks

Every row and every column of a transition matrix carries three actions next to
its name: **Yes**, **No** and **(No change)**. They set that whole row or column
at once.

Redmine's own check-all toggle is still there and still does exactly what it did.
What it never reached is a cell whose value differs across the selection you are
editing: such a cell renders as a dropdown rather than a checkbox, and a toggle
that selects checkboxes skips precisely the cells with the manual work in them.
The three actions reach both kinds of cell.

**(No change)** appears only where a cell can hold it — that is, when the
selection covers more than one workflow. It puts every cell in the row or column
back to the value the page was opened with, which is what a mixed cell means:
leave each of those workflows as it is. A sentence above the matrix says how many
workflows one cell stands for, so you can see how much a single click is about to
write.

**Undo, and what is not saved yet.** A row or column action changes the screen
and nothing else — only **Save** writes. Above the matrix, once you have used
one, a line says how many cells changed and how many workflow rules that stands
for, offers **Undo**, and says in as many words that nothing has been saved. Undo
steps back one action at a time and restores the value each cell held *before*
that action, which is not the same as *(No change)*: that one goes back to the
value the page was opened with.

### Seeing what a project changed

From a project's **Workflow** tab, from either of its matrices, and from the
administration inventory, **Compare with the generic workflow** lists exactly
which rules differ for one tracker, one role and one kind of rule. Each line says
which side it is on — *Only in this project*, *Only in the generic workflow*, or,
for field permissions, *Different* with both values.

There is no "wins" column, because there is no contest: once a project has its
own workflow, the generic rules for that combination do not apply at all. A
combination the project still inherits says there is nothing to compare, and one
whose rules happen to match the generic ones says so in a sentence rather than
showing an empty table.

Next to the state on the tab and in the inventory, **Updated by … ago** says who
last changed those rules. The date the decision was taken is kept separately from
the date the rules last changed, so re-saving a matrix does not make it look like
a fresh decision.

### Explaining the status list on the issue form

Two things sit next to the status list when you create or edit an issue.

**Redmine's own help icon** — the question mark — lists every status you may pick
with the description an administrator wrote for it. This is core's, not the
plugin's, and the plugin is what makes it correct: the list it shows is your
project's own effective workflow, never another project's rules. It is invisible
until somebody fills those descriptions in, at **Administration → Issue statuses
→ Description**, which is worth doing once — an installation that has never used
that field concludes the feature does not exist.

**Workflow for this issue** — the second icon — is the plugin's, and it answers
the question the status list cannot:

- **Which workflow applies**, in the same three words the rest of the plugin
  uses: *Own workflow*, *Own empty workflow*, or *Inherits the generic workflow*.
  One line per role you hold, because a role can be overridden while the next one
  inherits, and what you see on the form is the union of both. Where you may
  change it, there is a link; where you may not, there is no link rather than one
  that answers *403*.
- **Status changes allowed from here**, with what each one requires — anyone with
  the role, only the author, only the assignee — and whether the status list is
  offering it *now*.
- **Statuses that lead to this one**, so *how did this issue get here* is
  answerable.

The panel says what the workflow allows; the status list on the form stays the
authority for what you may do this minute, and every difference between the two
carries its reason. Redmine withholds a closed status from an issue with an open
subtask or a blocking issue, and an open one from a subtask of a closed parent —
in those cases the panel shows Redmine's own sentence. Where the reason is who
you are, it says so: *Only the author of the issue may make this change.*

**The case worth knowing about.** A project given its **own empty workflow** for
your tracker and role permits nothing at all, and Redmine's response to that is
not an empty dropdown — it is *no status control on the form whatsoever*, with
nothing to say why. That is a deliberate configuration and not a fault, and this
panel is the only place that says so.

Redmine does the same thing without this plugin, for any status with nothing
leading out of it — a terminal *Closed*, most often. So the link is there
whenever the status list is not, which is where it is needed most.

It costs nothing until you open it: the form gets a link, and the panel is
loaded when you click it.

The panel is on the single-issue form — new, edit, and the inline edit form on the
issue page. It is deliberately **not** on the bulk-edit form, where a selection
can span projects and trackers, so one map would be wrong about most of it.

## Settings

**Administration → Plugins → Project Workflows → Configure** has one setting:

- **Ask before a row or column action changes more than** — a number of workflow
  rules, 50 by default. A row or column action that would change more than that
  asks for confirmation first; `0` asks every time.

## Upgrading and uninstalling

**Upgrading from 0.0.3 or earlier.** Migration 004 creates
`project_workflow_scopes` and **backfills it**: every (project, tracker, role)
that already had rules of its own gets a row saying so. That is what turns the
old implicit model — *rules exist, therefore this project overrides* — into the
explicit one, and it is why nothing changes for a project that was already
working. Run it with the usual

```
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows
```

The migration prints a line per rule type as it backfills, but not a count.
`say_with_time` prints a row tally only when its block returns an integer, and
the backfill's block returns the adapter's result object for a raw
`INSERT ... SELECT`. To see what it produced:

```
bundle exec rails runner -e production \
  'puts ProjectWorkflowScope.group(:rule_type).count'
```

It prints a hash — on Ruby 3.2 and 3.3, `{"transitions"=>12, "permissions"=>3}`.
An empty one (`{}`) means no project had rules of its own before the upgrade,
which is the normal answer on an installation that had not used per-project
workflows yet.

Two things change behaviour after the upgrade, both deliberately:

- **A project's own rules with no scope now apply to nothing.** The backfill
  gives every such project a scope, so this only bites rules written directly
  into the database afterwards.
- **The status filter and the status report are computed per project.** They used
  to be filtered by role as well, which returned nothing for a project with no
  members.

**Uninstalling.** Reverse the migrations *before* removing the plugin
directory — the plugin's tables and its column on `workflows` are not removed by
deleting the code:

```
RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows VERSION=0
```

That **deletes every project-specific rule** before dropping the `project_id`
column on `workflows`; `project_workflow_scopes` goes too, earlier in the run,
because the migrations reverse in the order they were applied. The delete is
deliberate and it has to precede the column drop: removing the column with those
rows still in the table would leave stock Redmine reading every one of them as a
*generic* rule. Your generic workflow itself is untouched.

**Take a backup first, and check the output.** There is no way back from this one,
and it is the one command here that has to run against the right database — see
the `RAILS_ENV` note under [Installation](#installation).

If you remove the plugin directory *without* running that, Redmine keeps working
— core only ever reads and writes the `project_id IS NULL` rows — but every
project rule stays in the table, invisible and inert, and comes back into force
the moment the plugin is reinstalled.

## Maintenance

Neither Redmine nor this plugin has a unique constraint on the `workflows`
table — the key would have to include two nullable columns, and every supported
database treats NULLs in a unique index as distinct
(see [`docs/design.md`](docs/design.md)). Two administrators saving the same
matrix at the same moment can therefore leave duplicate rows behind, which makes
a matrix cell render as a mixed dropdown instead of a checkbox. To clean them up:

```
bundle exec rake redmine_project_workflows:deduplicate_workflow_rules
```

It removes only rows that are identical in every column, so it cannot change
what any workflow permits. Two field permissions that agree on everything but
the rule are a contradiction rather than a duplicate, and are left for you to
settle.

## Development

Working on this plugin with an AI coding agent? Start with
[`CLAUDE.md`](CLAUDE.md) — it carries the invariants, the quality gates and the
branch discipline — and [`docs/STATE.md`](docs/STATE.md), which is where the
project keeps its memory between sessions. [`docs/design.md`](docs/design.md)
explains how the plugin decides which workflow applies;
[`docs/implementation-plan.md`](docs/implementation-plan.md) is the route from
here. Reviews run through [`docs/review/`](docs/review/README.md).

## Testing

The plugin includes an RSpec test suite. Run it from your Redmine root with:

```
RAILS_ENV=test bundle exec rspec plugins/redmine_project_workflows/spec
```

To create a throwaway Redmine host for a given version and database, see
[`dev/README.md`](dev/README.md):

```
dev/setup.sh 5.1-stable postgresql 3.2.6
dev/run.sh .redmine/5.1-stable-postgresql
```

## Compatibility

- **Redmine 5.1, 6.1 and 7.0.** All three are in CI, on every push, against all
  three databases. 5.1 is the declared minimum as of 0.1.0; it used to be 5.0,
  which nothing ever tested.
- **PostgreSQL, MySQL and MariaDB.** Nine combinations, all of them green before
  a change lands.
- Ruby 3.2 for Redmine 5.1, Ruby 3.3 for 6.1 and 7.0 — the versions CI uses.
