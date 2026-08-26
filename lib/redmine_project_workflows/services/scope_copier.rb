# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Duplicating a role or a tracker duplicates the decisions along with the
    # rules. Split out of ScopeWriter, which holds the three actions of INV-3;
    # between them they are the only places that create or remove a scope.
    class ScopeCopier
      # Duplicating a role or a tracker duplicates the decisions along with the
      # rules (claude F03). Called from WorkflowRule.copy_one_with_projects,
      # which has just copied the rows.
      #
      # The source is mirrored exactly, a scope with no rules included: that is
      # an own *empty* workflow, and leaving it out would silently return the
      # copy to inheritance (INV-3). Combinations the target already has are
      # left alone, audit columns and all -- core only ever calls this on a role
      # or tracker it has just created, so there is nothing there to disturb,
      # and repeating it is a no-op rather than a fresh decision.
      def self.copy_scopes(source_tracker_id:, source_role_id:, target_tracker_id:, target_role_id:, user: User.current)
        source_tracker_id = Integer(source_tracker_id)
        source_role_id = Integer(source_role_id)
        target_tracker_id = Integer(target_tracker_id)
        target_role_id = Integer(target_role_id)

        copied = ProjectWorkflowScope::RULE_TYPES.sum do |rule_type|
          insert_copied_scopes(
            source_tracker_id: source_tracker_id, source_role_id: source_role_id,
            target_tracker_id: target_tracker_id, target_role_id: target_role_id,
            rule_type: rule_type, user: user
          )
        end
        Resolver.reset_cache! if copied.positive?
        copied
      end

      # One INSERT ... SELECT per rule type rather than one create! per project.
      # A role copied in an installation with 500 overriding projects was 1000
      # round trips inside one transaction; it is now two.
      #
      # Written as raw SQL, like WorkflowRule.copy_generic_to_project and for
      # the same reason: every column value is either a column of a row already
      # in the table or an integer id resolved from the database, so no request
      # parameter can reach one and there is nothing for a validation to check
      # that the table's own NOT NULL and unique constraints do not (INV-2).
      # NOT EXISTS keeps it idempotent, which is what the unique index would
      # otherwise refuse.
      def self.insert_copied_scopes(source_tracker_id:, source_role_id:, target_tracker_id:, target_role_id:,
                                    rule_type:, user:)
        unless ProjectWorkflowScope::RULE_TYPES.include?(rule_type)
          raise ArgumentError, "unknown rule type #{rule_type.inspect}"
        end

        target = ProjectWorkflowScope.where(
          tracker_id: target_tracker_id, role_id: target_role_id, rule_type: rule_type
        )
        before = target.count
        # rubocop:disable Rails/SkipsModelValidations -- see the comment above:
        # every value is a column of an existing row or an id resolved from the
        # database, and the constraints the model would check are on the table.
        ProjectWorkflowScope.connection.insert(
          copy_scopes_sql(
            source_tracker_id: source_tracker_id, source_role_id: source_role_id,
            target_tracker_id: target_tracker_id, target_role_id: target_role_id,
            rule_type: rule_type, user: user
          )
        )
        # rubocop:enable Rails/SkipsModelValidations
        target.count - before
      end
      private_class_method :insert_copied_scopes

      def self.copy_scopes_sql(source_tracker_id:, source_role_id:, target_tracker_id:, target_role_id:,
                               rule_type:, user:)
        connection = ProjectWorkflowScope.connection
        table = ProjectWorkflowScope.table_name
        author = ProjectWorkflowScope.author_id_for(user)
        author_value = author ? connection.quote(author) : 'NULL'
        quoted_type = connection.quote(rule_type)
        target_tracker = connection.quote(target_tracker_id)
        target_role = connection.quote(target_role_id)

        "INSERT INTO #{table} " \
          '(project_id, tracker_id, role_id, rule_type, ' \
          'created_by_id, updated_by_id, created_at, updated_at) ' \
          "SELECT source.project_id, #{target_tracker}, #{target_role}, #{quoted_type}, " \
          "#{author_value}, #{author_value}, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP " \
          "FROM #{table} source " \
          "WHERE source.tracker_id = #{connection.quote(source_tracker_id)} " \
          "AND source.role_id = #{connection.quote(source_role_id)} " \
          "AND source.rule_type = #{quoted_type} " \
          "AND NOT EXISTS (SELECT 1 FROM #{table} existing " \
          'WHERE existing.project_id = source.project_id ' \
          "AND existing.tracker_id = #{target_tracker} " \
          "AND existing.role_id = #{target_role} " \
          "AND existing.rule_type = #{quoted_type})"
      end
      private_class_method :copy_scopes_sql
    end
  end
end
