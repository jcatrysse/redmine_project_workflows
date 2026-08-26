# Redmine plugin: Project Workflows

*WARNING: alpha stage, do not use in production!*

This plugin adds project-specific workflows to Redmine by extending the core workflows table with a nullable `project_id`.
Generic rules (`project_id = NULL`) behave exactly like Redmine core, while project rules override generic rules for selected roles and trackers.

The specs pass on Redmine 5.1, 6.1 and 7.0, against PostgreSQL 16, MySQL and MariaDB.
Redmine 5.1 with PostgreSQL is the combination in day-to-day use; the others are
covered by CI only.

## Features

- Project-specific status transitions and field permissions.
- A **Workflow** tab in project settings, so a project can run its own workflow
  without a system administrator — behind two permissions.
- A **Workflow inventory** answering which projects have taken a workflow over.
- Row and column actions on every transition matrix, which reach the mixed cells
  Redmine's own check-all toggle skips.
- Optimised SQL performance for bulk workflow transition/permission updates.

## Installation

1. Copy this plugin directory into `plugins` of your Redmine installation.
2. Run dependencies and plugin migrations:
   ```
   bundle install
   bundle exec rake redmine:plugins:migrate NAME=redmine_project_workflows
   ```
3. Restart Redmine.

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

## Settings

**Administration → Plugins → Project Workflows → Configure** has one setting:

- **Ask before a row or column action changes more than** — a number of workflow
  rules, 50 by default. A row or column action that would change more than that
  asks for confirmation first; `0` asks every time.

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

- Redmine 5.1, 6.1 and 7.0 (5.0 declared as the minimum, but untested)
- PostgreSQL, MySQL and MariaDB
