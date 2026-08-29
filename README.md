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
  can override one role and follow the generic workflow for another.
- **An issue can end up on a status its project cannot leave.** Move an issue
  into a project whose workflow does not use its current status, or change a
  workflow under issues that are already open, and those issues sit on a status
  with no transition out of it for that role. Redmine behaves the same way when
  an administrator edits the generic workflow; per-project workflows just make
  it reachable more often. The comparison screen (below) is the fastest way to
  see it coming.
- **The plugin answers `Issue#new_statuses_allowed_to` itself**, for the projects
  that follow the generic workflow too, rather than falling back to Redmine's own query — Redmine's
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
  rather than clearing it — and the screen says so instead of reporting a save,
  which is the other half of that promise. In practice this only shows up for a
  hand-built request; the matrices themselves cannot produce a rejected value.
- **A save that changes nothing says so.** Redmine reports *Successful update*
  for a matrix save where every control was left at *(No change)*; this plugin
  tells you nothing was saved, because the same message has to cover the case
  where the values you sent were not accepted.
- **Copying a project copies its workflow**, and the copy form says so. Since
  0.1.6 *Copy project* offers **Project workflows (N)** among *Members*,
  *Issues* and the rest, ticked like all of them, and a ticked box brings the
  project's own workflow across — the decisions and the rules, an own *empty*
  workflow included, for the trackers the copy actually has — which is also what
  the number beside the box counts. Untick it and the
  copy starts from the generic workflow. Before 0.1.6 there was no box and no
  copying: the copy quietly ran the generic workflow, which in the ordinary case
  (a project given its own workflow to be *stricter*) made it more permissive
  than the original with nothing said. A copy into a project that already runs a
  workflow of its own leaves that project's decisions alone.
- **Deleting an issue status can leave a project's own workflow empty, and the
  plugin says so.** Redmine deletes every workflow rule that names a status you
  delete — the generic ones and every project's. A project whose rules for a
  tracker and a role *all* named that status keeps its decision to run its own
  workflow and is left holding no rules at all, which for transitions permits
  nothing. Since 0.1.6 the deletion reports how many project workflows that
  happened to, with a link to them. It is a warning and not a repair: "runs an
  empty own workflow" and "follows the generic workflow" are different states,
  and choosing between them is yours rather than the plugin's.
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
- A **workflow diagram** — the picture with the arrows — for any tracker and any
  role in the project, with the statuses that cannot be reached and the ones
  nothing leads out of named rather than merely drawn.
- Optimised SQL performance for bulk workflow transition/permission updates.

## Installation

1. Copy this plugin directory into `plugins` of your Redmine installation.
2. Run dependencies and plugin migrations:
   ```
   bundle install
   RAILS_ENV=production bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows
   ```
3. Restart Redmine.

The plugin's only runtime dependency is `deface`, declared as `~> 1.9` — the
release every supported combination is tested against, up to but not including
the next major version. Your Redmine owns `Gemfile.lock`, so `bundle install` is
what applies it; on a host that already resolved `deface` inside that range,
nothing changes.

`RAILS_ENV` is not optional. Redmine's plugin migration task loads the
environment it is given and defaults to **development**, so leaving it off
migrates the wrong database and tells you it worked.

### What the migrations do, and what that costs

The migrations change Redmine's own `workflows` table: they add a nullable
`project_id` column, four indexes and a foreign key to `projects`, drop two
indexes the new ones replace, and create two tables of the plugin's own —
`project_workflow_scopes`, which records which projects run their own workflow,
and `project_workflow_write_locks`, which holds nothing but a place for two
simultaneous saves to queue. `VERSION=0` removes all of it and returns the
installation to stock behaviour; that reversal is tested on every supported
Redmine and database on every push.

The size to expect is smaller than "a core table" suggests: `workflows` holds one
row per configured rule, so it grows with trackers, roles and statuses and **not**
with issues, journals or time. A large installation has tens of thousands of rows
there, not millions. On a synthetic table of 900,000 rows — ten to fifty times
larger than realistic — the whole of this plugin's DDL measured about **7.4
seconds** on PostgreSQL 16, most of it index creation.

Two things worth knowing before you run it on a large MySQL or MariaDB
installation. Adding the foreign key is the one operation in all five migrations
that rebuilds the table: MySQL supports the in-place algorithm for adding a
foreign key only when `foreign_key_checks` is off, and Rails does not turn it off.
And one migration deletes workflow rows naming a project that no longer exists —
it prints the number it deleted, and on an installation upgrading into this plugin
that number is always 0, because project-specific rows cannot exist before the
column that holds them.

Take a backup, as with any migration that touches a core table.

## Usage

1. Go to **Administration → Project workflows**.

   This is the plugin's own screen, and it is where everything about projects
   lives. Redmine's own **Administration → Workflow** goes on doing exactly what
   Redmine does, for the workflow every project shares — it has no project
   controls on it at all, and it carries a link across to this one. (Earlier
   alpha releases added the project controls to Redmine's screens instead. If you
   have a bookmark to one of those with a project in its address, the project part
   is now ignored: open **Administration → Project workflows** instead.)
2. Select Role, Tracker, and Project.
   - **Generic** means the workflow every project uses unless it overrides it.
   - Selecting a real project shows that project's own workflow.
3. A project has its own workflow only once you give it one. The panel above the
   matrix says which of three states the selection is in and offers the three
   actions that move between them:
   - **Follows the generic workflow** — nothing is stored for this project.
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
list. **Archived projects are not on it** — nobody but an administrator can reach
an archived project and no issue in it can be edited, so a workflow written for
one governs nothing — and *(All)* means every project that is not archived. If an
archived project already has a workflow of its own, the *Project workflow
inventory* still reports it and its link still opens the matrix, so you can see it
and give it back.

What the selection means when you save:

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
- **Every cell you do change is written to all of them** — all of them that have
  a workflow of their own, that is; see the next-but-one point. One click on a
  checkbox with three trackers, two roles and ten projects selected writes sixty
  workflows. Whenever one cell stands for more than one workflow, a sentence above
  the matrix gives that number for the selection you have; a row or column
  action asks for confirmation once it would pass the threshold in the plugin's
  settings, and so does **Save** itself — see [Settings](#settings).
- **The three state actions act only where they mean something.** *Give own
  workflow* touches only the combinations that currently follow the generic one,
  so pressing it twice does not discard what the first press produced. *Empty
  this workflow* touches only combinations that already have their own. *Return
  to the generic workflow* deletes both the rules and the record of the
  decision.
- **Saving does not give a project a workflow of its own.** Those three actions
  are the only thing that does. A combination that still follows the generic
  workflow shows as an empty matrix — the grid shows the rules the selection
  holds *itself*, and a combination that has taken nothing over holds none — and
  Save leaves it exactly as it was rather than writing that emptiness back. The
  panel above the matrix says how many combinations of your selection are in
  that state, and a message after the save says how many it left alone.
- **Generic is not a project.** Selecting it alongside real projects edits the
  generic workflow as one more member of the selection; it cannot be given its
  own workflow, emptied as a scope, or handed back, because it *is* the workflow
  the other entries fall back to.

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
- **The builtin roles are not offered on the tab.** *Non member* and *Anonymous*
  have no members in any project, so the tab does not offer to give the project
  its own workflow for them; a system administrator can still do it from
  **Administration → Project workflows**. If one has, the tab **does** list the row, and
  the project can empty that workflow or give it back — otherwise a workflow the
  project runs would be in force with nothing on the project's own screens able
  to explain or undo it. The same holds for an ordinary role whose last member
  has left.

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
combination the project has not taken over says there is nothing to compare —
its workflow *is* the generic one — and one whose rules happen to match the
generic ones says so in a sentence rather than showing an empty table.

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
  uses: *Own workflow*, *Own empty workflow*, or *Follows the generic workflow*.
  One line per role you hold, because a role can be overridden while the next one
  follows the generic workflow, and what you see on the form is the union of
  both. Where you may
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

### The workflow as a diagram

The **Workflow diagram** link — on the project's Workflow tab, at the top of both
matrices, and in the panel on the issue form — draws the whole of a project's
status transitions for one tracker: a box per status, an arrow per permitted
change, and the *New issue* starting point on the left.

This is the picture people coming from Jira look for first, and it says one thing
Jira's cannot. In Jira a diagram is drawn per issue type, and who may make a move
is hidden in a dialogue behind the arrow — so the picture shows the transitions
*somebody* may make, not the ones *you* may make. Redmine decides its workflow per
tracker **and per role**, so the diagram has a **Roles shown** selector, and it
starts on the roles you hold in that project. Picking *Developer* answers "what
may a developer actually do here", which is the question somebody configuring a
workflow is really asking.

Under the drawing, in words:

- **Cannot be reached from a new issue** — a status no sequence of permitted
  moves leads to. These are drawn below a dotted line rather than in the flow.
- **Nothing leads out of these** — a status an issue can enter and never leave.
  Sometimes that is a deliberate terminal *Closed*; sometimes it is a rule
  somebody forgot to add, and there is no other screen in Redmine that will tell
  you.
- **Not used by the selected roles** — a status the tracker's workflow uses under
  some *other* role, which is why it is not in the picture.

A solid arrow is a change anyone holding the role may make; a dashed one is a
change only the author or the assignee may make; a dotted one is Redmine's own
fallback rather than a rule. Underneath is **the same workflow as a table** —
that is not an afterthought: it is what a screen reader reads, what Ctrl-F finds,
and what prints legibly.

**About that dotted arrow.** A stock Redmine ships a workflow with no rule at all
in the *New issue* row, and Redmine does not refuse to create issues because of
it: when no rule says which status a new issue starts in, it starts on the
tracker's default status. The diagram draws that as a dotted arrow, so the
statuses it leads to are correctly reported as reachable. It is not a rule
somebody wrote, and writing one for the *New issue* row makes it disappear.

**When there is no picture worth drawing.** Redmine's own default workflow lets
every status become every other one. A diagram of that is a line between every
pair of boxes, which answers nothing, so the screen says the workflow permits
nearly every move and folds the picture away behind *Show the diagram anyway*
rather than putting spaghetti in front of you. The table and the three lists
above stay where they are.

The diagram is behind the **View project workflow** permission, because it shows
what *other* roles may do, which is project configuration rather than information
about your own issue. The panel on the issue form needs no permission and keeps
none.

Two things it deliberately does not do. It does not let you *edit* the workflow by
dragging arrows — that is Jira's workflow editor, a far larger thing, and
Redmine's tick-box matrix is honestly better at the job. And it draws status
transitions only: field permissions are a property of a status rather than of a
move between two, so they are not a graph, and the comparison screen is where they
are read side by side.

A project with its **own empty workflow** draws as the starting point and nothing
else, with the sentence saying that is deliberate — the same case the issue panel
exists to explain, from the other end.

## Settings

**Administration → Plugins → Project Workflows → Configure** has five settings:
three about writing a workflow and two about drawing one.

The first three are counted in **workflow rules** — one cell of a matrix, once
for each workflow the selection covers — and they read as one scale:

- **Ask before a row or column action changes more than** — 50 by default. One
  click on a row or column action can change a great many cells and you cannot
  see what it did without looking, so this one is deliberately small. `0` asks
  every time.

- **Ask before Save rewrites more than** — 5,000 by default, which is roughly 46
  workflows of a six-status matrix. Saving is a form you have just filled in, on
  a page that already tells you how many workflows one cell stands for, so it
  asks much later than a row or column action does. Saving a **single** workflow
  never asks — that is what Redmine has always done.

- **Refuse a matrix save that would rewrite more than** — 200,000 by default. An
  administration save larger than that is refused before anything is written, and
  the message says how many rules it would have been. This is the guard against
  selecting every project, every tracker and every role at once. `0` means no
  limit.

  Since 0.1.6 the same number also bounds **Give own workflow**: giving a large
  selection of projects a copy of the generic workflow writes one rule per rule
  in that workflow per project, tracker and role, so it is the same kind of write
  and it is now refused in the same way, with a message that says how many rules
  it would have copied. *Give own **empty** workflow* copies nothing, so it is
  never refused whatever the selection — it is the bulk action that stays
  available at any size.

The last two are about the **workflow diagram**:

- **Offer the workflow diagram** — on. The diagram is a read-only screen reached
  from a project's workflow settings, from its matrices and from the issue form.
  Turn it off and no link to it is offered anywhere and the screen itself answers
  *404 not found*; every other screen is untouched. It exists so that an
  installation that does not want the diagram, or that meets something odd on a
  Redmine nobody has tried yet, can switch off one screen rather than carry a
  feature it has to think about on every upgrade.

- **Do not draw a workflow with more than** — 2,000 arrows. Deciding where to put
  the arrows is what the drawing costs, and it follows the arrows rather than the
  statuses: measured on Redmine 7.0 and PostgreSQL 16, a workflow of 400 statuses
  and 800 arrows is laid out in about 50 ms, while one of 60 statuses in which
  nearly every move is permitted (3,600 arrows) takes about 1.5 s. Above the
  limit the page says so and lists the workflow as a table instead — the table is
  the diagram's readable twin and holds exactly the same rules. `0` means no
  limit. For scale: Redmine's own default workflow is five statuses and
  twenty-five arrows.

### How fast is a bulk save?

Fast, because the plugin does **not** write one statement per rule the way
Redmine's own workflow save does. Measured on Redmine 7.0 and PostgreSQL 16, on
modest development hardware:

| what you did | what it cost |
|---|---|
| Save a matrix over 5 projects × 3 trackers × 3 roles (1,620 rules) | 30 statements, 0.22 s |
| The same 1,620 rules, one `save` per rule as Redmine does it | 6,480 statements, 5.03 s |
| Save a matrix over 50 projects (16,200 rules) | 400 statements, 2.4 s |
| *Empty this workflow* / *Return to the generic workflow* over 1,000 combinations | 5 and 6 statements, well under a second |

The statement count of a save is about **eight per project and does not grow with
the size of the matrix**; the throughput is roughly 27,000 workflow rules a
second. The 200,000-rule ceiling above is therefore about seven seconds of
writing, which is where a front-end proxy starts timing out.

**Give own workflow** was the one action still written a row at a time, and since
0.1.6 it is not. Measured the same way, giving 500 projects × 5 trackers × 8
roles (20,000 combinations) a copy of a 30-rule generic workflow — 600,000 rules:

| | before | after |
|---|---|---|
| PostgreSQL 16 | 110 s (and 294 s in a second sample), 60,042 statements | **18 s, 151 statements** |
| MariaDB 10.11 | 99 s, 60,048 statements | **14 s, 157 statements** |
| *Give own empty workflow*, same size | 60 s / 47 s | **3.9 s / 3.4 s** |

What changed, and why it needed changing carefully: the row-at-a-time write was
deliberate. It was how the plugin knew which scopes *this* request created, so
that two administrators pressing the button at the same moment could not both be
told they had created the same one — and so that the second one could not clear
and rewrite the rules the first had just copied. The batched write keeps that
guarantee a different way: the action now takes a small lock on the workflow it
is copying (one row per tracker and role, never one per project) before it looks,
so the second administrator waits, then sees what the first did. As a bonus that
closes a hole nobody had noticed: the rules being copied were read under no lock
at all, so editing the generic workflow while a large copy was running gave the
projects copied early the old rules and the ones copied late the new ones.

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
column on `workflows`; both of the plugin's own tables go too, earlier in the
run, because the migrations reverse in the order they were applied. The delete is
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
(see [`docs/design.md`](docs/design.md)). Duplicate rows make a matrix cell
render as a mixed dropdown instead of a checkbox.

The plugin no longer produces them: every workflow write — a project's, the one
every project shares, and a copy into either — now takes a lock before it
rewrites anything, so two administrators saving the same matrix at the same
moment queue rather than collide. Redmine's own workflow screens have the same
race and no such lock, and a database can carry duplicates from before this
version, from Redmine's own screens, or from another plugin. To clean them up:

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

Every fact in this section lives in
[`lib/redmine_project_workflows/compatibility.yml`](lib/redmine_project_workflows/compatibility.yml),
and a spec fails if the two disagree.

- **Redmine 5.1, 6.1 and 7.0.** All three are in CI, on every push, against all
  three databases. 5.1 is the declared minimum as of 0.1.0; it used to be 5.0,
  which nothing ever tested.
- **PostgreSQL, MySQL and MariaDB.** Nine combinations, all of them green before
  a change lands.
- Ruby 3.2 for Redmine 5.1, Ruby 3.3 for 6.1 and 7.0 — the versions CI uses.

### On a Redmine that is not one of those three

The plugin installs and runs — it declares a minimum version and no maximum,
because a version range would turn an upgrade into a Redmine that refuses to
boot until an administrator deletes the plugin directory. What it does instead
is **measure**. The plugin reimplements more than twenty of Redmine's own
methods (there is no `super` to call: core's workflow queries carry no project
column), so it records a fingerprint of each of them for every Redmine it has
been tested on, and on an unknown one it compares. It does the same for the five
places it adds something to one of Redmine's own screens: it checks, on the
Redmine you are running, that each of them still finds the place it attaches
to — because when one does not, Redmine says nothing at all and the screen
simply comes out missing a control.

That gives three answers, in the log at startup and on
**Administration → Project workflow diagnostics**:

- **Verified** — this Redmine is one the plugin is tested against. Nothing is
  measured and nothing is said.
- **Not verified, no differences found** — nobody has tested this Redmine, but
  every method the plugin copied is identical to the newest one that was tested.
- **Not verified, differences found** — one or more of those methods has
  changed. The page names them and says where Redmine defines them, so the
  difference can be read.

The third is a warning, not a refusal: the plugin keeps working, and the screens
an administrator would use to put it right keep working with it. What the check
proves is precise and worth stating plainly — that the *bodies* the plugin
copied are unchanged. It does not prove that Redmine still calls them the same
way. It is evidence, not a guarantee.

### Administration → Project workflow diagnostics

The same page answers three more questions, and all four are questions whose
wrong answer is otherwise **silent**:

- **Permissions.** Two plugins can register the same permission name. Redmine
  answers with whichever was registered first, and the loser's screens then
  refuse everybody, administrators included, with nothing in any log. The page
  says whether the names this plugin registered are the ones Redmine answers
  with. (This is not hypothetical: it happened to this plugin on a real
  installation, which is why both permissions are called
  `*_project_workflow_rules`.)
- **Patches.** Which of Redmine's own classes this plugin changes, and whether
  each change is in place. A patch that is not applied leaves Redmine behaving
  as it does without the plugin, which looks like the plugin doing nothing
  rather than like an error.
- **Screens.** Which of Redmine's own screens the plugin adds to. A screen that
  looks wrong is worth reporting even when everything is listed here: the list
  says what was registered, not what was placed.
