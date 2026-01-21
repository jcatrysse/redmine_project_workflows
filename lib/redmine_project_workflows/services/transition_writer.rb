# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    class TransitionWriter
      def self.replace_transitions(project, trackers, roles, transitions)
        replace_transitions_for_project_id(project.id, trackers, roles, transitions)
      end

      def self.replace_transitions_for_project_id(project_id, trackers, roles, transitions)
        trackers = Array.wrap(trackers)
        roles = Array.wrap(roles)

        WorkflowTransition.transaction do
          scope = WorkflowTransition.where(
            tracker_id: trackers.map(&:id),
            role_id: roles.map(&:id),
            project_id: project_id
          )
          delete_transitions_for_scope(scope, transitions)
          rows = build_transition_rows(project_id, trackers, roles, transitions)
          insert_transition_rows(rows)
        end
      end

      def self.build_transition_rows(project_id, trackers, roles, transitions)
        rows = []
        transitions.each do |old_status_id, transitions_by_new_status|
          old_status_id = old_status_id.to_i
          transitions_by_new_status.each do |new_status_id, transition_by_rule|
            new_status_id = new_status_id.to_i
            always_enabled = transition_enabled?(transition_by_rule['always'])
            author_enabled = transition_enabled?(transition_by_rule['author'])
            assignee_enabled = transition_enabled?(transition_by_rule['assignee'])

            trackers.each do |tracker|
              roles.each do |role|
                if always_enabled
                  rows << transition_row(old_status_id, new_status_id, tracker.id, role.id, project_id, false, false)
                end
                if author_enabled || assignee_enabled
                  rows << transition_row(old_status_id, new_status_id, tracker.id, role.id, project_id, author_enabled, assignee_enabled)
                end
              end
            end
          end
        end
        rows
      end

      def self.transition_row(old_status_id, new_status_id, tracker_id, role_id, project_id, author, assignee)
        {
          old_status_id: old_status_id,
          new_status_id: new_status_id,
          tracker_id: tracker_id,
          role_id: role_id,
          project_id: project_id,
          author: author,
          assignee: assignee,
          type: 'WorkflowTransition'
        }
      end

      def self.delete_transitions_for_scope(scope, transitions)
        table = WorkflowTransition.arel_table
        transition_hash =
          if transitions.respond_to?(:to_unsafe_h)
            transitions.to_unsafe_h
          else
            transitions.to_h
          end
        conditions = transition_hash.each_with_object([]) do |(old_status_id, transitions_by_new_status), memo|
          new_status_ids = transitions_by_new_status.keys.map(&:to_i)
          next if new_status_ids.empty?

          memo << table[:old_status_id].eq(old_status_id.to_i).and(table[:new_status_id].in(new_status_ids))
        end
        return if conditions.empty?

        predicate = conditions.reduce { |memo, condition| memo.or(condition) }
        scope.where(predicate).delete_all
      end

      def self.insert_transition_rows(rows)
        return if rows.empty?

        rows.each_slice(1000) do |slice|
          WorkflowTransition.insert_all(slice)
        end
      end

      def self.transition_enabled?(value)
        value == '1' || value == true
      end
    end
  end
end
