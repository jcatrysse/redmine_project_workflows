# Redmine plugin: Project Workflows

*WARNING: alpha stage, do not use in production!*

This plugin adds project-specific workflows to Redmine by extending the core workflows table with a nullable `project_id`.
Generic rules (`project_id = NULL`) behave exactly like Redmine core, while project rules override generic rules for selected roles and trackers.

The specs pass on Redmine 5.1, 6.1 and 7.0, against PostgreSQL 16, MySQL and MariaDB.
Redmine 5.1 with PostgreSQL is the combination in day-to-day use; the others are
covered by CI only. Note that on Redmine 6.0 and later the project selector does
not render the SVG sprite that core's JavaScript expects, which raises a
TypeError during page initialisation; see `spec/characterization`.

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
   - **Generic** project means generic workflows, for all projects
   - Selecting a project activates project override mode for that project.
3. Select the Generic project to manage rules shared across all projects.

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
