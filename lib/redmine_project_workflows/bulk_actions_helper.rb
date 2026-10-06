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
  # Included into ProjectWorkflowMatrixHelper, which the plugin's own controllers
  # name in their class bodies and which
  # RedmineProjectWorkflows::Patches::WorkflowsControllerHelperPatch puts into
  # core's WorkflowsController helper chain -- so it is available on the
  # administration matrices and on the project ones, both of which render core's
  # own workflows/_form partial. It used to be mixed into WorkflowsHelper itself;
  # ADR-003 removed that prepend, which is the plugin's own forbidden construct
  # (audit F01).
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
      # #size rather than Array(...).size: on the administration screens with
      # "all" selected this is a relation, already loaded by the project
      # selector above the matrix, and #size then reads its length while
      # Array() would copy it -- once per cell of the matrix.
      scopes = @projects_for_update ? @projects_for_update.size : 0
      scopes += 1 if @global_selected || scopes.zero?
      scopes
    end

    # A row or column action that would change more workflow rules than this asks
    # first. Falls back to the constant for a value an administrator has cleared
    # or typed something else into, and for the key an older saved settings hash
    # does not carry at all.
    def project_workflow_bulk_confirm_threshold
      RedmineProjectWorkflows::Services::WriteBudget.setting(
        'bulk_confirm_threshold', DEFAULT_BULK_CONFIRM_THRESHOLD
      )
    end

    # The data attributes the Save button's own confirmation reads (WP13, audit
    # F08). A save rewrites every cell it submits, once per workflow the
    # selection covers, so the number it asks about is counted in the same unit a
    # row or column action asks about -- workflow rules.
    #
    # **Its own threshold, and a much larger one.** It shared
    # `bulk_confirm_threshold` until the write path was measured on 2026-08-29,
    # and at 50 rules the dialog fired on essentially every multi-workflow save:
    # two workflows of a six-status matrix is already 216 rules. A row or column
    # action is one click whose effect you cannot see; a Save is a form the
    # operator has just filled in, on a page that already says how many workflows
    # one cell stands for. See Services::WriteBudget.
    #
    # `project_workflow_selection_size` rather than a cell count: how many cells
    # there are is decided by the status list and is the same on every save of
    # this screen. The script multiplies by the cells it finds and asks only when
    # the multiplier is more than one.
    def project_workflow_save_confirm_data
      {
        project_workflow_multiplier: project_workflow_selection_size,
        project_workflow_threshold: project_workflow_save_confirm_threshold,
        project_workflow_save_confirm: l(:text_project_workflow_save_confirm)
      }
    end

    # See Services::WriteBudget: the Save button's threshold, not the row and
    # column actions'.
    def project_workflow_save_confirm_threshold
      RedmineProjectWorkflows::Services::WriteBudget.save_confirm_threshold
    end

    # One <script> per page, from whichever of the plugin's administration
    # matrices is rendering.
    #
    # Public since WP13, and it had to become so. It used to be rendered only
    # from a row or column header, which the *field permissions* matrix does not
    # have -- so on that screen the script was never on the page, and the Save
    # button's confirmation would have called a function that is not there.
    # Both administration views now render it above their form; the header call
    # below finds it already done.
    #
    # Still one <script>: the transitions page renders core's grid three times
    # and the function is the same for all three, so the alternative would be a
    # fourth Deface anchor for something no page can be without (INV-9 asks for
    # a spec per anchor, and an anchor that carries nothing but a script is one
    # more thing to go stale).
    def project_workflow_bulk_script
      return ''.html_safe if @project_workflow_bulk_script_rendered

      @project_workflow_bulk_script_rendered = true
      render partial: 'redmine_project_workflows/bulk_script'
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
  end
end
