# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module WorkflowRulePatch
      # The two STI classes a workflow rule can be. Anything else is not a rule
      # type the plugin knows how to copy.
      COPYABLE_TYPES = %w[WorkflowTransition WorkflowPermission].freeze

      # Every column that carries meaning in a workflow row. Two rows that agree
      # on all of them say the same thing twice.
      #
      # `rule` is in the list on purpose. Two field-permission rows for the same
      # (project, tracker, role, status, field) with *different* rules are not
      # duplicates but a contradiction, and deleting one of them silently would
      # be choosing an answer on the administrator's behalf. Exact duplicates
      # can always be removed without changing what the workflow permits.
      DUPLICATE_KEY_COLUMNS = %i[
        project_id tracker_id role_id old_status_id new_status_id
        author assignee field_name rule type
      ].freeze

      # Returns the [[tracker, role], ...] pairs it actually copied, which is not
      # the same as the pairs it was given: a pair whose source resolves to the
      # target itself -- "any project, any role, this tracker" on the copy form
      # -- is skipped, and copying nothing is a legitimate outcome. The caller
      # needs the difference, because the scopes to record and the audit columns
      # to stamp are the ones this copy touched and no others (finding F04).
      def copy_for_project(source_project_id, target_project_id, source_tracker, source_role, target_trackers,
                           target_roles)
        unless (source_tracker.nil? || source_tracker.is_a?(Tracker)) &&
               (source_role.nil? || source_role.is_a?(Role)) &&
               (source_tracker.is_a?(Tracker) || source_role.is_a?(Role))
          raise ArgumentError,
                'source_tracker or source_role must be specified as a tracker/role, given: ' \
                "#{source_tracker.class.name} and #{source_role.class.name}"
        end

        copy_pairs, skipped_pairs = copy_pairs_for_project(
          source_project_id, target_project_id, source_tracker, source_role, target_trackers, target_roles
        )

        source_project_id = Integer(source_project_id) if source_project_id
        target_project_id = Integer(target_project_id) if target_project_id

        return [] if copy_pairs.empty?

        # WP13, audit finding F07. A copy into the generic workflow has no scope
        # row to lock -- the generic workflow is what a project inherits, not
        # something a project decides -- so it takes the plugin's own
        # coordination row instead. As one batch, and before
        # #delete_existing_rules_for_project, which is a write: the batch is what
        # fixes the *order* two concurrent copies take these rows in, and taking
        # them pair by pair in the loop below would leave that order up to
        # whatever order the request happened to name its trackers in.
        #
        # Both rule types, because a copy replaces both. A copy into a project
        # takes nothing here: its scope rows are its coordination rows, and the
        # copy screen locks them before it calls this.
        lock_generic_copy(copy_pairs) if target_project_id.nil?

        delete_existing = copy_pairs.size <= 1
        delete_existing_rules_for_project(target_project_id, copy_pairs, skipped_pairs) unless delete_existing

        copy_pairs.each do |target_tracker, target_role|
          copy_one_for_project(
            source_project_id,
            target_project_id,
            source_tracker || target_tracker,
            source_role || target_role,
            target_tracker,
            target_role,
            delete_existing: delete_existing
          )
        end
        copy_pairs
      end

      # Which (tracker, role) pairs a copy would write, and which it would skip,
      # decided without touching either table.
      #
      # Extracted from .copy_for_project so that the copy screen can know its
      # target combinations *before* it writes anything. That is what makes the
      # scope lock takeable in advance (finding F01): the lock has to be the
      # first statement in the transaction, and it can only name the rows the
      # copy is going to act on if the skip rule has already been applied. Two
      # callers, one rule -- duplicating the rule here is how a lock comes to
      # cover a different set from the write it is protecting.
      #
      # Pure arithmetic apart from the two `empty?` fallbacks, which are core's
      # own "no selection means everything" and are queries; the copy screen
      # refuses an empty selection long before this, so on that path they never
      # fire.
      def copy_pairs_for_project(source_project_id, target_project_id, source_tracker, source_role,
                                 target_trackers, target_roles)
        target_trackers = Array.wrap(target_trackers).compact
        target_roles = Array.wrap(target_roles).compact

        target_trackers = Tracker.sorted.to_a if target_trackers.empty?
        target_roles = Role.all.select(&:consider_workflow?) if target_roles.empty?

        source_project_id = Integer(source_project_id) if source_project_id
        target_project_id = Integer(target_project_id) if target_project_id

        target_trackers.product(target_roles).partition do |target_tracker, target_role|
          !((source_tracker || target_tracker) == target_tracker &&
            (source_role || target_role) == target_role &&
            source_project_id == target_project_id)
        end
      end

      # The generic population's coordination rows for these pairs, both rule
      # types, in one call so that Services::WriteCoordinator can sort them.
      def lock_generic_copy(pairs)
        ProjectWorkflowScope::RULE_TYPES.each do |rule_type|
          RedmineProjectWorkflows::Services::WriteCoordinator.lock_generic(rule_type: rule_type, pairs: pairs)
        end
      end

      def copy_one_for_project(source_project_id, target_project_id, source_tracker, source_role, target_tracker,
                               target_role, delete_existing: true)
        unless source_tracker.is_a?(Tracker) && !source_tracker.new_record? &&
               source_role.is_a?(Role) && !source_role.new_record? &&
               target_tracker.is_a?(Tracker) && !target_tracker.new_record? &&
               target_role.is_a?(Role) && !target_role.new_record?

          raise ArgumentError, 'arguments can not be nil or unsaved objects'
        end

        source_project_id = Integer(source_project_id) if source_project_id
        target_project_id = Integer(target_project_id) if target_project_id
        source_project_condition = source_project_id ? "= #{connection.quote(source_project_id)}" : 'IS NULL'
        target_project_value = target_project_id ? connection.quote(target_project_id) : 'NULL'

        return false if source_tracker == target_tracker && source_role == target_role &&
                        source_project_id == target_project_id

        transaction do
          # WP13. Taken here as well as in .copy_for_project, and neither is
          # redundant: **Redmine's own copy screen** reaches this method through
          # core's `WorkflowRule.copy` and the plugin's `.copy_one`, and never
          # goes through .copy_for_project at all -- so without this, the one
          # generic write path a matrix writer never sees would still be
          # unlocked. Re-taking a row this transaction already holds costs
          # nothing.
          lock_generic_copy([[target_tracker, target_role]]) if target_project_id.nil?
          if delete_existing
            where(tracker_id: target_tracker.id, role_id: target_role.id, project_id: target_project_id).delete_all
          end
          connection.insert(
            "INSERT INTO #{WorkflowRule.table_name} " \
            '(tracker_id, role_id, old_status_id, new_status_id, ' \
            "author, assignee, field_name, #{connection.quote_column_name 'rule'}, type, project_id) " \
            "SELECT #{target_tracker.id}, #{target_role.id}, old_status_id, new_status_id, " \
            "author, assignee, field_name, #{connection.quote_column_name 'rule'}, type, #{target_project_value} " \
            "FROM #{WorkflowRule.table_name} " \
            "WHERE tracker_id = #{source_tracker.id} AND role_id = #{source_role.id} " \
            "AND project_id #{source_project_condition}"
          )
        end
        RedmineProjectWorkflows::Services::Resolver.reset_cache!
        true
      end

      # Copies the generic rules of one (tracker, role) into one project, for one
      # kind of rule only -- taking over a project's transitions must not drag
      # its field permissions along (ADR-001, separate scopes per rule type).
      #
      # Written as INSERT ... SELECT, like core's own copy_one and like
      # #copy_one_for_project above: every column value comes from a row that is
      # already in the table, so no request parameter reaches one. The four
      # arguments are ids resolved from the database and an STI class name
      # checked against a server-built list, which is what INV-2 asks of a write
      # that does not go through the two writers.
      def copy_generic_to_project(target_project_id, tracker_id, role_id, sti_type)
        raise ArgumentError, "unknown workflow rule type #{sti_type.inspect}" unless COPYABLE_TYPES.include?(sti_type)

        target_project_id = Integer(target_project_id)
        tracker_id = Integer(tracker_id)
        role_id = Integer(role_id)

        connection.insert(
          "INSERT INTO #{WorkflowRule.table_name} " \
          '(tracker_id, role_id, old_status_id, new_status_id, ' \
          "author, assignee, field_name, #{connection.quote_column_name 'rule'}, type, project_id) " \
          'SELECT tracker_id, role_id, old_status_id, new_status_id, ' \
          "author, assignee, field_name, #{connection.quote_column_name 'rule'}, type, " \
          "#{connection.quote(target_project_id)} " \
          "FROM #{WorkflowRule.table_name} " \
          'WHERE project_id IS NULL ' \
          "AND tracker_id = #{connection.quote(tracker_id)} " \
          "AND role_id = #{connection.quote(role_id)} " \
          "AND type = #{connection.quote(sti_type)}"
        )
        RedmineProjectWorkflows::Services::Resolver.reset_cache!
      end

      # The same copy for many projects at once: one INSERT ... SELECT per
      # (tracker, role) per chunk of projects, instead of one per combination
      # (ADR-004).
      #
      # **One pair per statement, deliberately.** The obvious shape -- join the
      # generic rows to the scope table with `tracker_id IN (...) AND role_id IN
      # (...) AND project_id IN (...)` -- spans the whole cross product, so a
      # combination inside those lists that already had a scope of its own would
      # have the generic rules copied into it a second time, duplicating its
      # rules. The first prototype had exactly that shape and only passed because
      # every combination in it was new. spec/services/scope_writer_bulk_spec.rb
      # pins the case.
      #
      # The join is against the scope rows rather than against a list of ids so
      # that the statement cannot write a rule under a combination that has no
      # scope: a rule row the resolver would ignore is rubbish that nothing ever
      # cleans up (INV-3). ScopeWriter.enable holds the generic coordination rows
      # while this runs, so the scopes it joins to are the ones it has just
      # created.
      #
      # Written as raw SQL for the reason #copy_generic_to_project gives: every
      # column value is a column of a row already in the table or an id resolved
      # from the database, and the STI class name is checked against a
      # server-built list (INV-2). Both statements name their populations --
      # `generic.project_id IS NULL` on the one side and the scope rows' own
      # project ids on the other (INV-4).
      def copy_generic_to_projects(project_ids, tracker_id, role_id, sti_type, chunk_size: 1_000)
        raise ArgumentError, "unknown workflow rule type #{sti_type.inspect}" unless COPYABLE_TYPES.include?(sti_type)

        tracker_id = Integer(tracker_id)
        role_id = Integer(role_id)
        rule_type = ProjectWorkflowScope.rule_type_for(sti_type)
        project_ids = Array(project_ids).map { |id| Integer(id) }
        return 0 if project_ids.empty?

        project_ids.each_slice(chunk_size) do |slice|
          connection.insert(copy_generic_to_projects_sql(slice, tracker_id, role_id, sti_type, rule_type))
        end
        RedmineProjectWorkflows::Services::Resolver.reset_cache!
        project_ids.size
      end

      def copy_generic_to_projects_sql(project_ids, tracker_id, role_id, sti_type, rule_type)
        rules = WorkflowRule.table_name
        scopes = ProjectWorkflowScope.table_name
        rule_column = connection.quote_column_name('rule')

        "INSERT INTO #{rules} " \
          '(tracker_id, role_id, old_status_id, new_status_id, ' \
          "author, assignee, field_name, #{rule_column}, type, project_id) " \
          'SELECT generic.tracker_id, generic.role_id, generic.old_status_id, generic.new_status_id, ' \
          "generic.author, generic.assignee, generic.field_name, generic.#{rule_column}, generic.type, " \
          'scope.project_id ' \
          "FROM #{rules} generic " \
          "JOIN #{scopes} scope ON scope.tracker_id = generic.tracker_id AND scope.role_id = generic.role_id " \
          'WHERE generic.project_id IS NULL ' \
          "AND generic.tracker_id = #{connection.quote(tracker_id)} " \
          "AND generic.role_id = #{connection.quote(role_id)} " \
          "AND generic.type = #{connection.quote(sti_type)} " \
          "AND scope.rule_type = #{connection.quote(rule_type)} " \
          "AND scope.project_id IN (#{project_ids.map { |id| connection.quote(id) }.join(', ')})"
      end
      private :copy_generic_to_projects_sql

      # Core's WorkflowRule.copy, extended to the projects.
      #
      # Deliberately *not* folded into .copy_one. The administration copy screen
      # falls through to core's .copy whenever no project is selected, and that
      # has to stay generic-only: "copy the generic workflow" is not "copy every
      # project's workflow as well". Role#copy_workflow_rules and
      # Tracker#copy_workflow_rules -- the two places that mean "duplicate this
      # role/tracker entirely" -- call this instead (claude F03).
      def copy_with_projects(source_tracker, source_role, target_trackers, target_roles)
        unless source_tracker.is_a?(Tracker) || source_role.is_a?(Role)
          raise ArgumentError,
                'source_tracker or source_role must be specified, given: ' \
                "#{source_tracker.class.name} and #{source_role.class.name}"
        end

        target_trackers = Array.wrap(target_trackers).compact
        target_roles = Array.wrap(target_roles).compact
        target_trackers = Tracker.sorted.to_a if target_trackers.empty?
        target_roles = Role.all.select(&:consider_workflow?) if target_roles.empty?

        transaction do
          target_trackers.each do |target_tracker|
            target_roles.each do |target_role|
              copy_one_with_projects(
                source_tracker || target_tracker,
                source_role || target_role,
                target_tracker,
                target_role
              )
            end
          end
        end
      end

      # One (tracker, role) pair, generic rules and every project's, plus the
      # scopes that make the project rules visible to the resolver. Without the
      # scopes the copied rows would be ignored and the copy would silently be
      # an inheriting workflow (INV-3).
      #
      # One statement, not one per project: project_id is carried through the
      # SELECT rather than substituted, so the generic rows and every project's
      # move together. Copying a role in an installation with 500 overriding
      # projects would otherwise be 500 round trips per tracker.
      #
      # The delete is the target's rows for this (tracker, role) across *all*
      # projects, deliberately: this is a replacing copy, and leaving a target
      # project the source knows nothing about would make the two halves of the
      # same method behave differently. Core only ever calls this on a role or
      # tracker it has just created, so in practice there is nothing to delete.
      #
      # **This is INV-4's one deliberate exception, and CLAUDE.md names it as
      # such.** The `delete_all` carries no `project_id` predicate and the
      # INSERT ... SELECT carries `project_id` through the select list, so both
      # statements span the generic and project populations. Do not "repair" the
      # DELETE alone: the INSERT two lines down spans them too, and scoping one
      # without the other risks half-copying a duplicated role. Reported as a
      # finding twice now (F18); the answer is that the reach is the definition.
      #
      # Also why F01's lock is not extended here, and why extending it would be
      # a no-op that looked like a fix: core calls Role#copy_workflow_rules and
      # Tracker#copy_workflow_rules only on a record it has just created, so
      # there are no target rows and no scope rows to contend for.
      def copy_one_with_projects(source_tracker, source_role, target_tracker, target_role)
        return false if source_tracker == target_tracker && source_role == target_role

        transaction do
          where(tracker_id: target_tracker.id, role_id: target_role.id).delete_all
          connection.insert(
            "INSERT INTO #{WorkflowRule.table_name} " \
            '(tracker_id, role_id, old_status_id, new_status_id, ' \
            "author, assignee, field_name, #{connection.quote_column_name 'rule'}, type, project_id) " \
            "SELECT #{connection.quote(target_tracker.id)}, #{connection.quote(target_role.id)}, " \
            'old_status_id, new_status_id, author, assignee, field_name, ' \
            "#{connection.quote_column_name 'rule'}, type, project_id " \
            "FROM #{WorkflowRule.table_name} " \
            "WHERE tracker_id = #{connection.quote(source_tracker.id)} " \
            "AND role_id = #{connection.quote(source_role.id)}"
          )
        end
        RedmineProjectWorkflows::Services::ScopeCopier.copy_scopes(
          source_tracker_id: source_tracker.id,
          source_role_id: source_role.id,
          target_tracker_id: target_tracker.id,
          target_role_id: target_role.id
        )
        RedmineProjectWorkflows::Services::Resolver.reset_cache!
        true
      end

      def copy_one(source_tracker, source_role, target_tracker, target_role)
        copy_one_for_project(nil, nil, source_tracker, source_role, target_tracker, target_role)
      end

      # Removes exact duplicate rows, keeping the oldest of each set.
      #
      # There is no unique index behind this and there cannot be a portable one:
      # the key contains project_id and field_name, both nullable, and every
      # supported database treats NULLs in a unique index as distinct -- so the
      # generic rows, which are the majority, would not be covered at all.
      # PostgreSQL 15 could express it with NULLS NOT DISTINCT and MySQL 8 with a
      # functional index; MariaDB can do neither, and 5.1 has to run on older
      # PostgreSQL. See docs/design.md (external F06).
      #
      # So this is a repair tool rather than a constraint: rake
      # redmine_project_workflows:deduplicate_workflow_rules. Duplicates matter
      # because the matrix compares row counts against the size it expects and
      # renders a cell as a checkbox or as a mixed dropdown accordingly.
      #
      # The two populations are swept separately, so the generic pass cannot
      # touch a project row or the other way round (INV-1, INV-4).
      def delete_duplicate_rules!
        deleted = [where(project_id: nil), where.not(project_id: nil)].sum do |scope|
          delete_duplicates_within(scope)
        end
        RedmineProjectWorkflows::Services::Resolver.reset_cache! if deleted.positive?
        deleted
      end

      def delete_duplicates_within(scope)
        duplicate_keys = scope.group(DUPLICATE_KEY_COLUMNS).having('COUNT(*) > 1').count.keys
        return 0 if duplicate_keys.empty?

        duplicate_keys.sum do |key|
          ids = scope.where(DUPLICATE_KEY_COLUMNS.zip(Array(key)).to_h).order(:id).pluck(:id)
          # Deleted through the population's own relation, not by id alone, so
          # the statement still names its project predicate (INV-4).
          scope.where(id: ids.drop(1)).delete_all
        end
      end

      def delete_existing_rules_for_project(project_id, copy_pairs, skipped_pairs)
        tracker_ids = copy_pairs.map { |tracker, _role| tracker.id }.uniq
        role_ids = copy_pairs.map { |_tracker, role| role.id }.uniq
        scope = where(tracker_id: tracker_ids, role_id: role_ids, project_id: project_id)
        return scope.delete_all if skipped_pairs.empty?

        table = WorkflowRule.arel_table
        exclusions = skipped_pairs.map do |tracker, role|
          table[:tracker_id].eq(tracker.id).and(table[:role_id].eq(role.id))
        end
        predicate = exclusions.reduce { |memo, condition| memo.or(condition) }
        scope.where.not(predicate).delete_all
      end
    end
  end
end
