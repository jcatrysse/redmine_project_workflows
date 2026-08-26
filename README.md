# Redmine plugin: Project Workflows

*WARNING: alpha stage, do not use in production!*

This plugin adds project-specific workflows to Redmine by extending the core workflows table with a nullable `project_id`.
Generic rules (`project_id = NULL`) behave exactly like Redmine core, while project rules override generic rules for selected roles and trackers.

The specs pass on Redmine 5.1, 6.1 and 7.0, against PostgreSQL 16, MySQL and MariaDB.
Redmine 5.1 with PostgreSQL is the combination in day-to-day use; the others are
covered by CI only.

## Features

- Project-specific status transitions and field permissions.
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
