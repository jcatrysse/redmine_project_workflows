# frozen_string_literal: true

# The inventory: which projects run their own workflow, for which tracker, role
# and kind of rule -- the question the workflow summary page cannot answer,
# because it is a grid of trackers and roles for one selection at a time.
#
# One row per (project, tracker, role), a column per rule type, and the state
# named in words. It reads; it changes nothing. The three actions of INV-3 stay
# on the matrix screens, and each row links into the matrix it describes.
#
# Administrator-only for now, which satisfies INV-7 trivially. WP4 adds the
# project settings tab, where the same information is authorized with
# +view_project_workflow+ against the one project it is about.
class ProjectWorkflowInventoriesController < ApplicationController
  layout 'admin'
  self.main_menu = false
  helper ProjectWorkflowInventoriesHelper
  before_action :require_admin

  def index
    load_filter_options
    load_filter_selection

    query = RedmineProjectWorkflows::Services::InventoryQuery.new(
      projects: @selected_projects || @projects,
      trackers: @selected_trackers || @trackers,
      roles: @selected_roles || @roles,
      rule_types: @rule_types,
      deviations_only: @deviations_only
    )

    @row_count = query.total
    @limit = per_page_option
    @pages = Redmine::Pagination::Paginator.new(@row_count, @limit, params['page'])
    @rows = query.rows(offset: @pages.offset, limit: @limit)
  end

  private

  # The lists every filter is intersected with. They are built here, from the
  # database, so that no request parameter can name anything that is not on
  # them (INV-7, G5) -- a filter can only ever narrow what the server already
  # decided to offer.
  def load_filter_options
    @projects = Project.sorted.to_a
    @trackers = Tracker.sorted.to_a
    @roles = Role.sorted.select(&:consider_workflow?)
  end

  def load_filter_selection
    @invalid_filter_values = []
    @selected_projects = filter_selection(@projects, :project_id)
    @selected_trackers = filter_selection(@trackers, :tracker_id)
    @selected_roles = filter_selection(@roles, :role_id)
    load_rule_type_filter
    @deviations_only = params[:deviations_only].to_s != '0'

    return if @invalid_filter_values.empty?

    # A filter is a form the operator can correct, so a value that no longer
    # resolves is a message and a narrowed result, not a 404. The 404 in
    # ProjectWorkflowScopesController is for links the screen itself generated,
    # which is a different situation.
    flash.now[:warning] = l(:error_project_workflow_inventory_filter)
  end

  # Which of the two matrices the page is about. Unset means both.
  def load_rule_type_filter
    requested = params[:rule_type].to_s.presence
    @rule_type = ProjectWorkflowScope::RULE_TYPES.include?(requested) ? requested : nil
    @invalid_filter_values << requested if requested && @rule_type.nil?
    @rule_types = @rule_type ? [@rule_type] : ProjectWorkflowScope::RULE_TYPES
  end

  # Selection by intersection: the parameter picks from the loaded list rather
  # than reaching the database itself, so a value of the wrong shape resolves
  # to nothing instead of to whatever Rails casts it to -- Project.where(id:
  # ['1e5']) returns project 1.
  #
  # nil means "no filter, so all of them"; an empty array means "a filter was
  # given and nothing survived it". They must not be the same answer, or a
  # filter naming one project that no longer exists would quietly widen the
  # page to every project.
  def filter_selection(records, key)
    values = Array.wrap(params[key]).reject(&:blank?).map(&:to_s).uniq
    return nil if values.empty?

    selected = records.select { |record| values.include?(record.id.to_s) }
    @invalid_filter_values += values - selected.map { |record| record.id.to_s }
    selected
  end
end
