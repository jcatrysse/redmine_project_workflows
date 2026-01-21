# frozen_string_literal: true
module RedmineProjectWorkflows
  module Overrides
    module WorkflowsCopyAddProjectSelectors
      Deface::Override.new(
        virtual_path: 'workflows/copy',
        name: 'redmine_project_workflows_copy_add_source_project_selector',
        insert_after: "erb[loud]:contains(\"select_tag('source_role_id'\")",
        text: <<~ERB
          <p>
            <%= render partial: 'redmine_project_workflows/copy_project_selector',
                       locals: {
                         selector_id: 'project_id_source',
                         field_name: 'source_project_id',
                         selected_values: @source_project_id,
                         include_same_as_target: true
                       } %>
          </p>
        ERB
      )

      Deface::Override.new(
        virtual_path: 'workflows/copy',
        name: 'redmine_project_workflows_copy_add_target_project_selector',
        insert_after: "erb[loud]:contains(\"select_tag 'target_role_ids'\")",
        text: <<~ERB
          <p>
            <%= render partial: 'redmine_project_workflows/copy_project_selector',
                       locals: {
                         selector_id: 'project_id_target',
                         field_name: 'target_project_ids[]',
                         selected_values: params[:target_project_ids],
                         multiple: true,
                         disable_blank: true
                       } %>
          </p>
        ERB
      )
    end
  end
end
