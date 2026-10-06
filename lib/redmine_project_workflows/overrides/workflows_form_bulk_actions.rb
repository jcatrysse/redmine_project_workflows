# frozen_string_literal: true

module RedmineProjectWorkflows
  module Overrides
    # WP5 / claude F06. Row and column actions for a transition grid, in the two
    # header cells core already puts its own check-all toggle in.
    #
    # Two anchors, both unique in workflows/_form.html.erb and both present in
    # Redmine 5.1, 6.1 and 7.0: the column header is the only <td> in the file
    # with a style attribute, and the row header the only one with class="name".
    # Deface renames an attribute whose value contains ERB, so the column
    # header's style="width:<%= ... %>" is matched as data-erb-style -- the same
    # kind of convention the plugin's other overrides rely on in erb[loud].
    # The toggle expression itself is not the anchor, because 5.1 writes it as a
    # bare link_to_function and 6.0 and later as toggle_checkboxes_link -- and
    # anchoring on the cell puts the actions after the status name, where they
    # read as belonging to it.
    #
    # This partial is core's, rendered unchanged by the project matrices as well,
    # so one pair of overrides serves both the administration screens and the
    # project ones. INV-9: spec/integration/deface_overrides_spec.rb asserts each
    # of them against the rendered page, with an assertion only that one can
    # satisfy -- the column action's selector names .new-status-N and the row
    # action's .old-status-N, so neither could stop matching unnoticed.
    module WorkflowsFormBulkActions
      Deface::Override.new(
        virtual_path: 'workflows/_form',
        name: 'redmine_project_workflows_form_column_bulk_actions',
        insert_bottom: 'td[data-erb-style]',
        text: <<~ERB
          <%= project_workflow_bulk_actions('new', name, new_status.id, new_status.name) %>
        ERB
      )

      Deface::Override.new(
        virtual_path: 'workflows/_form',
        name: 'redmine_project_workflows_form_row_bulk_actions',
        insert_bottom: 'td.name',
        text: <<~ERB
          <%# The first row of the grid is "new issue", which has no status of its
              own: core writes its old_status_id as 0 and names it in words. The
              name has to be built here rather than read from core's own local,
              which is assigned further down the cell. %>
          <%= project_workflow_bulk_actions('old', name, old_status.try(:id) || 0,
                                            old_status ? old_status.name : l(:label_issue_new)) %>
        ERB
      )
    end
  end
end
