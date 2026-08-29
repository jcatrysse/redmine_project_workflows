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

  # WP19, finding F05 of 2026-08-29-claude-revalidation. What ADR-002's
  # compatibility object knows, on the screens where somebody is about to change
  # a workflow rule.
  #
  # Workflow logic is authorization logic, and a Redmine minor that changed
  # `WorkflowPermission.replace_permissions` under the plugin is exactly what
  # that object exists to catch. Until this it caught it into a log line and a
  # diagnostics page nobody has to visit, which is most of the value thrown away.
  #
  # **A warning, never a refusal.** ADR-002 decided that, and Jan answered A
  # again on 2026-08-29 when a second review proposed blocking writes until an
  # administrator acknowledges the digest set: Redmine still boots and reads
  # still work, so an installation halfway through an upgrade is not a good
  # moment to lock its administrators out of the screens that would tell them
  # why. Reversing it is a change in this one method.
  #
  # **Nothing at all on a verified host**, which is the common case and the whole
  # reason this is bearable: a banner that is always there is furniture, and the
  # next real one is not read.
  #
  # The link only for an administrator. The diagnostics page requires one, and a
  # project manager who followed a link to a 403 would learn less than the
  # sentence already told them.
  def project_workflow_compatibility_banner
    state = RedmineProjectWorkflows::Compatibility.state
    return nil if state == :verified

    sentence = l(:"text_project_workflow_compatibility_banner_#{state}",
                 version: RedmineProjectWorkflows::Compatibility.host_minor)
    body = User.current.admin? ? safe_join([sentence, diagnostics_link], ' ') : sentence
    content_tag(:div, body, class: 'warning')
  end

  def diagnostics_link
    link_to(l(:label_project_workflow_diagnostics), project_workflow_diagnostics_path)
  end

  # The settings tab's rows: one per (tracker, role) this project can decide for,
  # with the state and the project's own rule count for each kind of rule.
  #
  # Built here rather than in a patched ProjectsController#settings, because the
  # plugin deliberately holds nothing inside that controller either -- see
  # Patches::ProjectsHelperPatch#apply! for what an alias chain does to a
  # prepended method. Redmine renders every settings tab's partial on every visit
  # to the page, so this runs whenever somebody who may see the tab opens
  # project settings; it is InventoryQuery over a single project, which is a fixed
  # number of collection queries whatever the number of trackers and roles, and
  # never one per row (G6) -- three for the two lists, and three or four for the
  # rows depending on whether the audit line names anybody.
  #
  # Memoised per project for the length of the render, so a second call costs
  # nothing and cannot answer for a different project than it was asked about.
  def project_workflow_settings_rows(project)
    @project_workflow_settings_rows ||= {}
    @project_workflow_settings_rows[project.id] ||= begin
      options = RedmineProjectWorkflows::Services::ProjectOptions
      # Built here and handed to both, so that .roles runs once per render rather
      # than once here and once per row's actions (G6).
      offered = options.roles(project)
      offered_role_ids(project, offered)
      query = RedmineProjectWorkflows::Services::InventoryQuery.new(
        projects: [project],
        trackers: options.trackers(project),
        # visible_roles: a role with no member in the project that already has a
        # scope here is a workflow the project runs, and leaving it off the tab
        # left it in force with no line explaining it and no way back (finding
        # F05). Whether such a row may be *offered* a new workflow is a separate
        # question -- see #project_workflow_role_offered?.
        roles: options.visible_roles(project, offered),
        rule_types: ProjectWorkflowScope::RULE_TYPES,
        deviations_only: false
      )
      # The whole list, not a page: it is one project's own trackers times the
      # roles somebody holds in it, and the tab is where you go to see all of
      # them at once. The administration inventory is the paged screen.
      query.rows(offset: 0, limit: query.total)
    end
  end

  # Whether this project may be offered a workflow of its own for this role, as
  # opposed to merely being shown one it already has. Decided by Jan on
  # 2026-08-26: only the roles with members in the project, so Non member and
  # Anonymous are not on the offer.
  #
  # Memoised per project for the length of the render, beside
  # #project_workflow_settings_rows and for the same reason (G6). That method
  # seeds the same memo with the list it has already built, so the tab pays for
  # this once however many rows it draws; asked on its own it answers with one
  # query of its own rather than depending on having been called second.
  def project_workflow_role_offered?(project, role)
    offered_role_ids(project).include?(role.id)
  end

  # The state of one (project, tracker, role, rule type), as text.
  #
  # Three states have to stay tellable apart (INV-3), and "own empty workflow"
  # is a deliberate configuration rather than a fault, so it is named. The words
  # carry the whole meaning; the class is a hook for a theme, and the plugin
  # ships no stylesheet of its own.
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

  # One side of a comparison line: every distinct rule the table holds for that
  # (status, field), named. Normally one; more than one only where the table
  # holds two rows that disagree, and then both are shown rather than one being
  # picked -- picking would make the page depend on the order the rows came back
  # in, and core does not pick either.
  #
  # Empty where that side says nothing about the field, which is the default and
  # needs no word of its own.
  def project_workflow_permission_labels(rules)
    safe_join(Array(rules).filter_map { |rule| project_workflow_permission_label([rule]) }, ', ')
  end

  # The link to the comparison, or nothing at all where there is nothing to
  # compare: a combination the project inherits has no own workflow, and the
  # page would say so rather than show a table (WP6).
  #
  # Built here so the settings tab, the matrix header and the administration
  # inventory cannot drift apart about when the link is offered.
  def project_workflow_compare_link(project, tracker, role, rule_type, state)
    return if state.to_sym == :inherits

    link_to(l(:label_project_workflow_compare),
            project_workflow_compare_path(project, tracker_id: tracker.id, role_id: role.id,
                                                   rule_type: rule_type),
            class: 'project-workflow-compare-link')
  end

  # One line of the comparison, labelled with the side it is on (WP6). Three
  # states, in words, with the class carrying nothing but colour -- the same rule
  # as the scope state above.
  def project_workflow_difference_tag(state)
    content_tag(:span, project_workflow_difference_label(state),
                class: "project-workflow-difference #{state}")
  end

  def project_workflow_difference_label(state)
    case state
    when :project_only then l(:label_project_workflow_compare_project_only)
    when :generic_only then l(:label_project_workflow_compare_generic_only)
    else l(:label_project_workflow_compare_changed)
    end
  end

  # Which of core's three transition grids a difference sits in. Not core's own
  # `label_additional_workflow_transitions_for_*`: those are the sentences above
  # a grid ("Additional transitions allowed when the user is the author") and read
  # as a heading rather than as a cell in a column of four.
  def project_workflow_condition_label(group)
    case group
    when 'author' then l(:label_project_workflow_condition_author)
    when 'assignee' then l(:label_project_workflow_condition_assignee)
    else l(:label_project_workflow_condition_always)
    end
  end

  # A status by name, with the two cases a name cannot come from: core's "new
  # issue" pseudo status, stored as old_status_id 0 and not an IssueStatus, and a
  # row naming a status that no longer exists -- which core's own delete does not
  # leave behind, but which the table allows and is better named by its id than
  # rendered as an empty cell.
  def project_workflow_status_label(status, status_id)
    return status.name if status
    return l(:label_issue_new) if status_id.to_i.zero?

    "##{status_id}"
  end

  # The row header of a field-permissions grid: a core field by its translated
  # name, or a custom field by its own. +custom_fields+ is keyed by id as a
  # string, because that is how the rule stores it.
  #
  # A field the tracker no longer has -- disabled, or a custom field since
  # removed -- is named by what the rule holds rather than dropped, because the
  # rule is still in the table and still a difference.
  def project_workflow_field_label(field_name, custom_fields)
    return custom_fields[field_name.to_s]&.name || "##{field_name}" if field_name.to_s.match?(/\A\d+\z/)

    l("field_#{field_name.to_s.delete_suffix('_id')}", default: field_name.to_s)
  end

  # Who last changed this combination's rules, and when (WP6).
  #
  # Core's own +authoring+ helper and its +label_updated_time_by+ key, so the
  # sentence reads the way "Updated by X 3 days ago" reads everywhere else in
  # Redmine and is already translated into every language core ships -- there is
  # no string of the plugin's own to translate here.
  #
  # Nothing is rendered where there is nothing to say: an inheriting combination
  # has no scope to carry a stamp, and a write with no logged-in user behind it
  # -- the WP1 backfill, a rake task, a console -- records a time but no author,
  # which would read as "Updated by Anonymous" and name somebody who was not
  # there.
  def project_workflow_audit_tag(cell)
    return if cell.updated_on.blank? || cell.updated_by.blank?

    content_tag(:span, authoring(cell.updated_on, cell.updated_by, label: :label_updated_time_by),
                class: 'project-workflow-scope-audit')
  end

  # The details under a cell of the settings tab and the inventory: who changed
  # this workflow and when, and the links that lead somewhere from it.
  #
  # **Two blocks, and a pipe between the links.** The audit line is a sentence
  # and the links are actions, and with nothing between them the browser renders
  #
  #     Updated by Maria Manager less than a minute ago Compare with the generic
  #     workflow Workflow diagram
  #
  # as one run of text, and the reader has to find the seams. The pipe is the one
  # `_scope_actions.html.erb` uses for its own pair and its comment argues for at
  # length; this is the same situation on the screen a project manager uses most,
  # and it did not have it (finding F01 of 2026-08-29-claude-browser, seen in a
  # browser rather than in a spec). The plugin ships no stylesheet, so the markup
  # has to do this.
  #
  # +links+ arrives already built, so this decides nothing about *which* links a
  # screen offers -- the inventory has one and the settings tab has two, and a
  # nil among them is a link that screen does not offer here.
  def project_workflow_cell_details(cell, links)
    audit = project_workflow_audit_tag(cell)
    joined = safe_join(Array(links).compact, ' | ')
    safe_join(
      [(content_tag(:div, audit, class: 'project-workflow-cell-details') if audit),
       (content_tag(:div, joined, class: 'project-workflow-cell-links') if joined.present?)].compact
    )
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

  private

  # The ids of the roles this project may be offered a workflow for. +offered+
  # seeds the memo from a list the caller already holds; without it the list is
  # fetched, so either caller works on its own.
  def offered_role_ids(project, offered = nil)
    @project_workflow_offered_role_ids ||= {}
    @project_workflow_offered_role_ids[project.id] = offered.to_set(&:id) if offered
    @project_workflow_offered_role_ids[project.id] ||=
      RedmineProjectWorkflows::Services::ProjectOptions.roles(project).to_set(&:id)
  end
end
