# frozen_string_literal: true

# The project dimension of the workflow, on screens the plugin owns (WP12,
# ADR-003).
#
# Redmine's own Administration → Workflow screens go on doing exactly what
# Redmine does, for the generic workflow and nothing else. Everything about
# projects -- the selector, the scope panel, the summary counts, the copy form
# -- is here, on the plugin's own routes, in the plugin's own views.
#
# **Why this exists at all.** Before ADR-003 all of this hung off core's screens
# through eleven Deface overrides and a 468-line patch replacing six core
# actions. An unmatched Deface anchor is silent (INV-9), and the anchors most
# likely to stop matching on a Redmine upgrade were exactly the ones on views the
# plugin does not own. Owning the screen removes the hazard rather than testing
# for it.
#
# **What is still core's:** the grid. `workflows/_form` is rendered unchanged,
# as `ProjectWorkflowsController` has rendered it since WP4 -- copying it would
# trade an anchor for a view that has to track core, which is the same tax in a
# different currency (ADR-003, alternatives considered).
#
# Administrator-only, like the screens it takes the project dimension off.
# `require_admin` is declared **first**, before any finder: core declares its own
# finders before it, which is how /workflows/edit came to answer an anonymous
# visitor 404 for a project id that does not exist and a login redirect for one
# that does (finding G01). Here there is nothing to work around -- the callback
# order is the plugin's to choose, and it chooses authorization first.
class ProjectWorkflowRulesController < ApplicationController
  layout 'admin'
  self.main_menu = false

  # How a request names projects, and what that resolves to (INV-4: every query
  # below carries an explicit project_id predicate, `nil` for the generic
  # workflow). Every method it adds is private, because a public instance method
  # of a controller is an action.
  include RedmineProjectWorkflows::WorkflowSelection
  # Whether the copy screen's six selectors named anything real, checked before a
  # single rule is written.
  include RedmineProjectWorkflows::CopySelection
  # What the copy screen does to the scope table, and what it says afterwards.
  include RedmineProjectWorkflows::CopyScopes
  # Everything between "the operator pressed Save" and the redirect: the write,
  # the message, and the parameter shaping in front of it.
  include RedmineProjectWorkflows::AdminMatrix

  # Core's own workflow views and helpers: `workflows/_form` is rendered
  # unchanged, and `field_required?` comes from `WorkflowsHelper`.
  helper :workflows
  # The cells the plugin draws differently from core -- a mixed cell as a
  # <select>, and the row and column actions of WP5 -- plus the scope state
  # label and the summary count link.
  helper ProjectWorkflowMatrixHelper
  # The inventory link and the state vocabulary shared with the project screens.
  helper ProjectWorkflowsHelper

  before_action :require_admin
  before_action :find_trackers_roles_and_statuses, only: %i[edit update permissions update_permissions]

  # The summary: a grid of trackers and roles counting the rules of whichever
  # workflow the selector names.
  #
  # Core's own body is the first two lines plus a count with no project_id
  # predicate at all, so every project's rules were added into the generic
  # totals -- a project that had taken over one tracker made the generic
  # workflow look like it had rules it does not have (claude F01, INV-4).
  def index
    @roles = Role.sorted.select(&:consider_workflow?)
    @trackers = Tracker.sorted
    load_project_options
    return if invalid_selection?

    @project_workflow_selection = summary_selection_param_values
    @workflow_counts = WorkflowTransition
                       .where(project_id: workflow_project_ids)
                       .group(:tracker_id, :role_id).count
  end

  # The status transitions matrix for the selection.
  def edit
    return if invalid_selection?
    return unless @trackers.present? && @roles.present? && @statuses.any?

    @project_workflow_scope_state = scope_state_for(ProjectWorkflowScope::TRANSITIONS)
    @workflows = transitions_by_condition(
      WorkflowTransition
        .where(role_id: @roles.map(&:id), tracker_id: @trackers.map(&:id),
               project_id: workflow_project_ids)
        .preload(:old_status, :new_status)
    )
  end

  def update
    return if invalid_selection?

    @rule_type_for_log = ProjectWorkflowScope::TRANSITIONS
    if @roles.present? && @trackers.present? && params[:transitions]
      write_matrix(RedmineProjectWorkflows::Services::TransitionWriter,
                   :replace_transitions_for_project_id, strip_no_change(params[:transitions]))
    end
    redirect_to edit_project_workflow_rules_path(matrix_redirect_params)
  end

  # See #edit: the same reason, for the field permissions matrix.
  def permissions
    return if invalid_selection?
    return unless @roles.present? && @trackers.present?

    @project_workflow_scope_state = scope_state_for(ProjectWorkflowScope::PERMISSIONS)
    @fields = (Tracker::CORE_FIELDS_ALL - @trackers.map(&:disabled_core_fields).reduce(:&)).map do |field|
      [field, l("field_#{field.delete_suffix('_id')}")]
    end
    @custom_fields = @trackers.map(&:custom_fields).flatten.uniq.sort
    @permissions = RedmineProjectWorkflows::Services::PermissionQuery.rules_by_status_id_for_project(
      @trackers, @roles, workflow_project_ids
    )
    @statuses.each { |status| @permissions[status.id] ||= {} }
  end

  def update_permissions
    return if invalid_selection?

    @rule_type_for_log = ProjectWorkflowScope::PERMISSIONS
    if @roles.present? && @trackers.present? && params[:permissions]
      # The payload is `permissions[<status>][<field>]`, which is what
      # WorkflowsHelper#field_permission_tag emits on 5.1, 6.1 and 7.0 alike and
      # what the plugin's own grid emits too. Core's own update_permissions names
      # its block variables as though it were field-first; that is stale naming
      # rather than a second shape (finding F14).
      write_matrix(RedmineProjectWorkflows::Services::PermissionWriter,
                   :replace_permissions_for_project_id, strip_no_change(params[:permissions]))
    end
    redirect_to permissions_project_workflow_rules_path(matrix_redirect_params)
  end

  def copy
    load_project_options
    return if invalid_selection?

    find_sources_and_targets
    @source_project_id = params[:source_project_id].presence
  end

  # load_project_options is here for its @projects side effect alone -- the copy
  # form's two project selectors are `source_project_id` and
  # `target_project_ids[]`, and it builds the list both are rendered from.
  #
  # Deliberately no `invalid_selection?` after it, unlike #copy: this
  # action never reads params[:project_id], so an id in it names nothing and can
  # widen nothing, and answering 404 for a parameter the action ignores would be
  # reporting a fault that does not exist. The two selectors it does read are
  # validated in full below and in validated_target_project_ids, shape as well as
  # record (finding F07).
  def duplicate
    load_project_options
    find_sources_and_targets
    return if invalid_copy_selection?

    source_project_id = params[:source_project_id].presence
    resolved_target_project_ids, invalid_target_project_ids = validated_target_project_ids
    return if copy_refused?(source_project_id, resolved_target_project_ids, invalid_target_project_ids)

    @source_project_id = source_project_id
    report_copy(run_copy(source_project_id, resolved_target_project_ids))
    redirect_to copy_project_workflow_rules_path(
      source_tracker_id: @source_tracker, source_role_id: @source_role,
      source_project_id: source_project_id
    )
  end

  private

  # Core's three grids: what always applies, and what the author and the assignee
  # may do on top of it. One pass over the rows, in the three groups core's own
  # view expects.
  def transitions_by_condition(workflows)
    {
      'always' => workflows.reject { |workflow| workflow.author || workflow.assignee },
      'author' => workflows.select(&:author),
      'assignee' => workflows.select(&:assignee)
    }
  end

  def run_copy(source_project_id, target_project_ids)
    copied = []
    ActiveRecord::Base.transaction do
      lock_scopes_for_copy(source_project_id, target_project_ids)
      target_project_ids.each do |target_project_id|
        pairs = WorkflowRule.copy_for_project(
          resolved_copy_source(source_project_id, target_project_id), target_project_id,
          @source_tracker, @source_role, @target_trackers, @target_roles
        )
        copied.concat(RedmineProjectWorkflows::Services::ScopeCombinations.for_project(target_project_id, pairs))
      end
      record_scopes_for_copy(copied)
    end
    copied
  end

  # Core's own body, with `to_a` on the two source finders left as core has it.
  # A copy rather than a call, because ADR-003 leaves nothing of the plugin's
  # inside core's controller and this is a private method of it.
  def find_sources_and_targets
    @roles = Role.sorted.select(&:consider_workflow?)
    @trackers = Tracker.sorted
    @source_tracker = find_copy_source(Tracker, params[:source_tracker_id])
    @source_role = find_copy_source(Role, params[:source_role_id])
    @target_tracker_selection = exact_targets(params[:target_tracker_ids], @trackers.to_a)
    @target_role_selection = exact_targets(params[:target_role_ids], @roles)
    @target_trackers = @target_tracker_selection.presence
    @target_roles = @target_role_selection.presence
  end

  # WP18. The target selectors resolve against the very lists this form offers,
  # not against every record of the class -- so a role the form does not list,
  # because it takes no part in a workflow, is now refused rather than copied to.
  # Core's own body resolved against the class and reported success.
  def exact_targets(param, candidates)
    RedmineProjectWorkflows::Services::ExactSelection.resolve(param, candidates: candidates)
  end

  # nil for both "not chosen" and "same as the target", which is core's own
  # conflation -- #unresolved_source? is what tells the two apart before anything
  # is written.
  def find_copy_source(klass, value)
    return nil if value.blank? || value == 'any'

    klass.find_by(id: value.to_i)
  end

  # Prepared after `require_admin` rather than before it, which is the whole
  # reason these screens are here rather than on core's controller.
  def find_trackers_roles_and_statuses
    find_roles
    find_trackers
    load_project_options
    record_unresolved(@role_selection, @tracker_selection)
    find_statuses
  end

  # Core's own bodies were `klass.where(id: ids).to_a`, and that is finding F03
  # of 2026-08-29-claude-revalidation: whatever resolved was the selection, a
  # value naming nothing was dropped, and a value of the wrong shape was *cast*
  # -- `tracker_id=1e5` wrote rules for tracker 1 and reported *Successful
  # update*. This screen is the one that writes, and every matrix save deletes
  # before it inserts, so it is the last place that should be the most forgiving.
  #
  # `all` is the keyword core's own selector submits, and it stays a keyword
  # rather than becoming an id nothing matches.
  def find_roles
    @role_selection = RedmineProjectWorkflows::Services::ExactSelection.resolve(
      params[:role_id], candidates: Role.sorted.select(&:consider_workflow?), keywords: %w[all]
    )
    @roles = selection_records(@role_selection, Role.sorted.select(&:consider_workflow?))
  end

  def find_trackers
    @tracker_selection = RedmineProjectWorkflows::Services::ExactSelection.resolve(
      params[:tracker_id], candidates: Tracker.sorted.to_a, keywords: %w[all]
    )
    @trackers = selection_records(@tracker_selection, Tracker.sorted.to_a)
  end

  # nil for "nothing was selected", which is the state both matrices render the
  # selector for; the whole list for `all`.
  def selection_records(selection, all)
    return all.presence if selection.keyword?('all')

    selection.presence
  end

  # "Only display statuses that are used by this tracker" -- the checkbox above
  # both matrices.
  #
  # It used to filter on the physically selected project ids, so for a project
  # that inherits it found no rows at all, .presence then fell back to *every*
  # status, and the filter silently switched itself off in exactly the case where
  # it was wanted (external F04). It now asks for the effective workflow of the
  # selection: a project that inherits answers with the generic statuses, one
  # with its own workflow answers with its own, and a project whose workflow is
  # deliberately empty answers with nothing -- which still falls back to every
  # status, because that is the only way an administrator can fill an empty
  # matrix in.
  #
  # The role filter is core's own, kept as it is: the question is which statuses
  # the workflow uses, not which the selected roles use.
  def find_statuses
    @used_statuses_only = params[:used_statuses_only] != '0'
    if @trackers && @used_statuses_only
      status_ids = RedmineProjectWorkflows::Services::StatusListQuery.status_ids_for_pairs(
        pairs: workflow_project_ids.product(@trackers.map(&:id)),
        role_ids: Role.all.select(&:consider_workflow?).map(&:id)
      )
      @statuses = IssueStatus.where(id: status_ids).sorted.to_a.presence
    end
    @statuses ||= IssueStatus.sorted.to_a
  end
end
