# frozen_string_literal: true
module RedmineProjectWorkflows
  module Overrides
    module WorkflowsFormAddProjectSelector
      Deface::Override.new(
        virtual_path: 'workflows/edit',
        name: 'redmine_project_workflows_workflows_form_add_project_selector',
        insert_before: 'erb[loud]:contains("submit_tag l(:button_edit)")',
        partial: 'redmine_project_workflows/project_selector'
      )
    end
  end
end
