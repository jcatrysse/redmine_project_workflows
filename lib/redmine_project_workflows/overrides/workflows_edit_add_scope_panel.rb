# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    module WorkflowsEditAddScopePanel
      # Anchored on div.autoscroll, the same element the hidden project fields
      # use -- it exists verbatim in Redmine 5.1, 6.1 and 7.0, and the panel
      # belongs directly above the matrix it describes. INV-9:
      # spec/integration/deface_overrides_spec.rb asserts it reaches the page.
      Deface::Override.new(
        virtual_path: 'workflows/edit',
        name: 'redmine_project_workflows_edit_add_scope_panel',
        insert_before: 'div.autoscroll',
        text: <<~ERB
          <%= render partial: 'redmine_project_workflows/scope_panel',
                     locals: { rule_type: ProjectWorkflowScope::TRANSITIONS } %>
        ERB
      )
    end
  end
end
