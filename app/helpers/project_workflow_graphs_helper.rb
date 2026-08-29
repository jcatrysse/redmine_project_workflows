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
  # Both counts count what the words say, which +layout.nodes.size+ and
  # +layout.edges.size+ did not (finding F03 of 2026-08-28, second run). The
  # entry node is core's +old_status_id = 0+ pseudo-status and not a status an
  # issue can sit in -- the drawing shows it as *New issue*, and the dead-end
  # diagnostic already excludes it for the same reason -- so a workflow of six
  # statuses was announced as seven. Core's fallback arrow is Redmine's own
  # behaviour rather than a transition anybody configured; the picture
  # distinguishes it with a dotted stroke and the table calls it *Redmine's own
  # fallback*, and this was the one place that counted it as an ordinary move.
  #
  # It is excluded from the count and given a clause of its own instead, so a
  # screen-reader user is told the same thing the dotted arrow tells a sighted
  # one rather than losing it. A separate key, not a third interpolation: the
  # sentence only exists on the workflows that have a fallback, and eight
  # locale files are easier to keep honest with two short strings than with one
  # that has to read well with a clause missing.
  #
  # The count is interpolated as +statuses+ and not as +count+: +count+ makes
  # I18n look for one/other subkeys under the key, and a plain string then
  # answers "translation missing" in every language.
  def project_workflow_graph_aria_label(layout)
    label = l(:text_project_workflow_graph_aria,
              statuses: layout.nodes.count { |placed| !placed.node.entry? },
              transitions: layout.edges.count { |routed| !routed.fallback })
    return label unless layout.edges.any?(&:fallback)

    "#{label} #{l(:text_project_workflow_graph_aria_fallback)}"
  end

  # The stroke pattern for one arrow, as an attribute or as nothing at all.
  # Built here rather than inline in the partial so that the only +html_safe+ in
  # the drawing stays a literal constant -- the document is assembled from
  # user-supplied status names, and a template that reaches for +html_safe+ per
  # branch is where that stops being obviously true.
  #
  # Dotted for core's fallback, dashed for a rule only the author or the assignee
  # may use, nothing for a move anyone holding the role may make.
  def project_workflow_graph_dash(routed)
    return 'stroke-dasharray="2 3"'.html_safe if routed.fallback
    return 'stroke-dasharray="5 3"'.html_safe if routed.conditional

    ''.html_safe
  end

  # The legend, as the sentences that are actually about something on the page.
  # A line explaining a dashed arrow above a drawing that has none is
  # instructions for a thing that is not there, and the third kind -- core's own
  # fallback (finding F01) -- has to be explained wherever it appears, including
  # on a workflow that holds no rule at all and therefore skips the diagnostics.
  def project_workflow_graph_legend(layout)
    [
      [layout.edges.any? { |routed| !routed.conditional && !routed.fallback },
       :text_project_workflow_graph_legend_solid],
      [layout.edges.any?(&:conditional), :text_project_workflow_graph_legend_dashed],
      [layout.edges.any?(&:fallback), :text_project_workflow_graph_legend_fallback],
      [!layout.band_top.nil?, :text_project_workflow_graph_legend_band]
    ].filter_map { |applies, key| l(key) if applies }
  end

  # The three diagnostics, each as [label, nodes], and only the ones that have
  # anything in them. Computed from the graph and the layout already in hand, so
  # they cost no query.
  #
  # A workflow with no transition at all reports none of them. Every status the
  # tracker uses is unmentioned there, and a list of thirty of them under "not
  # used by the selected roles" says nothing the one sentence above the drawing
  # has not already said, while burying it (decided autonomously, 2026-08-28;
  # reversible by deleting this guard).
  def project_workflow_graph_diagnostics(graph, layout)
    return [] if graph.empty_workflow?

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

  # Whether this reader may open the drawing for this project, asked once per
  # render rather than once per settings-tab row. No query either way -- the
  # roles are memoised on User -- but the tab draws one link per tracker and
  # role, and a permission check per cell is the shape that turns into one
  # later.
  def project_workflow_graph_offered?(project)
    # WP14: the switch first, because it is one hash lookup and it answers for
    # every project at once. An installation with the drawing turned off offers
    # no link to it anywhere -- the settings tab, the matrix header and the
    # issue-form panel all come through here -- and the action itself answers 404.
    return false unless RedmineProjectWorkflows::Services::GraphBudget.enabled?

    @project_workflow_graph_offered ||= {}
    return @project_workflow_graph_offered[project.id] if @project_workflow_graph_offered.key?(project.id)

    @project_workflow_graph_offered[project.id] = User.current.allowed_to?(GRAPH_ACTION, project)
  end

  # The link into the drawing, or nothing at all where it would answer 403.
  #
  # Gated on the action rather than on a permission name, for the reason
  # GRAPH_ACTION gives. +role+ is optional: from a settings-tab row it names the
  # role of that row, and from a screen that has no one role in mind it is left
  # off and the drawing picks the reader's own.
  def project_workflow_graph_link(project, tracker, role = nil, label: nil)
    return if project.nil? || tracker.nil?
    return unless project_workflow_graph_offered?(project)

    options = { tracker_id: tracker.id }
    options[:role_id] = [role.id] if role
    link_to(label || l(:label_project_workflow_graph),
            project_workflow_graph_path(project, options),
            class: 'project-workflow-graph-link')
  end
end
