# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Every write to the scope table and its rules that is expressed as a **set
    # operation** rather than a row at a time: the two inserts *give own
    # workflow* is made of (ADR-004), and the batched deletes the other two
    # actions of INV-3 issue.
    #
    # Split out of ScopeWriter, which crossed the `Metrics/ClassLength` limit
    # that `.rubocop.yml` has already relaxed once with a stated rationale -- so
    # crossing it is a signal to extract rather than a cop to placate, and this
    # repository has been here six times with six genuine improvements. The unit
    # is coherent on its own: ScopeWriter holds the three actions of INV-3 and
    # decides *what* to write; this holds *how* the largest of them is issued.
    #
    # **Neither method is safe on its own.** Both are correct only while the
    # caller holds the coordination rows for the (tracker, role) pairs, which is
    # what makes the combinations it read the combinations it creates, and what
    # keeps the generic workflow still while it is being copied. ScopeWriter.enable
    # is the only caller, takes those rows as the first statement of its
    # transaction, and `spec/plugin_conventions_spec.rb` asserts it still does.
    class ScopeBulkWriter
      # Rows per statement when a delete is expressed as an OR of triples.
      DELETE_BATCH_SIZE = 500

      # Rows per statement for the decisions, and projects per statement for
      # their rules. The same order as ScopeWriter::DELETE_BATCH_SIZE and for the
      # same reason: a statement a database can plan, rather than one built from
      # an unbounded selection.
      INSERT_BATCH_SIZE = 1_000

      # The decisions, one statement per INSERT_BATCH_SIZE rows.
      #
      # `insert_all!` -- the **raising** form -- and this is the one place the
      # forbidden-constructs table permits it outside the two rule writers.
      # ADR-004 authorises it on the condition above: with the coordination rows
      # held there is nothing to conflict with, so a conflict is a defect rather
      # than a row skipped in silence, which is the bug 0.1.1 shipped with the
      # skipping form. ScopeWriter.create_scopes keeps its per-row `save!` for
      # the copy screen, which holds no such lock.
      #
      # What the skipped validations would have checked is checked anyway: the
      # rule type against RULE_TYPES here, the three ids by NOT NULL columns, and
      # uniqueness by the table's own unique index -- which is the real arbiter
      # in either shape. No request parameter reaches a row hash (INV-2): every
      # value is an id resolved from the database, a constant, or a clock.
      def self.create_scopes!(combinations, rule_type, user)
        unless ProjectWorkflowScope::RULE_TYPES.include?(rule_type)
          raise ArgumentError, "unknown workflow scope rule type #{rule_type.inspect}"
        end
        return combinations if combinations.empty?

        author_id = ProjectWorkflowScope.author_id_for(user)
        now = Time.now.utc
        rows = combinations.map do |project_id, tracker_id, role_id|
          { project_id: project_id, tracker_id: tracker_id, role_id: role_id, rule_type: rule_type,
            created_by_id: author_id, updated_by_id: author_id, created_at: now, updated_at: now }
        end
        # rubocop:disable Rails/SkipsModelValidations -- see the comment above.
        rows.each_slice(INSERT_BATCH_SIZE) { |slice| ProjectWorkflowScope.insert_all!(slice) }
        # rubocop:enable Rails/SkipsModelValidations
        combinations
      end

      # Whether anything at all is stored under these combinations.
      #
      # *Give own workflow* clears rules under a combination it has just created,
      # because a database predating the scope table can carry orphan rows. That
      # delete is an OR of triples and costs about 0.05 ms per combination on
      # both engines -- a second at 20,000 -- while this answers "there is
      # nothing here" in no measurable time, which is the case on every
      # installation that has not been through the backfill.
      #
      # Over the enclosing id lists rather than the exact triples: a superset
      # that finds nothing proves the subset holds nothing, and it is one
      # statement instead of one per batch. It is only sound for a caller that
      # holds the coordination rows -- ScopeWriter.delete_rules deliberately has
      # no such guard, because its other callers race with writers.
      def self.orphan_rules?(combinations, rule_type)
        return false if combinations.empty?

        ProjectWorkflowScope.rule_model_for(rule_type)
                            .exists?(project_id: combinations.map { |project_id, _t, _r| project_id }.uniq,
                                     tracker_id: combinations.map { |_p, tracker_id, _r| tracker_id }.uniq,
                                     role_id: combinations.map { |_p, _t, role_id| role_id }.uniq)
      end

      # The rules, one INSERT ... SELECT per (tracker, role) per chunk of
      # projects.
      #
      # Grouped by pair rather than issued as one cross-product statement for the
      # reason WorkflowRule.copy_generic_to_projects gives at length: a cross
      # product would re-copy the generic rules into a combination that already
      # had a scope of its own, duplicating its rules. The first prototype had
      # that shape and only passed because every combination in it was new.
      def self.copy_generic_rules(combinations, sti_type)
        combinations.group_by { |_project_id, tracker_id, role_id| [tracker_id, role_id] }
                    .each do |(tracker_id, role_id), triples|
          WorkflowRule.copy_generic_to_projects(
            triples.map(&:first), tracker_id, role_id, sti_type, chunk_size: INSERT_BATCH_SIZE
          )
        end
        combinations
      end

      # One statement per DELETE_BATCH_SIZE triples rather than one per triple.
      # The predicate is an OR of exact triples, not the cross product of the
      # three id lists, so a combination the caller did not name is never hit.
      def self.each_batch_predicate(combinations, table)
        combinations.each_slice(DELETE_BATCH_SIZE) do |slice|
          conditions = slice.map do |project_id, tracker_id, role_id|
            table[:project_id].eq(project_id)
                              .and(table[:tracker_id].eq(tracker_id))
                              .and(table[:role_id].eq(role_id))
          end
          yield conditions.reduce { |memo, condition| memo.or(condition) }
        end
      end

      # Deletes what is there, unconditionally, and that is not an oversight.
      #
      # ADR-004 wanted an EXISTS in front of this, because *enable* calls it
      # defensively over combinations that were inheriting a moment ago and
      # normally hold nothing. Folded in here it broke the other two callers, and
      # the measurement is in the concurrency spec: *return to the generic
      # workflow* deletes rules a matrix save may be writing at that very moment,
      # so a check-then-act skips the delete and leaves rules standing under a
      # scope that is about to go -- rows the resolver ignores and nothing ever
      # cleans up. Caught on MariaDB, where that interleaving actually happens.
      #
      # The guard is therefore ScopeBulkWriter.orphan_rules?, asked by the one
      # caller that holds the coordination rows and can prove nothing is writing.
      def self.delete_rules(combinations, rule_type)
        return if combinations.empty?

        model = ProjectWorkflowScope.rule_model_for(rule_type)
        each_batch_predicate(combinations, model.arel_table) do |predicate|
          model.where(predicate).delete_all
        end
      end

      def self.delete_scopes(combinations, rule_type)
        return if combinations.empty?

        each_batch_predicate(combinations, ProjectWorkflowScope.arel_table) do |predicate|
          ProjectWorkflowScope.where(rule_type: rule_type).where(predicate).delete_all
        end
      end
    end
  end
end
