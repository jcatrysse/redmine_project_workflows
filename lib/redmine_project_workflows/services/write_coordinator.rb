# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # The one place a write path says "nobody else may be rewriting this
    # workflow while I am" (WP13, audit finding F07).
    #
    # Before this there were two policies. A **project** write took
    # `SELECT ... FOR UPDATE` on the scope rows of the combinations it was about
    # to rewrite, which is what makes "does this project run its own workflow
    # here?" and "write its rules" one decision. A **generic** write took
    # nothing at all: the generic workflow is what a project inherits, not
    # something a project decides, so it has no scope row -- and two
    # administrators saving the same matrix at the same moment could both find
    # no row to delete and both insert one. The README documents the outcome
    # (a cell that renders as a mixed dropdown instead of a checkbox) and the
    # plugin ships a repair rake task for it.
    #
    # The calibration, because it decides how much machinery this deserves:
    # **core has the identical race and the plugin inherited it.** Core's own
    # `WorkflowTransition.replace_transitions` reads outside any lock and carries
    # an opportunistic `w[1..-1].each(&:destroy)` that repairs duplicates on
    # every save. This is not a regression the plugin introduced; it is a core
    # defect the plugin is unusually well placed to fix, because it is now the
    # write path for both populations.
    #
    # **One key, two kinds of row.** The key is
    # `(rule_type, project-or-generic, tracker, role)` and the caller never
    # names anything else. What that key resolves to differs by population, and
    # deliberately:
    #
    #   a project    the project's own scope row, which already exists exactly
    #                when the combination is writable -- so the lock and the
    #                "may I write this?" answer are one statement, as they have
    #                been since 0.1.2
    #   generic      a row in `project_workflow_write_locks`, which exists for
    #                no other reason
    #
    # Giving the generic population a *scope* row instead was the alternative,
    # and it is the one thing that must not be done: a scope row means "this
    # project decides" (INV-3), and a generic one would be a fourth state in a
    # model whose whole purpose is that there are three.
    #
    # **Lock order, which is what keeps two callers queueing rather than
    # deadlocking.** Within either table the rows are taken by ascending primary
    # key. Between the tables, the generic rows are taken *after* any project
    # scope rows -- which is what the callers already do without being told:
    # AdminMatrix#write_matrix iterates `selected_project_ids`, and
    # WorkflowSelection#selected_project_ids appends the generic `nil` last.
    #
    # **What does not go through here, and why that is not an omission:**
    # `WorkflowRule.copy_one_with_projects` -- the one query INV-4 allows to span
    # both populations -- rewrites both of them for a role or tracker that has
    # *just been created* by the copy, so no other request can name it and there
    # is nothing to serialise against.
    class WriteCoordinator
      # The (tracker, role) pairs of this selection the caller may write, with
      # the coordination rows for them locked -- one call, because the lock and
      # the answer are the same decision.
      #
      # +pairs+ are records, as the writers hold them. A generic write may write
      # every pair: it has no scope and cannot be inheriting.
      def self.writable_pairs(project_id, trackers, roles, rule_type)
        all_pairs = trackers.product(roles)
        return lock_generic(rule_type: rule_type, pairs: all_pairs) if project_id.nil?

        scoped = ScopeWriter.existing_combinations(
          project_ids: [project_id], tracker_ids: trackers.map(&:id), role_ids: roles.map(&:id),
          rule_type: rule_type, lock: true
        ).to_set
        all_pairs.select { |tracker, role| scoped.include?([project_id.to_i, tracker.id, role.id]) }
      end

      # Locks the generic population's rows for these (tracker, role) pairs and
      # answers the pairs unchanged, so a caller can write `pairs = lock_generic(...)`.
      #
      # Public because the copy screen needs it too: a copy whose target is
      # 'global' writes generic rules through a path that never reaches a matrix
      # writer, and CopyScopes#lock_scopes_for_copy compacts the generic target
      # out of the scope combinations precisely because there is no scope for it.
      #
      # +pairs+ may be records or ids; only the ids are used.
      def self.lock_generic(rule_type:, pairs:)
        keys = pairs.map { |tracker, role| [id_of(tracker), id_of(role)] }.uniq.sort
        lock_keys(rule_type, keys)
        pairs
      end

      # Create what is missing, then lock the lot by ascending primary key.
      #
      # The read before the create is what keeps the common case to two
      # statements: after the first generic save of a combination the row is
      # simply there, for the life of the installation.
      def self.lock_keys(rule_type, keys)
        return if keys.empty?

        create_missing(rule_type, keys)
        ids = rows_for(rule_type, keys).order(:id).pluck(:id)
        return if ids.empty?

        # By primary key in a second statement, in id order: the same shape as
        # ScopeWriter.lock_combinations, and for the same three reasons -- a row
        # another transaction deleted is simply absent, InnoDB takes no gap lock
        # over a mostly empty range, and two callers take the same locks in the
        # same order.
        ProjectWorkflowWriteLock.where(id: ids).order(:id).lock.pluck(:id)
      end
      private_class_method :lock_keys

      # One validated record per missing key, never insert_all: the
      # forbidden-constructs table confines that to the two rule writers (INV-2),
      # and insert_all is the *skipping* form, so a lost race would be reported
      # as a row this call created.
      #
      # In sorted key order, so that two callers creating overlapping sets block
      # each other in one direction only. A caller blocked on the unique index
      # here holds no coordination row yet, so it cannot be half of a cycle.
      def self.create_missing(rule_type, keys)
        existing = rows_for(rule_type, keys).pluck(:tracker_id, :role_id).to_set
        keys.reject { |key| existing.include?(key) }.each do |tracker_id, role_id|
          create_row(rule_type, tracker_id, role_id)
        end
      end
      private_class_method :create_missing

      # Two rescues, for the reason ScopeWriter.create_scope gives: the
      # uniqueness validation catches the ordinary case with a SELECT and raises
      # RecordInvalid, while RecordNotUnique is the narrow race where the other
      # transaction committed between that SELECT and this INSERT. Either way the
      # row now exists, which is all this method wanted. RecordInvalid for
      # anything else is a bug and is re-raised.
      #
      # requires_new because PostgreSQL refuses every further statement of a
      # transaction after a failed one, and the failed one here is expected.
      def self.create_row(rule_type, tracker_id, role_id)
        row = ProjectWorkflowWriteLock.new(rule_type: rule_type, tracker_id: tracker_id, role_id: role_id)
        ProjectWorkflowWriteLock.transaction(requires_new: true) { row.save! }
      rescue ActiveRecord::RecordNotUnique
        nil
      rescue ActiveRecord::RecordInvalid
        raise unless row.errors.of_kind?(:tracker_id, :taken)

        nil
      end
      private_class_method :create_row

      # An OR of exact pairs grouped by tracker, which is the shape
      # MatrixScope#pair_predicate uses and for the same reason: the cross
      # product of the two id lists would name combinations the caller did not,
      # and a lock on a row nobody is writing is contention for nothing.
      def self.rows_for(rule_type, keys)
        table = ProjectWorkflowWriteLock.arel_table
        conditions = keys.group_by(&:first).map do |tracker_id, group|
          table[:tracker_id].eq(tracker_id).and(table[:role_id].in(group.map(&:last)))
        end
        ProjectWorkflowWriteLock.where(rule_type: rule_type)
                                .where(conditions.reduce { |memo, condition| memo.or(condition) })
      end
      private_class_method :rows_for

      def self.id_of(record)
        record.respond_to?(:id) ? record.id : record.to_i
      end
      private_class_method :id_of
    end
  end
end
