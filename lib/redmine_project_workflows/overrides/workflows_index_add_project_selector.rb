# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    module WorkflowsIndexAddProjectSelector
      # The summary page is a grid of trackers and roles for one workflow at a
      # time, and before this override that workflow was always the generic
      # one. The selector says which workflow the grid is counting; the link
      # goes to the inventory, which answers the question the grid cannot --
      # which projects have taken a workflow over.
      #
      # A surround rather than an insert, because the two halves belong on
      # either side of the title: Redmine floats .contextual to the right and
      # core always renders it before the heading, while the selector belongs
      # under it. The anchor is core's title expression, byte-identical in
      # Redmine 5.1, 6.1 and 7.0 -- and it is the title rather than the grid so
      # that the header still renders on an installation with no roles or
      # trackers, where core shows its "no data" paragraph instead of a table.
      #
      # INV-9: spec/integration/deface_overrides_spec.rb asserts it reaches the
      # page. Deface itself raises if <%= render_original %> goes missing.
      Deface::Override.new(
        virtual_path: 'workflows/index',
        name: 'redmine_project_workflows_index_add_project_selector',
        surround: 'erb[loud]:contains("title [l(:label_workflow)")',
        text: <<~ERB
          <div class="contextual">
            <%= project_workflows_icon_link('list', l(:label_project_workflow_inventory),
                                            project_workflow_inventories_path) %>
          </div>
          <%= render_original %>
          <%= render partial: 'redmine_project_workflows/summary_selector' %>
        ERB
      )
    end
  end
end
