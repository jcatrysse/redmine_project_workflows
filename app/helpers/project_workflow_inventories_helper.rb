# frozen_string_literal: true

# View helpers for the inventory screen. Included explicitly by
# ProjectWorkflowInventoriesController: Rails' include_all_helpers only reaches
# the host application's app/helpers, not a plugin's.
module ProjectWorkflowInventoriesHelper
  include RedmineProjectWorkflows::VersionHelper

  # One filter control: a multiple select over a list the server built, with
  # an explicit "all" entry that submits nothing.
  #
  # Deliberately not options_for_workflow_select: the plugin patches that
  # helper to put the generic workflow into every 'project_id[]' select, and
  # the generic workflow is exactly what the inventory does not have rows for.
  def project_workflow_inventory_filter_select(name, id, records, selected)
    selected_ids = Array(selected).map(&:id)
    options = content_tag('option', l(:label_all), value: '', selected: selected_ids.empty?)
    options += options_from_collection_for_select(records, 'id', 'name', selected_ids)

    select_tag(name, options, multiple: selected_ids.size > 1, id: id, class: 'expandable') +
      project_workflows_toggle_multiselect_tag
  end

  # The state of one cell, as text. Three states have to stay tellable apart
  # (INV-3) and "own empty workflow" is a deliberate configuration, so it is
  # named rather than marked as a fault. The class only carries colour; it
  # never carries the meaning.
  def project_workflow_inventory_state_tag(cell)
    key =
      case cell.state
      when :own then :label_project_workflow_state_own
      when :own_empty then :label_project_workflow_state_own_empty
      else :label_project_workflow_state_inherits
      end
    content_tag(:span, l(key), class: "project-workflow-scope-state #{cell.state}")
  end

  # Which of the two matrices a column is about.
  def project_workflow_rule_type_label(rule_type)
    if rule_type == ProjectWorkflowScope::PERMISSIONS
      l(:label_fields_permissions)
    else
      l(:label_status_transitions)
    end
  end

  # The filters currently in force, so that a link from this page can change
  # one of them and keep the rest. Nothing here is trusted on the way back in:
  # the controller intersects every value with a list it built itself.
  def project_workflow_inventory_filter_params(overrides = {})
    {
      project_id: Array(@selected_projects).map(&:id),
      tracker_id: Array(@selected_trackers).map(&:id),
      role_id: Array(@selected_roles).map(&:id),
      rule_type: @rule_type,
      deviations_only: @deviations_only ? '1' : '0'
    }.merge(overrides)
  end

  # The number of rules that apply to this cell, linking into the matrix that
  # holds them, pre-filled with exactly this project, tracker and role.
  def project_workflow_inventory_count_link(cell, row, rule_type)
    options = { project_id: [row.project.id], tracker_id: [row.tracker.id], role_id: [row.role.id] }
    path =
      if rule_type == ProjectWorkflowScope::PERMISSIONS
        permissions_workflows_path(options)
      else
        edit_workflows_path(options)
      end
    link_to(cell.rule_count, path, title: l(:button_edit))
  end
end
