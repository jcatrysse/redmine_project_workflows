# frozen_string_literal: true
module RedmineProjectWorkflows
  module Overrides
    module WorkflowsPermissionsAddProjectHiddenField
      Deface::Override.new(
        virtual_path: 'workflows/permissions',
        name: 'redmine_project_workflows_permissions_add_project_hidden_field',
        insert_top: 'div.autoscroll',
        text: <<~ERB
    <% project_ids = Array(params[:project_id]).presence || ['global'] %>
    <% if project_ids.include?('all') %>
      <% project_ids = @projects.map { |project| project.id.to_s } + ['global'] %>
    <% end %>
    <% project_ids.each do |project_id| %>
      <%= hidden_field_tag 'project_id[]', project_id, id: nil %>
    <% end %>
  ERB
      )
    end
  end
end
