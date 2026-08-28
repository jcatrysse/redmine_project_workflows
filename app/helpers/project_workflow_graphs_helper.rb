# frozen_string_literal: true

# The workflow as a drawing (WP9): the words the layout could not know, and the
# link that opens the screen.
#
# A helper of its own rather than more of ProjectWorkflowsHelper, which is
# already near +Metrics/ModuleLength+ and is about the two matrices and the
# settings tab. Named explicitly by ProjectWorkflowsController, and included into
# ProjectWorkflowMapsHelper so that the issue form's panel can offer the link --
# Rails' include_all_helpers is built from the host application's helper paths
# and does not reach a plugin's app/helpers.
#
# Everything here that produces a colour produces none. The drawing is
# +currentColor+ throughout, and the two things it distinguishes -- a move anyone
# may make against one only the author or the assignee may, and a status inside
# the flow against one outside it -- are drawn as a solid line against a dashed
# one, with the legend saying so in words. A theme may recolour the page and the
# drawing follows it; nothing here needs a stylesheet the plugin does not ship.
module ProjectWorkflowGraphsHelper
  include RedmineProjectWorkflows::VersionHelper

  # The action the drawing lives on, for gating a link on the very thing the
  # target authorizes rather than on a permission name -- two permissions reach
  # this screen, and naming one of them would hide the link from holders of the
  # other. The same reasoning as ProjectWorkflowMapsHelper::TAB_ACTION.
  GRAPH_ACTION = { controller: 'project_workflows', action: 'graph' }.freeze

  # What to call each node, keyed by status id: the layout is a pure function
  # with no I18n behind it, so the words are passed in.
  def project_workflow_graph_labels(graph)
    graph.nodes.to_h do |node|
      [node.status_id, project_workflow_status_label(node.status, node.status_id)]
    end
  end

  def project_workflow_graph_layout(graph)
    RedmineProjectWorkflows::Services::WorkflowGraphLayout.new(
      graph, labels: project_workflow_graph_labels(graph)
    ).result
  end

  # One arrow, in a sentence: where it goes, what it requires, and which of the
  # selected roles grant it. This is the <title> a pointer shows, and it is the
  # only place the drawing itself says any of it -- the table below is the
  # readable twin, and it says all three in columns.
  def project_workflow_graph_edge_title(edge)
    parts = [
      "#{project_workflow_status_label(edge.old_status, edge.old_status_id)} → " \
      "#{project_workflow_status_label(edge.new_status, edge.new_status_id)}",
      project_workflow_map_conditions_label(edge.conditions)
    ]
    roles = Array(edge.roles).map(&:name).join(', ')
    parts << "#{l(:label_role_plural)}: #{roles}" if roles.present?
    parts.compact_blank.join(' — ')
  end

  # The baseline of each line of a node's label, so that one line sits on the
  # middle of the box and two straddle it.
  def project_workflow_graph_text_ys(placed)
    step = RedmineProjectWorkflows::Services::WorkflowGraphLayout::LINE_HEIGHT
    first = placed.center_y - (((placed.lines.size - 1) * step) / 2) + 4
    placed.lines.each_index.map { |index| first + (index * step) }
  end

  # What a screen reader is told before it reaches the table. Deliberately short:
  # no aria attribute makes a drawing legible, which is why the table below is
  # the readable twin rather than an afterthought, and a long label here would
  # only be read out ahead of the thing that actually answers.
  #
  # The count is interpolated as +statuses+ and not as +count+: +count+ makes
  # I18n look for one/other subkeys under the key, and a plain string then
  # answers "translation missing" in every language.
  def project_workflow_graph_aria_label(graph)
    l(:text_project_workflow_graph_aria, statuses: graph.nodes.size, transitions: graph.edges.size)
  end

  # The three diagnostics, each as [label, nodes], and only the ones that have
  # anything in them. Computed from the graph and the layout already in hand, so
  # they cost no query.
  def project_workflow_graph_diagnostics(graph, layout)
    unreachable = layout.band_nodes.map(&:node).select(&:mentioned)
    [
      [l(:label_project_workflow_graph_unreachable), unreachable],
      [l(:label_project_workflow_graph_dead_end), graph.dead_end_nodes],
      [l(:label_project_workflow_graph_unmentioned), graph.unmentioned_nodes]
    ].reject { |_label, nodes| nodes.empty? }
  end

  def project_workflow_graph_node_names(nodes)
    nodes.map { |node| project_workflow_status_label(node.status, node.status_id) }.join(', ')
  end

  # Back out of the drawing into the matrix that holds the rules for one role.
  #
  # Ungated, unlike the offers on the settings tab and the issue panel, and that
  # is not an oversight: both permissions that reach this screen also reach
  # +transitions+ (they are declared together in init.rb), so a reader who is
  # looking at this page can open that one. If those two lists ever diverge this
  # link needs the same +allowed_to?+ the others carry --
  # spec/plugin_conventions_spec.rb is what would notice.
  def project_workflow_graph_matrix_link(project, tracker, role)
    link_to(l(:label_project_workflow_open_matrix),
            project_workflow_matrix_path(project, tracker, role, ProjectWorkflowScope::TRANSITIONS))
  end

  # The link into the drawing, or nothing at all where it would answer 403.
  #
  # Gated on the action rather than on a permission name, for the reason
  # GRAPH_ACTION gives. +role+ is optional: from a settings-tab row it names the
  # role of that row, and from a screen that has no one role in mind it is left
  # off and the drawing picks the reader's own.
  def project_workflow_graph_link(project, tracker, role = nil, label: nil)
    return if project.nil? || tracker.nil?
    return unless User.current.allowed_to?(GRAPH_ACTION, project)

    options = { tracker_id: tracker.id }
    options[:role_id] = [role.id] if role
    link_to(label || l(:label_project_workflow_graph),
            project_workflow_graph_path(project, options),
            class: 'project-workflow-graph-link')
  end
end
