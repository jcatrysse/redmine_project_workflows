# frozen_string_literal: true

# One project's own workflow, edited by that project rather than by a system
# administrator (WP4). This is the only place in the plugin where a
# non-administrator writes workflow data.
#
# The project comes from the path and from nowhere else, and +authorize+ checks
# the permission against it before any other callback runs, so no request
# parameter can widen what an action reaches (INV-7). The tracker and the role
# are picked out of lists this controller builds from the project -- the
# trackers it has enabled and the roles that have members in it -- so a
# parameter can only ever name something the project already offers.
#
# One tracker and one role at a time, deliberately. The administration screens
# edit a selection at once and need a third "no change" state in every cell for
# it; here the settings tab lists the combinations and each one opens its own
# matrix, which keeps every cell a plain yes or no. Bulk editing is WP5.
class ProjectWorkflowsController < ApplicationController
  menu_item :settings

  helper :workflows
  helper ProjectWorkflowsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_rule_type, only: %i[enable inherit clear]
  before_action :find_tracker_and_role

  def transitions
    @rule_type = ProjectWorkflowScope::TRANSITIONS
    load_matrix
    # Core's own edit action, narrowed to one project, one tracker and one role,
    # and with an explicit project_id predicate either way (INV-4).
    workflows = WorkflowTransition.where(
      project_id: displayed_project_id, tracker_id: @tracker.id, role_id: @role.id
    ).preload(:old_status, :new_status)
    @workflows = {
      'always' => workflows.reject { |workflow| workflow.author || workflow.assignee },
      'author' => workflows.select(&:author),
      'assignee' => workflows.select(&:assignee)
    }
  end

  def update_transitions
    @rule_type = ProjectWorkflowScope::TRANSITIONS
    return if refuse_write_while_inheriting?

    if params[:transitions]
      RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions_for_project_id(
        @project.id, [@tracker], [@role], transitions_params
      )
      flash[:notice] = l(:notice_successful_update)
    end
    redirect_to matrix_path
  end

  def permissions
    @rule_type = ProjectWorkflowScope::PERMISSIONS
    load_matrix
    @fields = (Tracker::CORE_FIELDS_ALL - @tracker.disabled_core_fields).map do |field|
      [field, l("field_#{field.sub(/_id$/, '')}")]
    end
    @custom_fields = @tracker.custom_fields.to_a.sort
    @permissions = RedmineProjectWorkflows::Services::PermissionQuery.rules_by_status_id_for_project(
      [@tracker], [@role], [displayed_project_id]
    )
    @statuses.each { |status| @permissions[status.id] ||= {} }
  end

  def update_permissions
    @rule_type = ProjectWorkflowScope::PERMISSIONS
    return if refuse_write_while_inheriting?

    if params[:permissions]
      RedmineProjectWorkflows::Services::PermissionWriter.replace_permissions_for_project_id(
        @project.id, [@tracker], [@role], permissions_params
      )
      flash[:notice] = l(:notice_successful_update)
    end
    redirect_to matrix_path
  end

  # The three actions of INV-3, for this project and this one combination. They
  # go through ScopeWriter like the administration screens do; the only
  # difference is that the selection cannot be anything but this project.
  def enable
    copy_generic = params[:source].to_s != 'empty'
    touched = RedmineProjectWorkflows::Services::ScopeWriter.enable(
      **writer_selection, copy_generic: copy_generic, user: User.current
    )
    report(touched, copy_generic ? :notice_project_workflow_enabled_copy : :notice_project_workflow_enabled_empty)
  end

  def inherit
    touched = RedmineProjectWorkflows::Services::ScopeWriter.return_to_inheritance(**writer_selection)
    report(touched, :notice_project_workflow_inherited)
  end

  def clear
    touched = RedmineProjectWorkflows::Services::ScopeWriter.clear_rules(
      **writer_selection, user: User.current
    )
    report(touched, :notice_project_workflow_emptied)
  end

  private

  # Only for the three scope actions: the two matrices know their own rule type
  # and never read it from the request.
  def find_rule_type
    @rule_type = params[:rule_type].to_s
    render_404 unless ProjectWorkflowScope::RULE_TYPES.include?(@rule_type)
  end

  # Selection by intersection with a list built from the project, never by a
  # query on the parameter: Project.where(id: ['1e5']) resolves to project 1, so
  # the shape of an id is not something to rely on (INV-7).
  #
  # Rendering here is safe -- unlike core's WorkflowsController, which declares
  # its finders before +require_admin+ -- because +authorize+ has already run.
  def find_tracker_and_role
    return if performed?

    options = RedmineProjectWorkflows::Services::ProjectOptions
    @tracker = options.trackers(@project).detect { |tracker| tracker.id.to_s == params[:tracker_id].to_s }
    @role = options.roles(@project).detect { |role| role.id.to_s == params[:role_id].to_s }
    render_404 if @tracker.nil? || @role.nil?
  end

  # Everything both matrices need, so that the views query nothing themselves.
  def load_matrix
    @trackers = [@tracker]
    @roles = [@role]
    # WorkflowsHelper decides from these how many workflows one cell stands for.
    # One project, and the generic workflow is not part of the selection, so a
    # cell is one workflow and never needs the "no change" option.
    @projects_for_update = [@project]
    @global_selected = false

    @scope_state = scope_state
    @own_workflow = @scope_state.scoped?
    @manage_project_workflow = User.current.allowed_to?(:manage_project_workflow, @project)
    @editable = @own_workflow && @manage_project_workflow
    load_statuses
  end

  # Which population the grid shows. A project that has taken this combination
  # over shows its own rules; one that inherits shows the generic rules, as the
  # read-only reference of what applies to it today (INV-5: a scope replaces, so
  # until the project takes over the generic rules are the whole answer).
  def displayed_project_id
    @own_workflow ? @project.id : nil
  end

  def scope_state
    RedmineProjectWorkflows::Services::ScopeState.new(
      project_ids: [@project.id], tracker_ids: [@tracker.id],
      role_ids: [@role.id], rule_type: @rule_type
    )
  end

  # "Only display statuses that are used by this tracker", as on core's screens,
  # but asked of this project's effective workflow rather than of every project
  # at once. A combination whose workflow is deliberately empty answers nothing,
  # which still falls back to every status -- the only way an empty matrix can
  # be filled in.
  def load_statuses
    @used_statuses_only = params[:used_statuses_only] != '0'
    @statuses = used_statuses || IssueStatus.sorted.to_a
  end

  # nil when the checkbox is off, and nil as well when the answer is empty --
  # which is what makes an own empty workflow fillable in.
  def used_statuses
    return nil unless @used_statuses_only

    status_ids = RedmineProjectWorkflows::Services::StatusListQuery.status_ids_for_pairs(
      pairs: [[@project.id, @tracker.id]],
      role_ids: Role.all.select(&:consider_workflow?).map(&:id)
    )
    IssueStatus.where(id: status_ids).sorted.to_a.presence
  end

  # A save while the project inherits is refused rather than accepted.
  #
  # TransitionWriter and PermissionWriter create the scope a project write
  # implies, so accepting it would turn "save" into "enable" -- and this screen
  # never offered an editable grid in the first place, because a project that
  # inherits sees the generic workflow read-only. The three actions of INV-3
  # stay the only way to take a workflow over.
  def refuse_write_while_inheriting?
    @own_workflow = scope_state.scoped?
    return false if @own_workflow

    flash[:warning] = l(:notice_project_workflow_not_own)
    redirect_to matrix_path
    true
  end

  def writer_selection
    {
      project_ids: [@project.id], tracker_ids: [@tracker.id],
      role_ids: [@role.id], rule_type: @rule_type
    }
  end

  def report(touched, notice_key)
    if touched.positive?
      flash[:notice] = l(notice_key, count: touched)
    else
      flash[:warning] = l(:notice_project_workflow_scope_unchanged)
    end
    # The scope panel on a matrix screen sends no back_url, so an action taken
    # there comes back to that matrix; the settings tab sends one, so an action
    # taken there comes back to the tab.
    redirect_back_or_default(matrix_path)
  end

  def matrix_path
    options = { tracker_id: @tracker.id, role_id: @role.id,
                used_statuses_only: params[:used_statuses_only] }
    if @rule_type == ProjectWorkflowScope::PERMISSIONS
      project_workflow_permissions_path(@project, options)
    else
      project_workflow_transitions_path(@project, options)
    end
  end

  def transitions_params
    transitions = to_plain_hash(params[:transitions])
    transitions.each_value do |transitions_by_new_status|
      next unless transitions_by_new_status.respond_to?(:each_value)

      transitions_by_new_status.each_value do |transition_by_rule|
        transition_by_rule.reject! { |_rule, transition| transition == 'no_change' } if transition_by_rule.is_a?(Hash)
      end
    end
    transitions
  end

  def permissions_params
    permissions = to_plain_hash(params[:permissions])
    permissions.each_value do |rule_by_field|
      rule_by_field.reject! { |_field, rule| rule == 'no_change' } if rule_by_field.is_a?(Hash)
    end
    permissions
  end

  def to_plain_hash(value)
    return {} if value.nil?
    return value.to_unsafe_h if value.respond_to?(:to_unsafe_h)

    value.respond_to?(:to_h) ? value.to_h : {}
  end
end
