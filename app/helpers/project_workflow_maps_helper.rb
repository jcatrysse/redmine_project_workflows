# frozen_string_literal: true

# The issue form's workflow panel (WP8): the link that opens it, and the two
# things the panel says that no other screen does -- which of the three states
# of INV-3 governs the reader, and where that workflow is changed.
#
# Named explicitly by ProjectWorkflowMapsController, and added to
# IssuesController's helper chain by
# RedmineProjectWorkflows::Patches::IssuesControllerPatch, because the link is
# rendered into a view a *core* controller owns and Rails'
# include_all_helpers does not reach a plugin's app/helpers.
#
# Only {project_workflow_map_link} is used from a core view, and it depends on
# nothing but the VersionHelper included above. Everything else here is rendered
# by ProjectWorkflowMapsController, which names ProjectWorkflowsHelper as well --
# the three state labels and the condition labels come from there, so that the
# panel and the project screens cannot drift apart about what to call a thing.
module ProjectWorkflowMapsHelper
  include RedmineProjectWorkflows::VersionHelper

  # The project's own transitions matrix, which is where a project screen leads.
  # The same action ProjectWorkflowsController authorizes, so asking about it
  # asks exactly what that controller will (INV-7 -- the link is a convenience,
  # never the gate).
  TAB_ACTION = { controller: 'project_workflows', action: 'transitions' }.freeze

  # The link beside core's own status dropdown and its help icon.
  #
  # Remote, like core's own "new version" and "new category" links on the same
  # form: rails-ujs is loaded on all three supported versions, so the panel
  # arrives in core's #ajax-modal, and a browser without JavaScript follows the
  # href to the same content as a page of its own.
  #
  # The tracker travels with it so that the panel describes the tracker the form
  # currently shows: core re-renders the whole form whenever it changes, so this
  # link is rebuilt with it. Nothing else is passed -- the project comes from the
  # issue, and for a saved issue so does everything else (INV-7).
  def project_workflow_map_link(issue)
    project = issue.project
    return if project.nil? || issue.tracker_id.blank?

    label = l(:label_project_workflow_map)
    path =
      if issue.new_record?
        project_workflow_map_path(project, tracker_id: issue.tracker_id)
      else
        issue_workflow_map_path(issue, tracker_id: issue.tracker_id)
      end

    link_to(project_workflows_icon_body('workflows', label), path,
            remote: true, method: 'get', title: label,
            class: 'icon-only icon-workflows project-workflow-map-link')
  end

  # Where this workflow is changed, or nothing at all.
  #
  # A link that answers 403 is worse than no link, so the offer is gated -- and
  # gated on the very action the target authorizes, not on a permission name,
  # because two permissions reach that screen.
  #
  # Which screen depends on which workflow actually governs. A combination the
  # project has taken over is changed on the project's own tab. One that inherits
  # is governed by the *generic* workflow, so an administrator is sent to
  # Administration -> Workflow, pre-filled with this project, tracker and role --
  # where the project selector the plugin adds is what makes "pre-filled with
  # this project" mean anything. A project manager still goes to the tab, because
  # from there the useful action is to give the project a workflow of its own.
  def project_workflow_map_edit_link(project, tracker, role, state)
    generic = state.to_sym == :inherits
    return administration_workflow_link(project, tracker, role) if generic && User.current.admin?

    if User.current.allowed_to?(TAB_ACTION, project)
      link_to(l(:label_project_workflow_open_matrix),
              project_workflow_transitions_path(project, tracker_id: tracker.id, role_id: role.id))
    elsif User.current.admin?
      administration_workflow_link(project, tracker, role)
    end
  end

  # What one move requires, in one phrase.
  #
  # Deliberately *not* the comparison screen's condition labels. Those say "Also
  # when the user is the author", which is core's own framing of a whole grid --
  # the author grid holds what the always grid does not. Here the conditions of
  # one move have already been collapsed, so a move naming only the author grid
  # is a move only the author may make, and "also" would say the opposite of the
  # truth. The one they do share is the unconditional case, which means the same
  # thing on both screens and therefore keeps the same words.
  #
  # Both grids at once is its own phrase rather than two joined by a comma: "only
  # the author" beside "only the assignee" reads as a contradiction.
  def project_workflow_map_conditions_label(conditions)
    conditions = Array(conditions)
    return l(:label_project_workflow_condition_always) if conditions.include?('always')

    author = conditions.include?('author')
    assignee = conditions.include?('assignee')
    if author && assignee
      l(:label_project_workflow_map_condition_author_or_assignee)
    elsif author
      l(:label_project_workflow_map_condition_author)
    elsif assignee
      l(:label_project_workflow_map_condition_assignee)
    end
  end

  # Whether the status list on the form offers this move now, and why not when it
  # does not. Words carry the whole meaning; the class is a hook for a theme, and
  # the plugin ships no stylesheet.
  def project_workflow_map_availability_tag(edge)
    label = edge.available ? l(:general_text_Yes) : l(:general_text_No)
    tag = content_tag(:span, label,
                      class: "project-workflow-map-availability #{edge.available ? 'available' : 'withheld'}")
    return tag if edge.reason.blank?

    safe_join([tag, content_tag(:span, edge.reason, class: 'project-workflow-map-reason')], ' ')
  end

  # Which of the reader's roles permit one move. Rendered only where the reader
  # holds more than one role that takes part in a workflow: with one role the
  # column would repeat the same name on every line, and the panel already names
  # it above.
  def project_workflow_map_roles_label(roles)
    Array(roles).map(&:name).join(', ')
  end

  private

  # The plugin's own matrix, not Redmine's: since ADR-003 core's screens read no
  # project parameter, so this link would have opened the generic matrix while
  # naming the project in its label.
  def administration_workflow_link(project, tracker, role)
    link_to(l(:label_project_workflow_open_matrix),
            edit_project_workflow_rules_path(project_id: [project.id], tracker_id: [tracker.id],
                                             role_id: [role.id]))
  end
end
