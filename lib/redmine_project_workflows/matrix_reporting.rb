# frozen_string_literal: true

module RedmineProjectWorkflows
  # What a write on the project's own Workflow screens says to the operator, and
  # what it records in the log.
  #
  # Included into ProjectWorkflowsController, which is why every method here is
  # **private**: every public instance method of a controller is an action, so a
  # public method here would be routable and unauthorized (CLAUDE.md's
  # forbidden-constructs table).
  module MatrixReporting
    private

    # The warning and the notice are set independently, because a save can both
    # succeed and have refused part of what it was sent (finding F06): a positive
    # `written` used to mean `notice_successful_update` and silence about the
    # dropped part, while the README promises that an unacceptable value leaves its
    # rule alone *and the screen says so*.
    def report_rule_save(result)
      flash[:notice] = l(:notice_successful_update) if result.written?
      warnings = []
      unless result.written?
        warnings << if result.skipped?
                      l(:notice_project_workflow_not_own)
                    else
                      l(:notice_project_workflow_save_nothing_applied)
                    end
      end
      # Appended rather than replacing: which part was refused is additional
      # information about the save, not an alternative to reporting it. Built as a
      # list rather than by reading `flash[:warning]` back -- reading it makes
      # Rails/ActionControllerFlashBeforeRender fire, and the cop is not wrong to
      # be suspicious of a controller that reads its own flash.
      rejected = result.rejected
      warnings << l(:notice_project_workflow_save_rejected_values, count: rejected) if rejected.positive?
      flash[:warning] = warnings.join(' ') if warnings.any?
      log_rule_save(result)
    end

    # Ids and counts, never the matrix (finding F19). This screen is where a
    # non-administrator writes workflow data, so it is the one where "who removed
    # this transition" is a question somebody will actually ask.
    def log_rule_save(result)
      RedmineProjectWorkflows::Services::WriteLog.record(
        'project_matrix_save',
        rule_type: @rule_type, actor: User.current.id, project: @project.id,
        tracker: @tracker.id, role: @role.id,
        written: result.written, skipped: result.skipped, rejected: result.rejected
      )
    end

    def report(touched, notice_key)
      if touched.positive?
        flash[:notice] = l(notice_key, count: touched)
      else
        flash[:warning] = l(:notice_project_workflow_scope_unchanged)
      end
      # Which of the three INV-3 actions was taken, and on what. The notice key
      # names the action, and it is already a server-built symbol.
      RedmineProjectWorkflows::Services::WriteLog.record(
        'project_scope_action',
        action_key: notice_key, rule_type: @rule_type, actor: User.current.id,
        project: @project.id, tracker: @tracker.id, role: @role.id, touched: touched
      )
      # The scope panel on a matrix screen sends no back_url, so an action taken
      # there comes back to that matrix; the settings tab sends one, so an action
      # taken there comes back to the tab.
      redirect_back_or_default(matrix_path)
    end
  end
end
