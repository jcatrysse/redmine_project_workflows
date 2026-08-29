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
      #
      # **Every project that had a scope on the source pair gets one, including
      # the projects that do not have the new tracker enabled** -- and that is
      # deliberate, against the narrowing ProjectWorkflowCopier does for a
      # project copy (audit F11, settled in docs/DECISIONS.md on 2026-08-29).
      # The rules themselves are copied for every project whatever this method
      # does: WorkflowRule.copy_one_with_projects carries project_id through the
      # select list, and INV-4 exempts that method by name (CLAUDE.md; the
      # marker comment itself lives there, and spec/plugin_conventions_spec.rb
      # asserts it lives in exactly one file). Narrowing the
      # scopes alone would therefore leave project rule rows with no scope over
      # them -- rows the resolver ignores and nothing ever cleans up -- and
      # narrowing the rules to match would mean rewriting the one statement that
      # keeps copying a role from being 500 round trips per tracker. The
      # narrowing ProjectWorkflowCopier does is a different question with a
      # different answer: there the target project's tracker list is what the
      # copy is *about*.
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
        # Built in Ruby rather than asked of the database (finding F09).
        # CURRENT_TIMESTAMP is UTC only on PostgreSQL: its adapter sets the
        # session timezone to UTC when default_timezone is :utc, and
        # AbstractMysqlAdapter#configure_connection sets sql_auto_is_null,
        # wait_timeout and sql_mode and *no* time_zone -- in Rails 6.1, 7.2 and
        # 8.0 alike. mysql2's query_options[:database_timezone] decides how
        # returned values are tagged, not what the server computes. So on MySQL
        # and MariaDB -- six of the nine supported cells -- the server returned
        # its own local time and Rails read it back as if it were UTC.
        #
        # The literal is plain -- not the standard `TIMESTAMP '...'` type keyword,
        # which SQLite does not have and where it fails with `no such column:
        # TIMESTAMP` (finding F02 of 2026-08-28-claude-audit). Every supported
        # adapter coerces a bare literal in the select list of an INSERT ...
        # SELECT against the target column.
        #
        # **The narrow rule that goes with it:** never put an untyped literal in
        # the select list of a DISTINCT, a UNION or a GROUP BY. PostgreSQL has to
        # type the column to compare it, resolves `unknown` to `text`, and the
        # INSERT then fails with `PG::DatatypeMismatch`. This SELECT is plain, and
        # it has to stay plain -- migration 004 moved its DISTINCT into a subquery
        # for exactly this, and `spec/plugin_conventions_spec.rb` greps for it.
        now = connection.quote(connection.quoted_date(Time.now.utc))

        "INSERT INTO #{table} " \
          '(project_id, tracker_id, role_id, rule_type, ' \
          'created_by_id, updated_by_id, created_at, updated_at) ' \
          "SELECT source.project_id, #{target_tracker}, #{target_role}, #{quoted_type}, " \
          "#{author_value}, #{author_value}, #{now}, #{now} " \
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
