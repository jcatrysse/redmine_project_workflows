# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # The workflow governing one issue, as a local map: the statuses it may move
    # to from where it is, the statuses that can lead into it, and -- per role --
    # which of the three states of INV-3 the project is in (WP8).
    #
    # This is the query behind the panel on the issue form. It answers for one
    # (project, tracker, status) and for the roles the reader holds, which is
    # exactly the population Redmine's own status dropdown is built from.
    #
    # **It must not contradict that dropdown.** The dropdown is
    # Issue#new_statuses_allowed_to, which reads the workflow *and then* drops
    # closed statuses for an issue that cannot be closed, open ones for one that
    # cannot be reopened, and the author and assignee variants for a reader who
    # is neither. A map drawn from the rules alone therefore shows edges the
    # dropdown withholds. Rather than hide them -- which would leave "why can I
    # not close this issue" unanswerable, the question the panel exists for --
    # every edge carries whether it is available now, and the withheld ones
    # carry the reason: core's own Issue#transition_warning sentence where core
    # has one, and the plugin's where the reason is the reader's identity.
    #
    # Cost, all of it behind a link so an ordinary issue edit pays none of it
    # (G6): the scope lookup the Resolver caches, one query for whether the
    # project holds any rule of its own, one for the edges around this status,
    # and one for the statuses they name. None of them grows with the size of
    # the workflow.
    class TransitionMapQuery
      # The three grids core draws on the transitions screen, and the order they
      # are named in. A stored row with both flags set is in two of them, which
      # is how core's own matrix renders it -- see WorkflowComparison::GROUPS.
      CONDITIONS = %w[always author assignee].freeze

      # One transition. +conditions+ is the subset of CONDITIONS the stored rows
      # put it in, collapsed: a row anyone with the role may take subsumes the
      # author and assignee variants of the same pair, so 'always' is alone
      # whenever it is present.
      #
      # +roles+ is which of the reader's own roles grant it, so a reader holding
      # two roles can see which one an edge comes from. +available+ and +reason+
      # are the honesty clause above: nil reason on an available edge.
      #
      # The status ids ride along beside the records because a row may name a
      # status that no longer exists, and because core's "new issue" node is
      # stored as old_status_id 0 and is not an IssueStatus at all.
      Edge = Struct.new(:old_status_id, :old_status, :new_status_id, :new_status,
                        :conditions, :roles, :available, :reason, keyword_init: true)

      # One of the reader's roles and the state of this project's workflow for
      # it. Per role because resolution is per role (INV-5): one role can be
      # overridden while the next inherits, and what the reader sees is the
      # union.
      RoleState = Struct.new(:role, :state, keyword_init: true)

      Result = Struct.new(:status, :status_id, :outgoing, :incoming, :role_states,
                          keyword_init: true) do
        # The one state to name in one sentence, or nil when the roles disagree
        # and each needs a line of its own.
        def uniform_state
          states = role_states.map(&:state).uniq
          states.size == 1 ? states.first : nil
        end

        def roles
          role_states.map(&:role)
        end

        # No role that takes part in a workflow at all: the reader sees no status
        # choice either, and there is nothing to describe.
        def any_roles?
          role_states.any?
        end
      end

      # +issue+ is the issue as the form has it -- saved or not. +tracker+
      # defaults to its own; the caller passes the form's when the reader has
      # changed it, having matched it against the project's trackers first
      # (INV-7).
      def initialize(issue:, user:, tracker: nil)
        @issue = issue
        @user = user
        @tracker = tracker || issue.tracker
      end

      def result
        role_states = build_role_states
        return empty_result if role_states.empty?

        rows = edge_rows(role_states.map(&:role))
        statuses = statuses_for(rows)
        roles_by_id = role_states.index_by { |role_state| role_state.role.id }

        Result.new(
          status: from_status,
          status_id: from_status_id,
          outgoing: build_edges(rows, :outgoing, statuses, roles_by_id),
          incoming: build_edges(rows, :incoming, statuses, roles_by_id),
          role_states: role_states
        )
      end

      private

      # No role that takes part in a workflow at all, so the workflow permits the
      # reader nothing and there is nothing to draw. The panel says so in words
      # rather than rendering two empty tables.
      def empty_result
        Result.new(status: from_status, status_id: from_status_id,
                   outgoing: [], incoming: [], role_states: [])
      end

      # The node the map is drawn from. An unsaved issue starts at core's "new
      # issue" pseudo-status, which is stored as old_status_id 0 and is where the
      # dropdown on the new-issue form reads from too.
      #
      # For a saved issue it is the issue's own status *after* the form's tracker
      # has been applied, which is the same reconciliation
      # Issue#new_statuses_allowed_to performs to pick its initial status: keep
      # the status if the new tracker's workflow uses it, otherwise the new
      # tracker's default. Patches::IssuePatch#tracker= is the other half of it,
      # so the two cannot drift.
      def from_status
        @issue.new_record? ? nil : @issue.status
      end

      def from_status_id
        from_status&.id || 0
      end

      # --- which workflow, per role -------------------------------------------

      # The reader's roles, in Redmine's own order, each with the state of this
      # project's transitions workflow for it.
      #
      # roles_for_workflow is core's own private method and is what the dropdown
      # uses, so the panel names exactly the roles the dropdown was built from --
      # including the administrator case, where core hands back every role in the
      # installation.
      def build_role_states
        roles = @issue.send(:roles_for_workflow, @user).sort
        return [] if roles.empty? || @tracker.nil? || @issue.project_id.blank?

        scoped = scoped_role_ids
        with_rules = scoped.empty? ? [] : role_ids_with_own_rules(scoped)

        roles.map do |role|
          RoleState.new(role: role, state: state_for(role, scoped, with_rules))
        end
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
      # through (INV-6): one row lookup, never a walk up the project tree.
      def scoped_role_ids
        Resolver.scoped_role_ids(
          project_id: @issue.project_id, tracker_id: @tracker.id,
          rule_type: ProjectWorkflowScope::TRANSITIONS
        )
      end

      # Which of the overridden roles hold a rule of their own, so that "own
      # workflow" and "own empty workflow" stay tellable apart (INV-3). Asked
      # only of the roles that have a scope at all, and never of the generic
      # rows: the project_id predicate is explicit (INV-4).
      def role_ids_with_own_rules(scoped)
        WorkflowTransition.where(project_id: @issue.project_id, tracker_id: @tracker.id,
                                 role_id: scoped)
                          .distinct.pluck(:role_id)
      end

      # --- the edges -----------------------------------------------------------

      # Every stored row touching this status, in the two populations the reader's
      # roles resolve to: the project's own rows for the roles it answers for,
      # the generic rows for the rest. Both predicates name a project_id, nil
      # included (INV-4).
      #
      # One query for both directions -- the same rows answer "where can this go"
      # and "what leads here" -- and the OR over the two populations is built
      # before anything narrows it, because .or refuses a relation that has
      # already been distinct'ed or ordered.
      def edge_rows(roles)
        scopes = population_scopes(roles.map(&:id))
        return [] if scopes.empty?

        combined = scopes.shift
        scopes.each { |scope| combined = combined.or(scope) }
        # A row from a status to itself is not a move, and core puts the current
        # status back into the status list itself, so it would only pad the table.
        combined
          .where('old_status_id <> new_status_id')
          .where('old_status_id = :status_id OR new_status_id = :status_id', status_id: from_status_id)
          .pluck(:old_status_id, :new_status_id, :author, :assignee, :role_id)
      end

      # One relation per population the reader's roles resolve to: the project's
      # own rows for the roles it answers for, the generic rows for the rest. Both
      # name a project_id, nil included (INV-4).
      def population_scopes(role_ids)
        resolver = Resolver.new(project_id: @issue.project_id, tracker_id: @tracker.id,
                                role_ids: role_ids)
        own_role_ids = resolver.overridden_role_ids_for(WorkflowTransition)
        generic_role_ids = role_ids - own_role_ids

        base = WorkflowTransition.where(tracker_id: @tracker.id)
        scopes = []
        scopes << base.where(project_id: @issue.project_id, role_id: own_role_ids) if own_role_ids.any?
        scopes << base.where(project_id: nil, role_id: generic_role_ids) if generic_role_ids.any?
        scopes
      end

      # One query for every status the rows name. 0 is core's "new issue" node
      # and is not a status, so it is never asked for.
      def statuses_for(rows)
        ids = rows.flat_map { |old_status_id, new_status_id, *| [old_status_id, new_status_id] }
                  .uniq.reject(&:zero?)
        return {} if ids.empty?

        IssueStatus.where(id: ids).index_by(&:id)
      end

      # Rows collapsed into one edge per (from, to), because several roles and
      # several conditions can permit the same move and the reader wants the
      # move once.
      def build_edges(rows, direction, statuses, roles_by_id)
        grouped = {}
        rows.each do |old_status_id, new_status_id, author, assignee, role_id|
          next unless in_direction?(direction, old_status_id, new_status_id)

          entry = (grouped[[old_status_id, new_status_id]] ||= { conditions: Set.new, role_ids: Set.new })
          entry[:conditions] << condition_for(author, assignee)
          entry[:role_ids] << role_id
        end

        edges = grouped.map do |pair, entry|
          build_edge(pair, entry, statuses, roles_by_id, direction)
        end
        sort_edges(edges, direction)
      end

      def in_direction?(direction, old_status_id, new_status_id)
        direction == :outgoing ? old_status_id == from_status_id : new_status_id == from_status_id
      end

      # Which of core's three grids a stored row belongs to. A row with both
      # flags set is in two of them, and is recorded as both.
      def condition_for(author, assignee)
        return 'author' if author && !assignee
        return 'assignee' if assignee && !author
        return 'both' if author && assignee

        'always'
      end

      # An incoming edge is history rather than an action -- it ends at the status
      # the issue is already in -- so it carries no availability. Asking would
      # answer "yes" for every one of them, because the dropdown always offers
      # the current status back.
      def build_edge(pair, entry, statuses, roles_by_id, direction)
        old_status_id, new_status_id = pair
        conditions = collapse_conditions(entry[:conditions])
        roles = entry[:role_ids].filter_map { |role_id| roles_by_id[role_id]&.role }.sort
        available, reason =
          if direction == :outgoing
            availability(new_status_id, statuses[new_status_id], conditions)
          else
            [nil, nil]
          end

        Edge.new(
          old_status_id: old_status_id, old_status: statuses[old_status_id],
          new_status_id: new_status_id, new_status: statuses[new_status_id],
          conditions: conditions, roles: roles,
          available: available, reason: reason
        )
      end

      # 'both' is a single row carrying both flags; it stands for the author and
      # the assignee variants at once. A move anyone with the role may make
      # subsumes either of them, so 'always' is never listed beside another.
      def collapse_conditions(conditions)
        expanded = conditions.flat_map { |condition| condition == 'both' ? %w[author assignee] : [condition] }.uniq
        return ['always'] if expanded.include?('always')

        CONDITIONS.select { |condition| expanded.include?(condition) }
      end

      # --- the honesty clause --------------------------------------------------

      # Whether the dropdown offers this move now, and if not, why not.
      #
      # The order matters: the reader's identity comes first, because an edge
      # that only the author may take is withheld from everybody else whatever
      # the state of the issue's subtasks. Then core's own two reasons, in core's
      # own words, so the sentence beside the map is the sentence beside the
      # warning icon on the same form.
      def availability(new_status_id, new_status, conditions)
        return [true, nil] if offered_status_ids.include?(new_status_id)
        return [false, identity_reason(conditions)] unless conditions_met?(conditions)

        reason =
          if new_status.nil? then nil
          elsif new_status.is_closed? then closable_warning
          else reopenable_warning
          end
        [false, reason || I18n.t(:text_project_workflow_map_unavailable)]
      end

      # Exactly the dropdown's population, asked of the same object the form
      # rendered -- not recomputed from the rules, which is the whole point.
      def offered_status_ids
        @offered_status_ids ||= @issue.new_statuses_allowed_to(@user).to_set(&:id)
      end

      def conditions_met?(conditions)
        return true if conditions.include?('always')
        return true if conditions.include?('author') && author?
        return true if conditions.include?('assignee') && assignee?

        false
      end

      def identity_reason(conditions)
        author = conditions.include?('author')
        assignee = conditions.include?('assignee')
        key =
          if author && assignee then :text_project_workflow_map_requires_author_or_assignee
          elsif author then :text_project_workflow_map_requires_author
          else :text_project_workflow_map_requires_assignee
          end
        I18n.t(key)
      end

      def author?
        @issue.author == @user
      end

      # The same test core makes: the group case included, because an issue
      # assigned to a group is assigned to its members for this purpose.
      def assignee?
        assigned_to_id = @issue.assigned_to_id
        return false if assigned_to_id.blank?

        @user.id == assigned_to_id || @user.group_ids.include?(assigned_to_id)
      end

      # Core populates Issue#transition_warning as a side effect of answering,
      # and the second call overwrites the first, so each answer is captured as
      # it is given.
      def closable_warning
        return @closable_warning if defined?(@closable_warning)

        @closable_warning = @issue.closable? ? nil : @issue.transition_warning
      end

      def reopenable_warning
        return @reopenable_warning if defined?(@reopenable_warning)

        @reopenable_warning = @issue.reopenable? ? nil : @issue.transition_warning
      end

      # Deterministic on every database and every seed: the order core's own
      # matrix uses -- the "new issue" node first, then by position -- and never
      # the order the rows came back in.
      def sort_edges(edges, direction)
        edges.sort_by do |edge|
          status = direction == :outgoing ? edge.new_status : edge.old_status
          status_id = direction == :outgoing ? edge.new_status_id : edge.old_status_id
          [position_of(status), status_id]
        end
      end

      # -1 sorts core's "new issue" node first. A status whose position is null
      # -- which the column allows -- sorts after the ones that have one rather
      # than raising on a nil comparison.
      def position_of(status)
        return -1 if status.nil?

        status.position || Float::INFINITY
      end
    end
  end
end
