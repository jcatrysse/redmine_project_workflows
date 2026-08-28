# frozen_string_literal: true

module RedmineProjectWorkflows
  # Saving a workflow matrix from an administration screen: the write itself, the
  # message afterwards, and the parameter shaping in front of it.
  #
  # Extracted from ProjectWorkflowRulesController because Metrics/ClassLength
  # crossed at 249/200, and that limit is already relaxed in .rubocop.yml with a
  # stated rationale -- so crossing it is a signal to extract, not a cop to
  # placate. What came out is a coherent unit: everything between "the operator
  # pressed Save" and "the redirect".
  #
  # Deliberately not shared with RedmineProjectWorkflows::MatrixParams and
  # ::MatrixReporting, which are the *project* screens' versions. A project
  # matrix is one project, one tracker and one role, so it has no "no change"
  # state to strip and no mixture to report; sharing the two would mean one
  # module with a flag in it (finding F14).
  #
  # Every method here is private, because the module is mixed into a controller
  # and a public instance method there is an action.
  module AdminMatrix
    private

    # One transaction over the whole selection: a failure half way through
    # otherwise leaves some of the selected workflows rewritten and the rest
    # untouched. The two writers take the same four arguments, so one method
    # serves both matrices.
    def write_matrix(writer, method, matrix)
      result = RedmineProjectWorkflows::Services::MatrixSaveResult.none
      ActiveRecord::Base.transaction do
        result = selected_project_ids.sum(result) do |project_id|
          writer.public_send(method, project_id, @trackers, @roles, matrix)
        end
      end
      report_matrix_save(result)
    end

    def matrix_redirect_params
      { project_id: selected_project_param_values, tracker_id: @trackers, role_id: @roles,
        used_statuses_only: params[:used_statuses_only] }
    end

    # What a matrix save did, and what it deliberately did not do.
    #
    # A combination that still inherits the generic workflow is left alone (INV-3:
    # taking a workflow over is one of the three scope actions, not a side effect
    # of pressing Save), and saying so is not optional -- the grid shows what the
    # selection *stores*, so an inheriting combination renders empty, and a silent
    # no-op there is indistinguishable from a save that cleared it.
    #
    # The counts come from the writers rather than being inferred here: a payload
    # the writer's whitelist had emptied refuses nothing, so computing "written" as
    # (projects x trackers x roles) - skipped reported the whole selection saved
    # over a table nothing had touched (finding F06).
    def report_matrix_save(result)
      flash[:notice] = l(:notice_successful_update) if result.written?
      warnings = []
      if result.skipped?
        warnings << l(:notice_project_workflow_save_skipped_inheriting, count: result.skipped)
      elsif result.nothing_applied?
        warnings << l(:notice_project_workflow_save_nothing_applied)
      end
      # The mixed case: some entries written, some dropped by the whitelist. It had
      # no message at all -- `written` was positive, so the screen reported a plain
      # success and said nothing about the refused part (finding F06).
      rejected = result.rejected
      warnings << l(:notice_project_workflow_save_rejected_values, count: rejected) if rejected.positive?
      flash[:warning] = warnings.join(' ') if warnings.any?
      log_matrix_save(result)
    end

    # Ids and counts, never the matrix (finding F19). This is the write that can
    # touch every project on the installation in one transaction, so it is the one
    # whose absence from the log cost the most.
    def log_matrix_save(result)
      RedmineProjectWorkflows::Services::WriteLog.record(
        'admin_matrix_save',
        rule_type: @rule_type_for_log, actor: User.current.id,
        projects: selected_project_ids, trackers: @trackers&.map(&:id), roles: @roles&.map(&:id),
        written: result.written, skipped: result.skipped, rejected: result.rejected
      )
    end

    # The state of the three INV-3 actions for the current selection, used by the
    # panel above the matrix. Built here rather than in the view so that the view
    # does no querying and the state can be asserted in a controller spec.
    #
    # Only real projects have scopes: the generic workflow is the one thing that
    # cannot be inherited or emptied, so 'global' contributes nothing.
    def scope_state_for(rule_type)
      RedmineProjectWorkflows::Services::ScopeState.new(
        project_ids: selected_projects.map(&:id), tracker_ids: @trackers.map(&:id),
        role_ids: @roles.map(&:id), rule_type: rule_type
      )
    end

    # Strips core's "no change" option out of a submitted matrix, at whatever depth
    # the leaves are: transitions nest status/status/rule and permissions
    # status/field.
    #
    # Guarded, unlike core's own two loops: `transitions[1]=x` reaches those as a
    # String and raises NoMethodError on `each_value`, which is a 500 rather than a
    # rejection.
    def strip_no_change(params)
      hash = to_plain_hash(params)
      hash.each_value { |value| strip_no_change_in(value) }
      hash
    end

    def strip_no_change_in(value)
      return unless value.is_a?(Hash)

      value.reject! { |_key, inner| inner == 'no_change' }
      value.each_value { |inner| strip_no_change_in(inner) }
    end

    # What it is, not what it answers to: `respond_to?(:to_h)` is true of an Array,
    # whose `to_h` raises TypeError -- so `?transitions[]=x` was a 500 from inside
    # the guard that exists to prevent one (finding F02).
    #
    # The deep_dup stays: strip_no_change mutates what it is given with reject!,
    # and these parameters belong to the request.
    def to_plain_hash(value)
      return value.deep_dup.to_unsafe_h if value.respond_to?(:to_unsafe_h)

      value.is_a?(Hash) ? value.deep_dup : {}
    end
  end
end
