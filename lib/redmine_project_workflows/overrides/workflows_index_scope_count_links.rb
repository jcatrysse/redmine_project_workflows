# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    module WorkflowsIndexScopeCountLinks
      # Core's count cell links to the transitions matrix with the tracker and
      # the role but no project, so with a project selected the page would show
      # that project's counts and the link would open the generic matrix.
      #
      # The two supported shapes of the cell differ (5.1 substitutes an
      # icon-not-ok span for a zero, 6.0 and later colour the number), so the
      # anchor is the part they have in common -- the url hash -- and the
      # replacement reproduces whichever shape the host uses through
      # RedmineProjectWorkflows::VersionHelper.
      Deface::Override.new(
        virtual_path: 'workflows/index',
        name: 'redmine_project_workflows_index_scope_count_links',
        replace: %(erb[loud]:contains(":action => 'edit', :role_id => role, :tracker_id => tracker")),
        text: <<~ERB
          <%= project_workflow_summary_count_link(count, tracker, role, @project_workflow_selection) %>
        ERB
      )
    end
  end
end
