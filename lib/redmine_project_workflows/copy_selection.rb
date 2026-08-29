# frozen_string_literal: true

module RedmineProjectWorkflows
  # Every way the copy screen's six selectors can be wrong, checked before
  # anything is written -- because every write on that screen first deletes what
  # the target pair already had.
  #
  # Extracted from ProjectWorkflowRulesController for the reason AdminMatrix was:
  # Metrics/ClassLength crossed at 249/200 and that limit is already relaxed with
  # a rationale. The unit is coherent on its own -- it decides nothing about what
  # a copy does, only whether the request named something real.
  #
  # **Why any of this exists.** Core cannot tell a selection from a mistake here.
  # A source tracker or role that names nothing resolves to nil, which is also how
  # "same as the target" is spelled, so a stale form naming a deleted tracker
  # copies from *every* tracker instead of being reported (codex F01). A target
  # tracker or role that names nothing is dropped from core's `where(id: ...)`, so
  # a selection of one live tracker and one deleted one is applied to the live one
  # and reported as a success (codex F02).
  #
  # Every method here is private, because the module is mixed into a controller
  # and a public instance method there is an action.
  module CopySelection
    private

    # The three ways a copy is refused once its selectors have resolved. Renders
    # the form again with the message and answers true, for the action to return
    # on.
    def copy_refused?(source_project_id, resolved_target_project_ids, invalid_target_project_ids)
      if unresolved_source_project?(source_project_id)
        @source_project_id = nil
        flash.now[:error] = l(:error_workflow_copy_source_project)
      elsif invalid_target_project_ids.present?
        @source_project_id = source_project_id
        flash.now[:error] = l(:error_workflow_copy_target_project)
      elsif @target_trackers.blank? || @target_roles.blank? || resolved_target_project_ids.blank?
        flash.now[:error] = l(:error_workflow_copy_target)
      else
        return false
      end
      render :copy
      true
    end

    # Blank means "the generic workflow", which is what core copies from and what
    # the form preselects; 'any' means each target project's own. Any other value
    # has to name a project that exists, and the *shape* is checked as well as the
    # record, because core resolves such an id with `to_i` and '12abc' would
    # silently mean project 12.
    def unresolved_source_project?(source_project_id)
      return true if params[:source_tracker_id].blank? || params[:source_role_id].blank?
      return true if @source_tracker.nil? && @source_role.nil?
      return false if source_project_id.blank? || %w[any global].include?(source_project_id)

      !source_project_id.to_s.match?(/\A\d+\z/) || !Project.exists?(source_project_id.to_i)
    end

    # The copy form's "which workflow" selectors, checked before anything is
    # written, because every write on this screen first deletes what the target
    # pair already had.
    #
    # Core cannot tell a selection from a mistake here. A source tracker or role
    # that names nothing resolves to nil -- which is also how "same as the target"
    # is spelled -- so a stale form naming a deleted tracker copies from every
    # tracker instead of being reported (codex F01). A target tracker or role that
    # names nothing is dropped from core's `where(id: ...)`, so a selection of one
    # live tracker and one deleted one is applied to the live one and reported as a
    # success (codex F02).
    def invalid_copy_selection?
      if unresolved_source_selection?
        @source_project_id = nil
        flash.now[:error] = l(:error_workflow_copy_source)
      elsif unresolved_target_selection?
        @source_project_id = params[:source_project_id].presence
        flash.now[:error] = l(:error_workflow_copy_target_tracker_or_role)
      else
        return false
      end
      render :copy
      true
    end

    def unresolved_source_selection?
      unresolved_source?(params[:source_tracker_id], @source_tracker) ||
        unresolved_source?(params[:source_role_id], @source_role)
    end

    # 'any' is a selection, and a selector left blank is already reported by the
    # branch that owns it. An id of any other shape has to resolve to the record it
    # names, and the shape is checked as well as the record, because core resolves
    # the id with `to_i`, so '12abc' silently means tracker 12.
    def unresolved_source?(value, record)
      value = value.to_s
      return false if value.blank? || value == 'any'

      !value.match?(/\A\d+\z/) || record.nil?
    end

    # Both target selectors, through the one resolver (WP18). It de-duplicates
    # the way every other selector on the plugin now does: an id repeated in a
    # selection is one selection, not a missing record.
    def unresolved_target_selection?
      !@target_tracker_selection.exact? || !@target_role_selection.exact?
    end
  end
end
