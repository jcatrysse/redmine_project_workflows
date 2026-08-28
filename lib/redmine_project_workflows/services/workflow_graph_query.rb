# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # A project's whole transitions workflow for one tracker and a set of roles,
    # as a graph: the statuses as nodes, the stored transitions as edges, and --
    # per role -- which of the three states of INV-3 the project is in (WP9).
    #
    # This is the query behind the drawing on the project screen. WP8's
    # TransitionMapQuery answers "what may I do from here" for one issue; this
    # answers "what does this workflow look like" for a whole (tracker, roles)
    # combination, which is the question a workflow administrator asks and the
    # one an ex-Jira user misses the picture for.
    #
    # **A query object of its own, not a mode on TransitionMapQuery.** That class
    # reads the tracker, the status and the status list off one issue on purpose
    # -- its own initialize says why -- and there is no issue here. What the two
    # share is the population split, which is WorkflowPopulations and is shared.
    #
    # **Availability has no meaning here**, and that is the one thing this says
    # less than WP8's panel. There is no issue and no reader identity to judge an
    # edge against, so no edge carries whether it is offered right now; the
    # drawing says what the workflow permits. The panel is still the place to ask
    # about one issue, and it links here.
    #
    # Cost (G6), all of it behind a link so no other screen pays any of it: the
    # scope lookup the Resolver caches, one query for which of the overridden
    # roles hold a rule, one edge query, the cached effective status list for the
    # tracker, and one status query. None of them grows with the size of the
    # workflow, and nothing is per node or per edge.
    class WorkflowGraphQuery
      # Core's "new issue" pseudo-status, stored as old_status_id 0. It is not an
      # IssueStatus and never will be; it is where the status list on the
      # new-issue form reads from, and it is the entry point of the drawing.
      ENTRY_STATUS_ID = 0

      # One status in the drawing. +status+ is nil for the entry node and for a
      # row naming a status that no longer exists -- told apart by the id, never
      # by the record being absent.
      #
      # +mentioned+ is whether any rule for the selected roles names this status
      # at all. False only for a status the project's effective workflow for this
      # tracker uses under *some* role while these roles' rules say nothing about
      # it, which is the third diagnostic and is not visible from the edges.
      Node = Struct.new(:status_id, :status, :mentioned, keyword_init: true) do
        def entry?
          status_id.to_i == ENTRY_STATUS_ID
        end
      end

      # One transition, collapsed over the roles and the condition grids that
      # permit it: the reader wants the move once, with what it requires and
      # which of the selected roles grant it.
      Edge = Struct.new(:old_status_id, :old_status, :new_status_id, :new_status,
                        :conditions, :roles, keyword_init: true)

      # One selected role and the state of this project's transitions workflow
      # for it. Per role because resolution is per role (INV-5): one role can be
      # overridden while the next inherits, and the drawing is the union.
      RoleState = Struct.new(:role, :state, keyword_init: true)

      Result = Struct.new(:nodes, :edges, :role_states, keyword_init: true) do
        def entry_status_id
          ENTRY_STATUS_ID
        end

        # The one state to name in one sentence, or nil when the selected roles
        # disagree and each needs a line of its own. The same shape as WP8's,
        # deliberately, so the two screens say it the same way.
        def uniform_state
          states = role_states.map(&:state).uniq
          states.size == 1 ? states.first : nil
        end

        def roles
          role_states.map(&:role)
        end

        # Nothing at all to draw but the entry node: the selected roles run their
        # own workflow here and it is deliberately empty (INV-3). Distinct from
        # "no role takes part in a workflow", which is role_states being empty.
        def empty_workflow?
          edges.empty?
        end

        # A status with no way out. The entry node is never one -- it is not a
        # status an issue can sit in -- and neither is a status the rules do not
        # mention, which is its own diagnostic and would otherwise be reported
        # twice.
        def dead_end_nodes
          with_outgoing = edges.to_set(&:old_status_id)
          nodes.reject { |node| node.entry? || !node.mentioned || with_outgoing.include?(node.status_id) }
        end

        # A status this project's workflow for this tracker uses under some role,
        # that no rule for the selected roles mentions at all. Not a defect in the
        # workflow the way the other two are -- it is what "this role has nothing
        # to do with that status" looks like -- but it is the answer to "why is
        # that status not in the picture".
        def unmentioned_nodes
          nodes.reject(&:mentioned)
        end
      end

      # +role_ids+ is the selection, which the caller has already intersected
      # with the roles the project offers (INV-7); this asks no question about
      # who may look at it.
      def initialize(project:, tracker:, role_ids:)
        @project = project
        @tracker = tracker
        @role_ids = Array(role_ids).compact.map(&:to_i).uniq
      end

      def result
        role_states = build_role_states
        return empty_result if role_states.empty?

        rows = edge_rows(role_states.map { |role_state| role_state.role.id })
        statuses = statuses_for(rows)
        roles_by_id = role_states.index_by { |role_state| role_state.role.id }

        Result.new(
          nodes: build_nodes(rows, statuses),
          edges: build_edges(rows, statuses, roles_by_id),
          role_states: role_states
        )
      end

      private

      # No selected role takes part in a workflow at all, so the workflow permits
      # nothing and there is nothing to draw. The screen says so in words rather
      # than rendering a frame with one node in it.
      def empty_result
        Result.new(nodes: [], edges: [], role_states: [])
      end

      # --- which workflow, per role -------------------------------------------

      # The selected roles in Redmine's own order, each with the state of this
      # project's transitions workflow for it. Roles that take no part in a
      # workflow are dropped: they have no rules and never will, so a line for
      # one would say "inherits" about a workflow that does not apply to it.
      def build_role_states
        return [] if @tracker.nil? || @project.nil? || @role_ids.empty?

        roles = Role.sorted.where(id: @role_ids).select(&:consider_workflow?).sort
        return [] if roles.empty?

        scoped = scoped_role_ids
        with_rules = scoped.empty? ? [] : role_ids_with_own_rules(scoped)

        roles.map { |role| RoleState.new(role: role, state: state_for(role, scoped, with_rules)) }
      end

      # The three states of INV-3, told apart by the scope table and then by
      # whether that scope holds a rule -- never by the rules alone, which cannot
      # express a deliberately empty workflow.
      def state_for(role, scoped, with_rules)
        return :inherits if scoped.exclude?(role.id)
        return :own if with_rules.include?(role.id)

        :own_empty
      end

      # The cached point lookup every other reader of the scope table goes
      # through: one row lookup, never a walk up the project tree (INV-6).
      def scoped_role_ids
        Resolver.scoped_role_ids(
          project_id: @project.id, tracker_id: @tracker.id,
          rule_type: ProjectWorkflowScope::TRANSITIONS
        )
      end

      # Which of the overridden roles hold a rule of their own, so "own workflow"
      # and "own empty workflow" stay tellable apart (INV-3). Asked only of the
      # roles that have a scope at all, never of the generic rows: the project_id
      # predicate is explicit (INV-4).
      def role_ids_with_own_rules(scoped)
        WorkflowTransition.where(project_id: @project.id, tracker_id: @tracker.id, role_id: scoped)
                          .distinct.pluck(:role_id)
      end

      # --- the edges -----------------------------------------------------------

      # Every stored transition for the selected roles, in the two populations
      # they resolve to. Both relations name a project_id, nil included (INV-4);
      # WorkflowPopulations is the only place either is built.
      #
      # Self-transitions are excluded as they are everywhere else in the plugin:
      # a row from a status to itself is not a move, and drawn it is a loop that
      # says nothing.
      #
      # Ordered in SQL as well as sorted afterwards. The sort is what makes the
      # answer deterministic; the ORDER BY is what stops a database from
      # returning a different *row* for two rows that sort equal, which is the
      # shape of failure that shows up as one red cell out of nine.
      def edge_rows(role_ids)
        combined = WorkflowPopulations.combined(
          model: WorkflowTransition, project_id: @project.id, tracker_id: @tracker.id, role_ids: role_ids
        )
        return [] if combined.nil?

        combined
          .where('old_status_id <> new_status_id')
          .order(:old_status_id, :new_status_id, :role_id)
          .pluck(:old_status_id, :new_status_id, :author, :assignee, :role_id)
      end

      # One query for every status the rows name, plus every status this
      # project's effective workflow for this tracker uses under any role -- the
      # second half is what makes the "no rule for these roles mentions it"
      # diagnostic possible, and it is the cached list StatusListQuery already
      # keeps for the request (so a screen that has asked once pays nothing).
      #
      # 0 is core's "new issue" node and is not a status, so it is never asked
      # for.
      def statuses_for(rows)
        ids = (mentioned_status_ids(rows) + used_status_ids).uniq.reject(&:zero?)
        return {} if ids.empty?

        IssueStatus.where(id: ids).index_by(&:id)
      end

      def mentioned_status_ids(rows)
        rows.flat_map { |old_status_id, new_status_id, *| [old_status_id, new_status_id] }.uniq
      end

      # Asked of the project's effective workflow rather than of the tracker:
      # Tracker#issue_status_ids reads +workflows+ with no project_id predicate
      # at all, which is precisely what INV-4 forbids and what made the summary
      # page count wrong.
      def used_status_ids
        StatusListQuery.effective_status_ids(project: @project, tracker: @tracker)
      end

      # The nodes, in the order core's own matrix puts statuses in: the entry
      # node first, then by position, then by id. Deterministic on every database
      # and every seed -- the layout is a pure function of this order, so an
      # order that came out of a query would put the drawing at the mercy of the
      # planner.
      def build_nodes(rows, statuses)
        mentioned = mentioned_status_ids(rows).to_set
        ids = (mentioned + statuses.keys + [ENTRY_STATUS_ID]).to_a

        nodes = ids.map do |status_id|
          Node.new(status_id: status_id, status: statuses[status_id],
                   mentioned: node_mentioned?(status_id, mentioned))
        end
        nodes.sort_by { |node| [position_of(node.status, node.status_id), node.status_id] }
      end

      # The entry node is always "mentioned": it is not a status the rules can
      # fail to name, it is where every workflow starts, and reporting it as
      # unmentioned would put core's own pseudo-status in a diagnostic list.
      def node_mentioned?(status_id, mentioned)
        status_id == ENTRY_STATUS_ID || mentioned.include?(status_id)
      end

      # Rows collapsed into one edge per (from, to), because several roles and
      # several condition grids can permit the same move and the drawing wants
      # one arrow.
      def build_edges(rows, statuses, roles_by_id)
        grouped = {}
        rows.each do |old_status_id, new_status_id, author, assignee, role_id|
          entry = (grouped[[old_status_id, new_status_id]] ||= { conditions: Set.new, role_ids: Set.new })
          entry[:conditions] << condition_for(author, assignee)
          entry[:role_ids] << role_id
        end

        edges = grouped.map { |pair, entry| build_edge(pair, entry, statuses, roles_by_id) }
        sort_edges(edges)
      end

      def build_edge(pair, entry, statuses, roles_by_id)
        old_status_id, new_status_id = pair
        Edge.new(
          old_status_id: old_status_id, old_status: statuses[old_status_id],
          new_status_id: new_status_id, new_status: statuses[new_status_id],
          conditions: collapse_conditions(entry[:conditions]),
          roles: entry[:role_ids].filter_map { |role_id| roles_by_id[role_id]&.role }.sort
        )
      end

      # Which of core's three grids a stored row belongs to. A row with both
      # flags set is in two of them, and is recorded as both.
      def condition_for(author, assignee)
        return 'author' if author && !assignee
        return 'assignee' if assignee && !author
        return 'both' if author && assignee

        'always'
      end

      # 'both' is a single row carrying both flags; it stands for the author and
      # the assignee variants at once. A move anyone with the role may make
      # subsumes either of them, so 'always' is never listed beside another.
      def collapse_conditions(conditions)
        expanded = conditions.flat_map { |condition| condition == 'both' ? %w[author assignee] : [condition] }.uniq
        return ['always'] if expanded.include?('always')

        TransitionMapQuery::CONDITIONS.select { |condition| expanded.include?(condition) }
      end

      # Deterministic on every database and every seed: by where the two ends sit
      # in core's own status order, never the order the rows came back in.
      def sort_edges(edges)
        edges.sort_by do |edge|
          [position_of(edge.old_status, edge.old_status_id), edge.old_status_id,
           position_of(edge.new_status, edge.new_status_id), edge.new_status_id]
        end
      end

      # -1 sorts core's "new issue" node first, where the matrix puts it -- and it
      # is told from the other nil by its **id**, not by being nil. Both are nil
      # records: id 0 is that node, and any other id is a row naming a status that
      # no longer exists, which belongs at the end rather than ahead of every real
      # status. A status whose position is null -- which the column allows --
      # sorts after the ones that have one rather than raising on a nil
      # comparison.
      def position_of(status, status_id)
        return -1 if status.nil? && status_id.to_i.zero?
        return Float::INFINITY if status.nil?

        status.position || Float::INFINITY
      end
    end
  end
end
