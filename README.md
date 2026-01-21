# Redmine plugin: Project Workflows

*WARNING: alpha stage, do not use in production!*

This plugin adds project-specific workflows to Redmine by extending the core workflows table with a nullable `project_id`.
Generic rules (`project_id = NULL`) behave exactly like Redmine core, while project rules override generic rules for selected roles and trackers.

The plugin has been tested on Redmine 5.1. but I encourage you to test it thoroughly before using it in production. Redmine 6.0 and 6.1 should also work, but this has not been tested.

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

## Compatibility

- Redmine > 5.0
