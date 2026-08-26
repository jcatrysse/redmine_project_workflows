# frozen_string_literal: true

# View helpers shared by the project settings tab, the project matrices and the
# administration inventory: the three states of INV-3 named in words, which of
# the two matrices a thing is about, and the path into it.
#
# Named explicitly by every controller that renders these views. Rails'
# include_all_helpers is built from the host application's helper paths and does
# not reach a plugin's app/helpers.
module ProjectWorkflowsHelper
  include RedmineProjectWorkflows::VersionHelper

  # The state of one (project, tracker, role, rule type), as text.
  #
  # Three states have to stay tellable apart (INV-3), and "own empty workflow"
  # is a deliberate configuration rather than a fault, so it is named. The class
  # only carries colour; the words carry the meaning.
  def project_workflow_state_tag(state)
    content_tag(:span, project_workflow_state_label(state),
                class: "project-workflow-scope-state #{state}")
  end

  def project_workflow_state_label(state)
    case state
    when :own then l(:label_project_workflow_state_own)
    when :own_empty then l(:label_project_workflow_state_own_empty)
    else l(:label_project_workflow_state_inherits)
    end
  end

  # Which of the two matrices a column, a tab or a link is about.
  def project_workflow_rule_type_label(rule_type)
    if rule_type == ProjectWorkflowScope::PERMISSIONS
      l(:label_fields_permissions)
    else
      l(:label_status_transitions)
    end
  end

  # The project's own matrix for one tracker, one role and one kind of rule.
  def project_workflow_matrix_path(project, tracker, role, rule_type, options = {})
    options = options.merge(tracker_id: tracker.id, role_id: role.id)
    if rule_type == ProjectWorkflowScope::PERMISSIONS
      project_workflow_permissions_path(project, options)
    else
      project_workflow_transitions_path(project, options)
    end
  end

  # One cell of a read-only field-permissions grid. The rules stored for a
  # (project, tracker, role) can only ever hold one value per field and status,
  # so the array core's query builds has at most one entry here.
  #
  # An empty cell is left empty, exactly as the editable grid's select is: the
  # field is neither read-only nor required, which is the default and needs no
  # word of its own.
  def project_workflow_permission_label(rules)
    case Array(rules).first
    when 'readonly' then l(:label_readonly)
    when 'required' then l(:label_required)
    end
  end

  # The number of rules the project holds itself, linking into the matrix that
  # holds them. Never the generic count: an inheriting combination reads 0, and
  # the state label beside it -- not the number -- says the generic workflow
  # applies, so the number always matches the matrix the link opens.
  def project_workflow_own_count_link(cell, row, rule_type)
    link_to(cell.rule_count,
            project_workflow_matrix_path(row.project, row.tracker, row.role, rule_type),
            title: l(:label_project_workflow_open_matrix))
  end
end
