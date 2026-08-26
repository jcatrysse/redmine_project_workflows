# frozen_string_literal: true

module RedmineProjectWorkflows
  # Row and column actions for the transition matrices, and the sentence above
  # the matrix that says how much one cell stands for (WP5).
  #
  # Core already puts a check-all/uncheck-all toggle in every row and column
  # header, but it selects on `input[type=checkbox]`, so it silently skips the
  # cells a multi-selection renders as a <select> -- exactly the cells with the
  # manual work in them (finding claude F06). Adding classes to that select is
  # not enough on its own: no selector of the shape core uses can ever match a
  # <select>. So the plugin adds three explicit actions instead, which reach
  # both kinds of cell, and leaves core's toggle exactly as it was.
  #
  # Three actions, because toggling is not the same as setting: "Yes" and "No"
  # say what the row or column becomes, and "no change" puts every cell in it
  # back to the value the page was opened with -- which is what a mixed cell
  # means and the only way back to it once something has been clicked.
  #
  # Included into WorkflowsHelper through
  # RedmineProjectWorkflows::Patches::WorkflowsHelperPatch, so it is available on
  # the administration matrices and on the project ones, which render core's own
  # workflows/_form partial.
  module BulkActionsHelper
    # Above this many workflow rules a single row or column action asks first.
    # The plugin setting overrides it; init.rb registers the same number as the
    # setting's default and spec/plugin_conventions_spec.rb asserts the two agree.
    DEFAULT_BULK_CONFIRM_THRESHOLD = 50

    # The three actions for one row or one column of one transition grid.
    #
    # +dimension+ is 'old' for a row and 'new' for a column, which are the two
    # halves of the classes core already puts on every checkbox cell -- and that
    # the plugin now puts on a mixed cell's select as well, so that one selector
    # reaches both.
    def project_workflow_bulk_actions(dimension, name, status_id, status_name)
      selector = "table.transitions-#{name} .#{dimension}-status-#{status_id}:not(:disabled)"
      links = project_workflow_bulk_values.map do |value, label|
        title = l(project_workflow_bulk_title_key(dimension), name: status_name, value: label)
        link_to_function(label, 'projectWorkflowBulkApply(this)',
                         :title => title, 'aria-label' => title, :class => 'project-workflow-bulk-action',
                         :data => { project_workflow_value: value })
      end

      project_workflow_bulk_script +
        content_tag(:span, safe_join(links, ' '),
                    class: 'project-workflow-bulk',
                    data: {
                      project_workflow_target: selector,
                      project_workflow_multiplier: project_workflow_selection_size,
                      project_workflow_threshold: project_workflow_bulk_confirm_threshold,
                      project_workflow_confirm: l(:text_project_workflow_bulk_confirm)
                    })
    end

    # How many workflows one cell of the matrix stands for: every (tracker, role,
    # scope) combination the selection covers. One on a project's own matrix,
    # which is one combination by construction; more on the administration
    # screens, which edit a selection at once.
    def project_workflow_selection_size
      Array(@roles).size * Array(@trackers).size * project_workflow_selection_scopes
    end

    # The scopes in the selection: the projects it named, plus the generic
    # workflow when that is selected too. Never zero -- a selection that named no
    # project at all is the generic workflow alone, which is what core shows.
    def project_workflow_selection_scopes
      scopes = Array(@projects_for_update).size
      scopes += 1 if @global_selected || scopes.zero?
      scopes
    end

    # A row or column action that would change more workflow rules than this asks
    # first. Falls back to the constant for a value an administrator has cleared
    # or typed something else into, and for the key an older saved settings hash
    # does not carry at all.
    def project_workflow_bulk_confirm_threshold
      value = Setting.plugin_redmine_project_workflows['bulk_confirm_threshold'].to_s
      value.match?(/\A\d+\z/) ? value.to_i : DEFAULT_BULK_CONFIRM_THRESHOLD
    end

    private

    # "No change" is only offered where a cell can actually hold it: with one
    # workflow per cell there is nothing to disagree, and the option would name a
    # state the matrix cannot be in.
    def project_workflow_bulk_values
      values = [['1', l(:general_text_Yes)], ['0', l(:general_text_No)]]
      values << ['no_change', l(:label_no_change_option)] if project_workflow_selection_size > 1
      values
    end

    def project_workflow_bulk_title_key(dimension)
      dimension == 'old' ? :label_project_workflow_bulk_row : :label_project_workflow_bulk_column
    end

    # One <script> per page, from whichever row or column header is rendered
    # first. The transitions page renders core's grid three times and the
    # function is the same for all three, so the alternative would be a fourth
    # Deface anchor for something no page can be without (INV-9 asks for a spec
    # per anchor, and an anchor that carries nothing but a script is one more
    # thing to go stale).
    def project_workflow_bulk_script
      return ''.html_safe if @project_workflow_bulk_script_rendered

      @project_workflow_bulk_script_rendered = true
      render partial: 'redmine_project_workflows/bulk_script'
    end
  end
end
