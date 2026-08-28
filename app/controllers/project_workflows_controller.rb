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
  # The submitted matrix, with core's "(No change)" stripped out. Extracted
  # because Metrics/ClassLength crossed at 203/200, and that limit is already
  # relaxed in .rubocop.yml with a stated rationale -- so crossing it is a signal
  # to extract, not a cop to placate. Every method there is private: a public
  # instance method of a controller is an action.
  include RedmineProjectWorkflows::MatrixParams
  # What a write on this screen says to the operator, and what it records in the
  # log. Extracted for the same reason MatrixParams was: Metrics/ClassLength
  # crossed at 202/200, and that limit is already relaxed with a rationale.
  include RedmineProjectWorkflows::MatrixReporting

  menu_item :settings

  helper :workflows
  helper ProjectWorkflowsHelper
  # WP9's drawing, and the condition wording it shares with the issue form's
  # panel -- one phrase for one move, written once so the two screens cannot
  # drift apart about what a move requires.
  helper ProjectWorkflowGraphsHelper
  helper ProjectWorkflowMapsHelper

  before_action :find_project_by_project_id
  before_action :authorize
  before_action :find_rule_type, only: %i[compare enable inherit clear]
  # #graph is the one action that describes *several* roles at once, so it picks
  # its selection out of a list of its own rather than through the single-role
  # finder. Both finders intersect a request parameter with a list built from the
  # project and never query on the parameter itself (INV-7).
  before_action :find_tracker_and_role, except: %i[graph]
  before_action :find_tracker_and_roles, only: %i[graph]
  # Only #enable. Every other action acts on a scope that already exists, or on
  # rules under one; taking a *new* workflow over is the one thing a role with no
  # member in the project is not offered (finding F05).
  before_action :require_offered_role, only: %i[enable]

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
      report_rule_save(
        RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions_for_project_id(
          @project.id, [@tracker], [@role], transitions_params
        )
      )
    else
      # A save that carries no matrix at all. Reachable only through a
      # hand-built PATCH or an API client that omits it, so the practical impact
      # is small -- but it was the one remaining path on this screen that said
      # nothing, and the whole lesson of the earlier F06 was that a screen must
      # not stay quiet about having done nothing (finding F17).
      #
      # The existing key rather than a new one: it already reads "Nothing was
      # saved. Either no cell was changed, or the values submitted were not
      # accepted", which covers this case exactly, and it is already translated
      # in all eight locale files -- so nothing here can break
      # spec/locales_spec.rb.
      flash[:warning] = l(:notice_project_workflow_save_nothing_applied)
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
      report_rule_save(
        RedmineProjectWorkflows::Services::PermissionWriter.replace_permissions_for_project_id(
          @project.id, [@tracker], [@role], permissions_params
        )
      )
    else
      # See #update_transitions: the same silent path, the same existing key.
      flash[:warning] = l(:notice_project_workflow_save_nothing_applied)
    end
    redirect_to matrix_path
  end

  # What this project's own workflow says that the generic one does not, and the
  # other way round (WP6). Read-only, and behind the same +authorize+ as the two
  # matrices, so somebody who may see the workflow may see how it differs.
  #
  # A project that inherits has nothing to compare -- its workflow *is* the
  # generic one -- and the view says so rather than showing an empty table. That
  # also keeps a pre-WP1 database honest: rows stored against a project with no
  # scope apply to nothing (INV-3), so listing them as differences would name
  # rules that are not in force.
  def compare
    @scope_state = scope_state
    @own_workflow = @scope_state.scoped?
    return unless @own_workflow

    @comparison = RedmineProjectWorkflows::Services::WorkflowComparison.new(
      project_id: @project.id, tracker_id: @tracker.id, role_id: @role.id, rule_type: @rule_type
    ).result
    @custom_fields_by_name = @tracker.custom_fields.index_by { |field| field.id.to_s }
    # Which fields the permissions matrix can actually show, so the view can say
    # so when a difference names one it cannot. The same two lists the
    # #permissions action builds its grid from: a rule on a core field the
    # tracker has since disabled, or on a custom field removed from it, is still
    # in the table and still a difference -- and there is no control anywhere on
    # a project screen that can change it.
    @offered_field_names = (Tracker::CORE_FIELDS_ALL - @tracker.disabled_core_fields).to_set +
                           @custom_fields_by_name.keys
  end

  # The whole of this project's transitions workflow for one tracker and a
  # selection of roles, as a drawing with a table beneath it (WP9).
  #
  # Read-only, and behind the same +authorize+ as everything else here: the map
  # shows what *other* roles may do, which is project configuration rather than
  # information about one issue, so it sits behind +view_project_workflow+ while
  # the issue form's own panel keeps no permission of its own (decided by Jan,
  # 2026-08-28).
  #
  # Transitions only. Field permissions are not a graph -- they are a property of
  # a status, not of a move between two -- and the comparison screen is where
  # they are read side by side.
  def graph
    @rule_type = ProjectWorkflowScope::TRANSITIONS
    @graph = RedmineProjectWorkflows::Services::WorkflowGraphQuery.new(
      project: @project, tracker: @tracker, role_ids: @roles.map(&:id)
    ).result
    @manage_project_workflow = User.current.allowed_to?(:manage_project_workflow, @project)
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
    find_role
    render_404 if @tracker.nil? || @role.nil?
  end

  # visible_roles, not roles: a role with no member in the project that already
  # has a scope here is a workflow this project runs and has to be able to undo.
  # @role_offered records which of the two lists answered, because the offer to
  # take a new workflow over follows the narrower one -- and that narrower list
  # is built once and handed on, rather than queried twice (G6).
  def find_role
    options = RedmineProjectWorkflows::Services::ProjectOptions
    offered = options.roles(@project)
    @role = options.visible_roles(@project, offered).detect { |role| role.id.to_s == params[:role_id].to_s }
    @role_offered = @role.present? && offered.any? { |role| role.id == @role.id }
  end

  # The drawing's selection: one tracker, and one or more roles out of the very
  # list the settings tab and the matrix offer (answer B of 2026-08-28 -- every
  # role the project screen already lists, not only the reader's own).
  #
  # A role the project does not offer, or a tracker it has not enabled, answers
  # 404 rather than drawing something else: silently narrowing a selection to
  # what happens to be allowed would draw one workflow under the heading of
  # another.
  def find_tracker_and_roles
    return if performed?

    options = RedmineProjectWorkflows::Services::ProjectOptions
    @tracker = options.trackers(@project).detect { |tracker| tracker.id.to_s == params[:tracker_id].to_s }
    @visible_roles = @tracker.nil? ? [] : options.visible_roles(@project)
    @roles = selected_roles
    render_404 if @tracker.nil? || @roles.empty?
  end

  # What the request asked for, intersected with the list above -- so a parameter
  # can only ever name a role the project already offers, and no shape of it
  # reaches a query (Project.where(id: ['1e5']) resolves to project 1, which is
  # why the shape of an id is never relied on).
  #
  # With nothing asked for, the reader's own roles here, which is the union the
  # status dropdown on an issue of theirs is built from and therefore the answer
  # to "what may I do". A reader who holds none -- an administrator, or somebody
  # with the permission through a group -- gets the whole list rather than an
  # empty drawing.
  def selected_roles
    return [] if @visible_roles.empty?

    requested = requested_role_ids
    return @visible_roles.select { |role| requested.include?(role.id.to_s) } if requested.any?

    own = User.current.roles_for_project(@project).to_set(&:id)
    @visible_roles.select { |role| own.include?(role.id) }.presence || @visible_roles
  end

  # A scalar, a list, or anything else. Compared as strings against ids the
  # server already holds, so a Hash or a nested array simply matches nothing and
  # answers 404 -- it never reaches a query and never raises.
  def requested_role_ids
    value = params[:role_id]
    return [] if value.blank?

    (value.is_a?(Array) ? value : [value]).map(&:to_s)
  end

  # 403 rather than 404: the combination exists and this user may look at it, so
  # saying it is missing would be a lie. It is the action that is not on offer.
  def require_offered_role
    return if performed? || @role_offered

    render_403
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

  # What a save on this screen did. The success notice used to be set whenever
  # the request carried a matrix at all, which said "Successful update" over two
  # things that are not one (finding F06): a payload the writer's whitelist had
  # dropped in its entirety, which by design changes nothing; and a save that
  # lost the race against a concurrent return to the generic workflow, which the
  # writer refuses because it locks the scope rows it reads.
  #
  # The refusal reuses the message #refuse_write_while_inheriting? gives, because
  # by the time the writer answered it is the same fact: this project follows the
  # generic workflow here. One tracker and one role, so there is never a mixture
  # to report.

  def matrix_path
    options = { tracker_id: @tracker.id, role_id: @role.id,
                used_statuses_only: params[:used_statuses_only] }
    if @rule_type == ProjectWorkflowScope::PERMISSIONS
      project_workflow_permissions_path(@project, options)
    else
      project_workflow_transitions_path(@project, options)
    end
  end
end
