# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    module WorkflowsPermissionsAddProjectHiddenField
      Deface::Override.new(
        virtual_path: 'workflows/permissions',
        name: 'redmine_project_workflows_permissions_add_project_hidden_field',
        insert_top: 'div.autoscroll',
        # 'all' is carried verbatim, never expanded (finding F01).
        #
        # Core puts the project selector and the matrix in two separate
        # form_tag blocks -- byte-identically on 5.1, 6.1 and 7.0 -- so these
        # hidden fields are the only thing that carries the selection into the
        # save. Expanding the keyword here made every id ride in the redirect
        # after Save and in all four scope-action links on the page that came
        # back: roughly 11 KB of query string on an installation with 500
        # projects, which nginx rejects with a 414 at its default 8 KB header
        # buffer. `load_project_options` expands it server-side already, and
        # the scope panel has kept it verbatim for the same reason since WP1.
        text: <<~ERB
          <% project_ids = Array(params[:project_id]).presence || ['global'] %>
          <% project_ids = ['all'] if project_ids.include?('all') %>
          <% project_ids.each do |project_id| %>
            <%= hidden_field_tag 'project_id[]', project_id, id: nil %>
          <% end %>
        ERB
      )
    end
  end
end
