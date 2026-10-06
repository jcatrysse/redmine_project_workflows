# frozen_string_literal: true

module RedmineProjectWorkflows
  # What the copy screen does to the scope table, and what it says afterwards.
  #
  # The four methods #duplicate alone needs. Not under +Patches+ since ADR-003,
  # for the reason WorkflowSelection gives: this is the plugin's own controller
  # code and it is mixed into the plugin's own controller. The hard rule is
  # unchanged -- everything here is private, because every public instance method
  # of a controller is an action and would be routable.
  module CopyScopes
    private

    # Every scope row this copy could touch, locked before the first rule is
    # written. See ScopeWriter.lock_scopes_for_copy for what goes wrong
    # without it (finding F01); this method's own job is only to work out the
    # target combinations without consulting either table, which is what makes
    # the lock takeable this early.
    #
    # The pairs come from the same method copy_for_project uses, so the lock
    # cannot cover a different set from the write. A target of 'global' is nil
    # here and contributes nothing: the generic workflow has no scope.
    #
    # It is not unlocked, though, and since WP13 it is not this method's
    # business either. A copy into the generic workflow takes the plugin's own
    # coordination row (audit finding F07), and it takes it in
    # WorkflowRule.copy_for_project -- beside the write, where Redmine's *own*
    # copy screen reaches it too. Taking it here as well would cover one of the
    # two screens twice and the other not at all.
    def lock_scopes_for_copy(source_project_id, target_project_ids)
      combinations = target_project_ids.compact.flat_map do |target_project_id|
        copy_pairs, = WorkflowRule.copy_pairs_for_project(
          resolved_copy_source(source_project_id, target_project_id),
          target_project_id, @source_tracker, @source_role, @target_trackers, @target_roles
        )
        RedmineProjectWorkflows::Services::ScopeCombinations.for_project(target_project_id, copy_pairs)
      end
      RedmineProjectWorkflows::Services::ScopeWriter.lock_scopes_for_copy(combinations: combinations)
    end

    def record_scopes_for_copy(combinations)
      RedmineProjectWorkflows::Services::ScopeWriter.ensure_scopes_for_copy(
        combinations: combinations,
        user: User.current
      )
    end

    # Which workflow a copy reads from, per target project. 'any' means each
    # target project's own; blank or 'global' mean the generic one; anything
    # else is the project the form named.
    def resolved_copy_source(source_project_id, target_project_id)
      return target_project_id if source_project_id == 'any'
      return nil if source_project_id.blank? || source_project_id == 'global'

      source_project_id
    end

    # What the copy did, including the part nobody asked for: a combination it
    # left with an own *empty* workflow. See ScopeCombinations.own_empty_count --
    # reported rather than refused, because the copy is also how somebody
    # deliberately empties a project (finding F03).
    def report_copy(combinations)
      flash[:notice] = l(:notice_successful_update)
      emptied = RedmineProjectWorkflows::Services::ScopeCombinations.own_empty_count(combinations)
      flash[:warning] = l(:notice_project_workflow_copy_left_empty, count: emptied) if emptied.positive?
    end
  end
end
