# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    module WorkflowsPermissionsAddScopePanel
      # See WorkflowsEditAddScopePanel; the field permissions matrix carries its
      # own scope, so it carries its own panel.
      Deface::Override.new(
        virtual_path: 'workflows/permissions',
        name: 'redmine_project_workflows_permissions_add_scope_panel',
        insert_before: 'div.autoscroll',
        text: <<~ERB
          <%= render partial: 'redmine_project_workflows/scope_panel',
                     locals: { rule_type: ProjectWorkflowScope::PERMISSIONS } %>
        ERB
      )
    end
  end
end
