# frozen_string_literal: true

# The three actions of INV-3, as three routes.
#
#   POST   /project_workflow_scopes         enable a project's own workflow
#   DELETE /project_workflow_scopes         return the project to inheritance
#   POST   /project_workflow_scopes/clear   empty the project's matrix
#
# They are reached from the administration workflow screens and are
# administrator-only, which satisfies INV-7 trivially. The same three actions are
# also on ProjectWorkflowsController as of WP4, where they act on one project and
# are authorized with +manage_project_workflow_rules+ against it; that is the path a
# non-administrator takes, and this one stays what it is.
#
# Every id that reaches a query is resolved against the database first and
# compared back to what was sent (G5). Rails casts loosely enough in
# +where(id:)+ that '1e5' and '01' both resolve to project 1, so the shape of
# each value is checked before it is used.
class ProjectWorkflowScopesController < ApplicationController
  before_action :require_admin
  before_action :find_rule_type
  before_action :find_scope_selection

  # Bounded since ADR-004, by the same setting the matrix save uses and in the
  # same unit: above `bulk_write_ceiling` the writer raises before anything is
  # written, and the transaction it raises inside is abandoned with nothing in
  # it. Only the *copy* variant can reach it -- an own empty workflow copies no
  # rule and is therefore never refused, which is deliberate: it is the bulk
  # action that stays available at any size.
  def create
    copy_generic = params[:source].to_s != 'empty'
    touched = RedmineProjectWorkflows::Services::ScopeWriter.enable(
      project_ids: @project_ids, tracker_ids: @tracker_ids, role_ids: @role_ids,
      rule_type: @rule_type, copy_generic: copy_generic, user: User.current
    )
    report(touched, copy_generic ? :notice_project_workflow_enabled_copy : :notice_project_workflow_enabled_empty)
  rescue RedmineProjectWorkflows::Services::WriteBudget::TooLarge => e
    refuse_oversized_enable(e)
  end

  def destroy
    touched = RedmineProjectWorkflows::Services::ScopeWriter.return_to_inheritance(
      project_ids: @project_ids, tracker_ids: @tracker_ids, role_ids: @role_ids,
      rule_type: @rule_type
    )
    report(touched, :notice_project_workflow_inherited)
  end

  def clear
    touched = RedmineProjectWorkflows::Services::ScopeWriter.clear_rules(
      project_ids: @project_ids, tracker_ids: @tracker_ids, role_ids: @role_ids,
      rule_type: @rule_type, user: User.current
    )
    report(touched, :notice_project_workflow_emptied)
  end

  private

  def find_rule_type
    @rule_type = params[:rule_type].to_s
    render_404 unless ProjectWorkflowScope::RULE_TYPES.include?(@rule_type)
  end

  # 'global' is accepted and dropped: the generic workflow has no scope, so an
  # action naming it simply has nothing to do for that entry. Anything that is
  # neither a keyword nor an id that exists is a 404 -- these controls are not
  # a form the operator can correct, they are links the screen generated.
  def find_scope_selection
    values = param_values(:project_id)
    all = values.delete('all')
    values.delete('global')

    # 'all' is the selector's own keyword, so it expands to exactly what the
    # selector offered: every project that is not archived (WP13, audit F09).
    # An id named explicitly still resolves, archived or not.
    @project_ids = all ? RedmineProjectWorkflows::Services::ProjectOptions.selectable_ids : resolve_ids(Project, values)
    @tracker_ids = resolve_ids(Tracker, param_values(:tracker_id))
    @role_ids = resolve_ids(Role, param_values(:role_id))

    render_404 if @project_ids.nil? || @tracker_ids.nil? || @role_ids.nil?
  end

  def param_values(key)
    Array.wrap(params[key]).reject(&:blank?).map(&:to_s).uniq
  end

  # Returns the resolved ids, or nil when any value was not the id of an
  # existing record. One query, whatever the size of the list.
  def resolve_ids(model, values)
    return [] if values.empty?
    return nil unless values.all? { |value| value.match?(/\A\d+\z/) }

    ids = model.where(id: values.map(&:to_i)).pluck(:id)
    return nil unless ids.size == values.size

    ids
  end

  # The refusal says the number, the limit and the three ways out -- fewer
  # projects, the empty variant, or a larger limit -- and records the same line
  # in the log that the matrix save's refusal does.
  def refuse_oversized_enable(error)
    flash[:error] = l(:error_project_workflow_enable_too_large,
                      count: error.projected, ceiling: error.ceiling)
    RedmineProjectWorkflows::Services::WriteLog.record(
      'admin_scope_enable_refused',
      rule_type: @rule_type, actor: User.current.id,
      projects: @project_ids, trackers: @tracker_ids, roles: @role_ids,
      projected: error.projected, ceiling: error.ceiling
    )
    redirect_to matrix_path
  end

  def report(touched, notice_key)
    if touched.positive?
      flash[:notice] = l(notice_key, count: touched)
    else
      flash[:warning] = l(:notice_project_workflow_scope_unchanged)
    end
    # See Services::WriteLog: ids and counts only (finding F19). The selection
    # here can be every project on the installation, which is why the service
    # renders a long id list as a count rather than in full.
    RedmineProjectWorkflows::Services::WriteLog.record(
      'admin_scope_action',
      action_key: notice_key, rule_type: @rule_type, actor: User.current.id,
      projects: @project_ids, trackers: @tracker_ids, roles: @role_ids, touched: touched
    )
    redirect_to matrix_path
  end

  # Back to the matrix the panel was on. The plugin's own administration screens
  # since ADR-003: these three actions are about projects, and after WP12 the
  # project dimension is not on core's screens at all -- sending an operator back
  # to one would land them on a matrix that cannot show what they just changed.
  def matrix_path
    options = {
      project_id: params[:project_id],
      tracker_id: @tracker_ids,
      role_id: @role_ids,
      used_statuses_only: params[:used_statuses_only]
    }
    if @rule_type == ProjectWorkflowScope::PERMISSIONS
      permissions_project_workflow_rules_path(options)
    else
      edit_project_workflow_rules_path(options)
    end
  end
end
