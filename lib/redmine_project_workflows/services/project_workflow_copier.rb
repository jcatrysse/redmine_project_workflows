# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Copying a project copies its workflow (finding F01 of 2026-08-28, second
    # run).
    #
    # Redmine's *Copy project* duplicates members, trackers, categories, issues,
    # versions, queries and the enabled modules -- everything that makes the
    # copy a working restatement of the original. Before this it did not
    # duplicate the project's own workflow, so a project given a deliberately
    # narrow workflow arrived, copied, running the *generic* one: more
    # permissive than the original, with no message and nothing in the
    # documentation to warn anybody. The direction of that surprise is the wrong
    # way round, which is why copying rather than merely documenting was chosen
    # (docs/DECISIONS.md, 2026-08-28).
    #
    # The precedent is ScopeCopier: duplicating a role or a tracker already
    # duplicates the decisions along with the rules, for the same reason.
    #
    # **Scopes first, rules second, and the rules only where a scope exists.**
    # A scope with no rules is an own *empty* workflow and has to survive the
    # copy as one (INV-3); a rule row with no scope is invisible to the resolver
    # and copying it would carry rubbish across. Nothing here merges with the
    # generic workflow (INV-5) and nothing walks the project tree: a subproject
    # copied along with its parent is copied in its own right, by its own call
    # to Project#copy (INV-6).
    class ProjectWorkflowCopier
      # The value of the checkbox this item gets in Redmine's *Copy project*
      # form, and therefore the string Project#copy looks for in +options[:only]+.
      #
      # Not one of core's own eight (`members`, `wiki`, `versions`,
      # `issue_categories`, `issues`, `queries`, `boards`, `documents`): core
      # intersects its list with what was submitted, so an entry it does not know
      # is ignored rather than dispatched to a `copy_<name>` method that does not
      # exist. A collision would need core to add per-project workflows of its
      # own, at which point this plugin has a larger question than a form value.
      COPY_ONLY_KEY = 'project_workflows'

      # Returns [scopes copied, rules copied].
      #
      # +tracker_ids+ is the target's own tracker list, not the source's. They
      # are the same list on the path core takes -- Project.copy_from assigns
      # the source's trackers -- but a scope for a tracker the project does not
      # have is a decision about nothing, and narrowing here is what keeps the
      # copy a restatement of the original rather than a superset of it.
      #
      # A target that already carries a scope of its own is left completely
      # alone. Core only ever calls this on a project it has just created, so on
      # that path there is nothing to leave alone; anywhere else, a project that
      # has already decided something about its own workflow must not have that
      # decision overwritten by a copy (INV-3 -- the three actions stay
      # distinguishable, and "copied over" is not one of them).
      def self.copy(source_project_id:, target_project_id:, user: User.current)
        source_project_id = Integer(source_project_id)
        target_project_id = Integer(target_project_id)
        return [0, 0] if source_project_id == target_project_id

        tracker_ids = Tracker.joins(:projects).where(projects: { id: target_project_id }).distinct.pluck(:id)
        return [0, 0] if tracker_ids.empty?
        return [0, 0] unless copyable?(source_project_id, target_project_id, tracker_ids)

        scopes, rules = ProjectWorkflowScope.transaction do
          copied_scopes = insert_scopes(source_project_id, target_project_id, tracker_ids, user)
          [copied_scopes, insert_rules(source_project_id, target_project_id, tracker_ids)]
        end
        Resolver.reset_cache! if scopes.positive? || rules.positive?
        [scopes, rules]
      end

      # Something to copy, and nothing already there to disturb. Two point
      # queries, both project-scoped (INV-4), and they answer nothing to do for
      # the overwhelmingly common case -- a project that never overrode anything
      # -- before a single write is attempted.
      def self.copyable?(source_project_id, target_project_id, tracker_ids)
        ProjectWorkflowScope.exists?(project_id: source_project_id, tracker_id: tracker_ids) &&
          !ProjectWorkflowScope.exists?(project_id: target_project_id)
      end
      private_class_method :copyable?

      # One INSERT ... SELECT for the decisions, whatever the number of
      # (tracker, role, rule type) combinations. Written as raw SQL for the
      # reason ScopeCopier gives at length: every column value is either a
      # column of a row already in the table or an integer id resolved from the
      # database, so no request parameter can reach one, and the constraints a
      # validation would check are on the table itself (INV-2).
      def self.insert_scopes(source_project_id, target_project_id, tracker_ids, user)
        connection = ProjectWorkflowScope.connection
        table = ProjectWorkflowScope.table_name
        author = ProjectWorkflowScope.author_id_for(user)
        author_value = author ? connection.quote(author) : 'NULL'
        now = connection.quote(connection.quoted_date(Time.now.utc))
        target = ProjectWorkflowScope.where(project_id: target_project_id)
        before = target.count

        # rubocop:disable Rails/SkipsModelValidations -- see the comment above.
        connection.insert(
          "INSERT INTO #{table} " \
          '(project_id, tracker_id, role_id, rule_type, ' \
          'created_by_id, updated_by_id, created_at, updated_at) ' \
          "SELECT #{connection.quote(target_project_id)}, source.tracker_id, source.role_id, source.rule_type, " \
          "#{author_value}, #{author_value}, #{now}, #{now} " \
          "FROM #{table} source " \
          "WHERE source.project_id = #{connection.quote(source_project_id)} " \
          "AND source.tracker_id IN (#{quoted_list(connection, tracker_ids)})"
        )
        # rubocop:enable Rails/SkipsModelValidations
        target.count - before
      end
      private_class_method :insert_scopes

      # One statement per rule type, because the scope table names the rule type
      # and the +workflows+ table names the STI class, and the two are joined by
      # ProjectWorkflowScope's own mapping rather than by a CASE nobody would
      # read. Both values come from RULE_TYPES, which is a server-built list.
      def self.insert_rules(source_project_id, target_project_id, tracker_ids)
        ProjectWorkflowScope::RULE_TYPES.sum do |rule_type|
          insert_rules_of_type(source_project_id, target_project_id, tracker_ids, rule_type)
        end
      end
      private_class_method :insert_rules

      def self.insert_rules_of_type(source_project_id, target_project_id, tracker_ids, rule_type)
        model = ProjectWorkflowScope.rule_model_for(rule_type)
        connection = WorkflowRule.connection
        rules = WorkflowRule.table_name
        scopes = ProjectWorkflowScope.table_name
        rule_column = connection.quote_column_name('rule')
        target = model.where(project_id: target_project_id)
        before = target.count

        # EXISTS against the *source* project's scopes: a rule row the resolver
        # would ignore where it is now is a rule row the copy has no use for
        # either (INV-3).
        #
        # rubocop:disable Rails/SkipsModelValidations -- the same argument as
        # #insert_scopes above and as WorkflowRule.copy_generic_to_project:
        # every column value is a column of a row already in the table or an id
        # resolved from the database, and there is nothing for a validation to
        # check that the table's own constraints do not (INV-2).
        connection.insert(
          "INSERT INTO #{rules} " \
          "(tracker_id, role_id, old_status_id, new_status_id, author, assignee, field_name, #{rule_column}, " \
          'type, project_id) ' \
          'SELECT source.tracker_id, source.role_id, source.old_status_id, source.new_status_id, ' \
          "source.author, source.assignee, source.field_name, source.#{rule_column}, source.type, " \
          "#{connection.quote(target_project_id)} " \
          "FROM #{rules} source " \
          "WHERE source.project_id = #{connection.quote(source_project_id)} " \
          "AND source.type = #{connection.quote(model.name)} " \
          "AND source.tracker_id IN (#{quoted_list(connection, tracker_ids)}) " \
          "AND EXISTS (SELECT 1 FROM #{scopes} scope " \
          'WHERE scope.project_id = source.project_id ' \
          'AND scope.tracker_id = source.tracker_id ' \
          'AND scope.role_id = source.role_id ' \
          "AND scope.rule_type = #{connection.quote(rule_type)})"
        )
        # rubocop:enable Rails/SkipsModelValidations
        target.count - before
      end
      private_class_method :insert_rules_of_type

      # Integers, resolved from the database and quoted anyway. Never empty --
      # both callers return early on an empty tracker list, and an empty IN ()
      # is a syntax error on MySQL rather than the empty set.
      def self.quoted_list(connection, ids)
        ids.map { |id| connection.quote(Integer(id)) }.join(', ')
      end
      private_class_method :quoted_list
    end
  end
end
