# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    class TransitionWriter
      # The three columns of the transitions matrix.
      RULES = %w[always author assignee].freeze
      # What the matrix can submit for one cell: the checkbox and its paired
      # hidden field. 'no_change' is stripped by the controller; anything else
      # is not something the form can produce.
      VALUES = ['0', '1', true, false].freeze
      # Core stores transitions out of the "new issue" pseudo status as
      # old_status_id 0, which is not an IssueStatus.
      NEW_ISSUE_STATUS_ID = '0'

      def self.replace_transitions(project, trackers, roles, transitions)
        replace_transitions_for_project_id(project.id, trackers, roles, transitions)
      end

      def self.replace_transitions_for_project_id(project_id, trackers, roles, transitions)
        trackers = Array.wrap(trackers)
        roles = Array.wrap(roles)
        return if trackers.empty? || roles.empty?

        transitions = sanitize_transitions(transitions)
        return if transitions.empty?

        WorkflowTransition.transaction do
          # A project write records the decision along with the rules; a generic
          # write (project_id nil) has no scope to record. Existing scopes are
          # left alone, and none is ever removed here -- see ScopeWriter.
          if project_id
            ScopeWriter.ensure_scopes(
              project_ids: [project_id],
              tracker_ids: trackers.map(&:id),
              role_ids: roles.map(&:id),
              rule_type: ProjectWorkflowScope::TRANSITIONS
            )
          end

          scope = WorkflowTransition.where(
            tracker_id: trackers.map(&:id),
            role_id: roles.map(&:id),
            project_id: project_id
          )
          delete_transitions_for_scope(scope, transitions)
          rows = build_transition_rows(project_id, trackers, roles, transitions)
          insert_transition_rows(rows)
        end
        # The rules have changed, so anything cached from them is now wrong.
        # ScopeWriter resets when it creates a scope, but a save into a project
        # that already has one creates nothing.
        Resolver.reset_cache!
      end

      # INV-2: the rows are written with insert_all, which runs no validations,
      # so this whitelist *is* the validation. It restores core's
      # validates_presence_of :new_status, which the plugin's routing of
      # replace_transitions would otherwise have removed from the generic write
      # path as well, and rejects rule names and cell values the matrix cannot
      # produce.
      #
      # An entry that fails the whitelist is dropped before the delete, not
      # only before the insert, so an unacceptable value changes nothing rather
      # than removing the transition it names.
      def self.sanitize_transitions(transitions)
        status_ids = valid_status_ids

        to_hash(transitions).each_with_object({}) do |(old_status_id, by_new_status), sanitized|
          next unless by_new_status.respond_to?(:each)
          next unless old_status_id.to_s == NEW_ISSUE_STATUS_ID || status_ids.include?(old_status_id.to_s)

          row = sanitize_transition_row(by_new_status, status_ids)
          sanitized[old_status_id] = row unless row.empty?
        end
      end
      private_class_method :sanitize_transitions

      def self.sanitize_transition_row(by_new_status, status_ids)
        by_new_status.each_with_object({}) do |(new_status_id, transition_by_rule), row|
          next unless transition_by_rule.respond_to?(:each)
          next unless status_ids.include?(new_status_id.to_s)

          rules = transition_by_rule.select { |rule, value| permitted_cell?(rule, value) }
          row[new_status_id] = rules unless rules.empty?
        end
      end
      private_class_method :sanitize_transition_row

      def self.permitted_cell?(rule, value)
        RULES.include?(rule.to_s) && VALUES.include?(value)
      end
      private_class_method :permitted_cell?

      def self.valid_status_ids
        IssueStatus.pluck(:id).to_set(&:to_s)
      end
      private_class_method :valid_status_ids

      def self.to_hash(transitions)
        return {} if transitions.nil?

        if transitions.respond_to?(:to_unsafe_h)
          transitions.to_unsafe_h
        elsif transitions.respond_to?(:to_h)
          transitions.to_h
        else
          transitions
        end
      end
      private_class_method :to_hash

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
        conditions = transitions.each_with_object([]) do |(old_status_id, transitions_by_new_status), memo|
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
