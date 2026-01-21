# frozen_string_literal: true
module RedmineProjectWorkflows
  module Overrides
    module WorkflowsPermissionsAddProjectSelector
      Deface::Override.new(
        virtual_path: 'workflows/permissions',
        name: 'redmine_project_workflows_permissions_add_project_selector',
        insert_before: 'erb[loud]:contains("submit_tag l(:button_edit)")',
        partial: 'redmine_project_workflows/project_selector'
      )
    end
  end
end
