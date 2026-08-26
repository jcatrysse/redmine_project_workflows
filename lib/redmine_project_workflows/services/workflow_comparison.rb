# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # What a project's own workflow says that the generic one does not, and the
    # other way round, for one (project, tracker, role) and one rule type (WP6).
    #
    # A scope replaces (INV-5), so "which cells differ" is the only question a
    # project manager can ask about the relationship between the two: there is no
    # merge to explain and no precedence to work out. The answer is a list of
    # cells, each labelled with the side it is on.
    #
    # Both populations are read with an explicit project_id -- the project's id
    # and nil (INV-4) -- in two queries per rule type, whatever the size of the
    # matrix.
    class WorkflowComparison
      # The three grids core draws on the transitions screen. A stored row lands
      # in +author+ if its author flag is set, in +assignee+ if its assignee flag
      # is set, and in +always+ only if neither is -- so a row with both set is
      # in two grids, exactly as core's own matrix renders it. Comparing by grid
      # rather than by row therefore compares what the screen shows.
      GROUPS = %w[always author assignee].freeze

      # One line of a transitions comparison. +old_status+ is nil for core's
      # "new issue" pseudo status, which is stored as old_status_id 0 and is not
      # an IssueStatus -- and nil as well, with the id kept, for the one case the
      # tables allow but core's own delete does not leave behind: a row naming a
      # status that no longer exists. The ids ride along so the view can always
      # name the cell rather than rendering a blank one.
      TransitionDifference = Struct.new(:group, :old_status_id, :old_status, :new_status_id, :new_status,
                                        :state, keyword_init: true)

      # One line of a field-permissions comparison. Either rule is nil where that
      # side says nothing about the field, which is the default -- neither
      # read-only nor required.
      PermissionDifference = Struct.new(:status_id, :status, :field_name, :project_rule, :generic_rule,
                                        :state, keyword_init: true)

      # +differences+ is ordered for display and is empty when the two agree.
      Result = Struct.new(:rule_type, :differences, :project_rule_count, :generic_rule_count,
                          keyword_init: true) do
        def identical?
          differences.empty?
        end
      end

      def initialize(project_id:, tracker_id:, role_id:, rule_type:)
        @project_id = project_id.to_i
        @tracker_id = tracker_id.to_i
        @role_id = role_id.to_i
        @rule_type = rule_type.to_s
        return if ProjectWorkflowScope::RULE_TYPES.include?(@rule_type)

        raise ArgumentError, "unknown workflow scope rule type #{rule_type.inspect}"
      end

      def result
        if transitions?
          compare_transitions
        else
          compare_permissions
        end
      end

      private

      def transitions?
        @rule_type == ProjectWorkflowScope::TRANSITIONS
      end

      # --- transitions ---------------------------------------------------------

      def compare_transitions
        project = transition_groups(@project_id)
        generic = transition_groups(nil)
        statuses = statuses_for(transition_status_ids(project) | transition_status_ids(generic))

        differences = GROUPS.flat_map do |group|
          only(project[group], generic[group], :project_only, group, statuses) +
            only(generic[group], project[group], :generic_only, group, statuses)
        end

        Result.new(
          rule_type: @rule_type,
          differences: sort_transition_differences(differences),
          project_rule_count: transition_row_count(@project_id),
          generic_rule_count: transition_row_count(nil)
        )
      end

      def only(mine, theirs, state, group, statuses)
        (mine - theirs).map do |old_status_id, new_status_id|
          TransitionDifference.new(
            group: group,
            # 0 is core's "new issue" row, not a status; statuses never holds it.
            old_status_id: old_status_id, old_status: statuses[old_status_id],
            new_status_id: new_status_id, new_status: statuses[new_status_id],
            state: state
          )
        end
      end

      def transition_groups(project_id)
        groups = GROUPS.index_with { Set.new }
        transition_scope(project_id).pluck(:old_status_id, :new_status_id, :author, :assignee)
                                    .each do |old_status_id, new_status_id, author, assignee|
          pair = [old_status_id, new_status_id]
          groups['author'] << pair if author
          groups['assignee'] << pair if assignee
          groups['always'] << pair unless author || assignee
        end
        groups
      end

      def transition_row_count(project_id)
        transition_scope(project_id).count
      end

      def transition_scope(project_id)
        WorkflowTransition.where(project_id: project_id, tracker_id: @tracker_id, role_id: @role_id)
      end

      # Set#flatten flattens nested Sets, not the Arrays inside one, so the pairs
      # have to leave the Set before they are flattened.
      def transition_status_ids(groups)
        groups.each_value.reduce(Set.new) { |memo, pairs| memo | pairs.to_a.flatten }
      end

      # Deterministic on every database and every seed: the grid's own order --
      # "new issue" first, then by the statuses' positions -- and never the order
      # the rows happened to come back in.
      def sort_transition_differences(differences)
        differences.sort_by do |difference|
          [GROUPS.index(difference.group),
           position_of(difference.old_status), difference.old_status_id,
           position_of(difference.new_status), difference.new_status_id,
           difference.state == :project_only ? 0 : 1]
        end
      end

      # --- field permissions ---------------------------------------------------

      def compare_permissions
        project = permission_rules(@project_id)
        generic = permission_rules(nil)
        keys = project.keys | generic.keys
        statuses = statuses_for(keys.map(&:first))

        differences = keys.filter_map do |key|
          next if project[key] == generic[key]

          status_id, field_name = key
          PermissionDifference.new(
            status_id: status_id, status: statuses[status_id], field_name: field_name,
            project_rule: project[key], generic_rule: generic[key],
            state: permission_state(project[key], generic[key])
          )
        end

        Result.new(
          rule_type: @rule_type,
          differences: sort_permission_differences(differences),
          project_rule_count: project.size,
          generic_rule_count: generic.size
        )
      end

      def permission_state(project_rule, generic_rule)
        return :project_only if generic_rule.nil?
        return :generic_only if project_rule.nil?

        :changed
      end

      # Keyed by [status id, field name]. A key with two rows that disagree is a
      # contradiction for an administrator to settle rather than a difference to
      # show -- design.md and `rake
      # redmine_project_workflows:deduplicate_workflow_rules` cover it -- so the
      # last row wins here, as it does in the matrix cell.
      def permission_rules(project_id)
        WorkflowPermission.where(project_id: project_id, tracker_id: @tracker_id, role_id: @role_id)
                          .pluck(:old_status_id, :field_name, :rule)
                          .to_h { |status_id, field_name, rule| [[status_id, field_name], rule] }
      end

      def sort_permission_differences(differences)
        differences.sort_by do |difference|
          [position_of(difference.status), difference.status_id, difference.field_name.to_s]
        end
      end

      # --- shared --------------------------------------------------------------

      # One query for every status either side names, so the view asks for none.
      def statuses_for(status_ids)
        ids = status_ids.to_a.compact.reject(&:zero?)
        return {} if ids.empty?

        IssueStatus.where(id: ids).index_by(&:id)
      end

      # -1 sorts core's "new issue" row first, where the matrix puts it. A status
      # with no position -- which the column allows -- sorts after the ones that
      # have one rather than raising on a nil comparison.
      def position_of(status)
        return -1 if status.nil?

        status.position || Float::INFINITY
      end
    end
  end
end
