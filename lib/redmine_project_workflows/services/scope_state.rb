# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Which of the three states of INV-3 the current selection is in.
    #
    # A selection on the administration screens is a set of projects times a set
    # of trackers times a set of roles, so the answer is three counts rather
    # than one state. They always add up to #total.
    #
    #   inheriting   no scope             -- the generic workflow applies
    #   own          scope, with rules    -- only the project's rules apply
    #   own_empty    scope, without rules -- nothing applies
    #
    # "Own empty" is a deliberate, valid configuration and not an error, so
    # everything that renders it says so in words (ADR-001, consequences).
    class ScopeState
      attr_reader :project_ids, :tracker_ids, :role_ids, :rule_type

      def initialize(project_ids:, tracker_ids:, role_ids:, rule_type:)
        @project_ids = ids_for(project_ids)
        @tracker_ids = ids_for(tracker_ids)
        @role_ids = ids_for(role_ids)
        @rule_type = rule_type
      end

      def total
        @project_ids.size * @tracker_ids.size * @role_ids.size
      end

      def any?
        total.positive?
      end

      def own
        @own ||= (scoped_combinations & combinations_with_rules).size
      end

      def own_empty
        scoped_combinations.size - own
      end

      def inheriting
        total - scoped_combinations.size
      end

      # The single state to show when the selection is uniform, or :mixed when
      # it is not. Callers use it to pick one sentence instead of three counts.
      def state
        return :none unless any?
        return :inherits if inheriting == total
        return :own if own == total
        return :own_empty if own_empty == total

        :mixed
      end

      # Whether an action would do anything, so that a button that cannot
      # change anything is not offered.
      def enable_possible?
        inheriting.positive?
      end

      def scoped?
        scoped_combinations.any?
      end

      private

      def ids_for(objects)
        Array(objects).compact.map { |object| object.respond_to?(:id) ? object.id : object.to_i }.uniq
      end

      def scoped_combinations
        @scoped_combinations ||=
          if any?
            ProjectWorkflowScope.where(
              project_id: @project_ids, tracker_id: @tracker_ids,
              role_id: @role_ids, rule_type: @rule_type
            ).pluck(:project_id, :tracker_id, :role_id).to_set
          else
            Set.new
          end
      end

      # INV-4: the query names its project ids, so a generic row can never be
      # counted here -- which is the mistake the summary page makes today.
      def combinations_with_rules
        @combinations_with_rules ||=
          if any?
            ProjectWorkflowScope.rule_model_for(@rule_type).where(
              project_id: @project_ids, tracker_id: @tracker_ids, role_id: @role_ids
            ).distinct.pluck(:project_id, :tracker_id, :role_id).to_set
          else
            Set.new
          end
      end
    end
  end
end
