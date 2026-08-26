# frozen_string_literal: true

# The three actions of INV-3, as three routes.
#
#   POST   /project_workflow_scopes         enable a project's own workflow
#   DELETE /project_workflow_scopes         return the project to inheritance
#   POST   /project_workflow_scopes/clear   empty the project's matrix
#
# They are reached from the administration workflow screens. WP4 adds the
# project settings tab, where the same three actions are authorized with
# +manage_project_workflow+ against the project they act on; until then they are
# administrator-only, which satisfies INV-7 trivially.
#
# Every id that reaches a query is resolved against the database first and
# compared back to what was sent (G5). Rails casts loosely enough in
# +where(id:)+ that '1e5' and '01' both resolve to project 1, so the shape of
# each value is checked before it is used.
class ProjectWorkflowScopesController < ApplicationController
  before_action :require_admin
  before_action :find_rule_type
  before_action :find_scope_selection

  def create
    copy_generic = params[:source].to_s != 'empty'
    touched = RedmineProjectWorkflows::Services::ScopeWriter.enable(
      project_ids: @project_ids, tracker_ids: @tracker_ids, role_ids: @role_ids,
      rule_type: @rule_type, copy_generic: copy_generic, user: User.current
    )
    report(touched, copy_generic ? :notice_project_workflow_enabled_copy : :notice_project_workflow_enabled_empty)
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

    @project_ids = all ? Project.pluck(:id) : resolve_ids(Project, values)
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

  def report(touched, notice_key)
    if touched.positive?
      flash[:notice] = l(notice_key, count: touched)
    else
      flash[:warning] = l(:notice_project_workflow_scope_unchanged)
    end
    redirect_to matrix_path
  end

  def matrix_path
    options = {
      project_id: params[:project_id],
      tracker_id: @tracker_ids,
      role_id: @role_ids,
      used_statuses_only: params[:used_statuses_only]
    }
    if @rule_type == ProjectWorkflowScope::PERMISSIONS
      permissions_workflows_path(options)
    else
      edit_workflows_path(options)
    end
  end
end
