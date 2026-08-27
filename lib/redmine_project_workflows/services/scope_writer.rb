# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # One of the two places that create or remove a scope; ScopeCopier, which
    # duplicates them along with a role or a tracker, is the other.
    #
    # INV-3 names three actions that must stay distinguishable in the database,
    # and they are the three public actions here:
    #
    #   enable                 create the scope     (rules copied, or none)
    #   return_to_inheritance  delete scope + rules
    #   clear_rules            keep the scope, delete the rules
    #
    # Nothing else may collapse two of them. In particular no write path removes
    # a scope implicitly: deleting the last rule of a project leaves the scope
    # standing, which is what makes "this project deliberately allows nothing"
    # expressible at all.
    #
    # Every method here works on (project_id, tracker_id, role_id) triples for
    # one rule type, and every delete names its project ids (INV-1, INV-4).
    class ScopeWriter
      # Rows per statement when a delete is expressed as an OR of triples.
      DELETE_BATCH_SIZE = 500

      # Records that somebody changed the rules of the scopes in this selection.
      # Only existing scopes are touched -- a combination that inherits has no
      # row to stamp, and creating one here would collapse "save" into "enable"
      # (INV-3). This is the whole of what a matrix save does to the scope
      # table: `ensure_scopes`, which used to create the missing rows here on
      # behalf of the two writers, is gone, because that is exactly what made
      # a plain Save on the administration matrix turn an inheriting project
      # into one with an own **empty** workflow.
      #
      # The two halves of the audit trail say different things, which is why a
      # repeated save moves one of them and not the other (WP6):
      #
      #   created_by_id / created_at   who decided this project runs its own
      #                                workflow here, and when -- never touched
      #                                again, so a save is not mistaken for a
      #                                fresh decision
      #   updated_by_id / updated_at   who last changed the rules, and when
      #
      # The touch covers every combination in the selection rather than only the
      # ones whose rules actually differ afterwards. A matrix save submits and
      # rewrites the whole matrix for the whole selection, so "this workflow was
      # saved by this person" is true of all of them; telling a rewrite that
      # changed nothing apart from one that did would mean diffing every cell on
      # a path that already writes the lot.
      #
      # One statement rather than one per scope: a selection on the
      # administration screens can be every project on the installation, and
      # there is nothing here for a validation to check -- only the two audit
      # columns change.
      def self.touch_scopes(project_ids:, tracker_ids:, role_ids:, rule_type:, user: User.current)
        project_ids, tracker_ids, role_ids = normalize(project_ids, tracker_ids, role_ids)
        return 0 if project_ids.empty? || tracker_ids.empty? || role_ids.empty?

        scope_relation(project_ids, tracker_ids, role_ids, rule_type)
          .update_all( # rubocop:disable Rails/SkipsModelValidations
            updated_by_id: author_id_for(user), updated_at: Time.now.utc
          )
      end

      # Records the decision for the combinations that already carry rules, and
      # for no others.
      #
      # This is what the copy screen needs. WorkflowRule.copy_for_project writes
      # rules straight into a project, and without a scope the resolver would
      # ignore every one of them; but creating a scope where nothing was copied
      # would hand the project an *empty* workflow, which for transitions means
      # no issue in it can change status. So the scope follows the rows.
      def self.ensure_scopes_for_existing_rules(combinations:, rule_type:, user: User.current)
        create_scopes(
          ScopeCombinations.with_rules_and_no_scope(combinations, rule_type), rule_type, user
        )
      end

      # The copy screen's entry point: both rule types at once, because
      # WorkflowRule.copy_for_project moves both.
      #
      # +combinations+ is what the copy actually acted on, not what it was aimed
      # at -- the caller gets that from copy_for_project's return value. Every one
      # of those pairs had its rows of *both* rule types deleted before anything
      # was inserted, so the rules of both types have changed for all of them,
      # and the touch covers all of them per rule type.
      #
      # The touch is what makes the audit line true on this path as well. A copy
      # into a project that already had a scope deletes and rewrites its rules
      # and creates nothing, so without it the inventory would go on naming
      # whoever last saved the matrix by hand -- for rules somebody else has
      # since replaced wholesale. It runs after the create, unlike the writers':
      # here the scopes that already existed are exactly the ones whose rules
      # were overwritten, and the ones just created carry the same user anyway.
      def self.ensure_scopes_for_copy(combinations:, user: User.current)
        combinations = ScopeCombinations.normalize(combinations)
        ProjectWorkflowScope::RULE_TYPES.flat_map do |rule_type|
          created = ensure_scopes_for_existing_rules(
            combinations: combinations, rule_type: rule_type, user: user
          )
          touch_combinations(combinations, rule_type, user)
          created
        end
      end

      # The copy screen's lock, and it has to be the first statement inside the
      # copy's transaction.
      #
      # 0.1.2 gave the two matrix writers and the two scope actions a locked
      # read (MatrixScope#writable_pairs, .return_to_inheritance, .clear_rules)
      # so that "does this project run its own workflow here?" and "write its
      # rules" stopped being two decisions. The copy screen was left out, and
      # docs/design.md went on claiming the rule held everywhere (finding F01).
      # Unlocked, the copy writes rules for every target project and only then
      # reads the scope table, which is the same check-then-act it was, one path
      # further along.
      #
      # Two outcomes, and the quiet one is why this is not merely a deadlock
      # fix. For a combination whose scope has no rules under it -- an own
      # *empty* workflow, which ADR-001 supports -- the copy's delete locks
      # nothing, so a concurrent return to the generic workflow never collides
      # with it: the copy then reads a scope row the return has deleted but not
      # committed, concludes the combination is already scoped, creates nothing,
      # and commits its rules under a scope that is gone. Reproduced from Rails
      # with two connections: one rule left in `workflows`, no scope, no error,
      # `notice_successful_update`.
      #
      # +combinations+ is what the copy is *about* to act on, computed before
      # any write from WorkflowRule.copy_pairs_for_project. Both rule types at
      # once and no rule_type filter, because the copy replaces both.
      #
      # The residual case no row lock can close: a combination with no scope row
      # has nothing to pre-take, so copy-versus-.enable is serialised by the
      # unique index and can still form a cycle. That is recorded rather than
      # chased -- if it is ever observed, the answer is a
      # `rescue ActiveRecord::Deadlocked` on the copy action, not a wider lock.
      def self.lock_scopes_for_copy(combinations:)
        combinations = ScopeCombinations.normalize(combinations)
        return [] if combinations.empty?

        ids = []
        each_batch_predicate(combinations, ProjectWorkflowScope.arel_table) do |predicate|
          ids.concat(ProjectWorkflowScope.where(predicate).pluck(:id))
        end
        return [] if ids.empty?

        # Ascending primary key, which is the order .lock_combinations takes and
        # the whole reason two callers queue rather than deadlock. Sorted here
        # rather than relying on the batches, whose ids only ascend within a
        # batch.
        ProjectWorkflowScope.where(id: ids.sort).order(:id).lock
                            .pluck(:project_id, :tracker_id, :role_id)
      end

      # Records that somebody changed the rules of exactly these
      # (project_id, tracker_id, role_id) combinations.
      #
      # The difference from .touch_scopes is the shape of the selection, and that
      # is the whole point: .touch_scopes takes three id lists and stamps their
      # cross product, which is right for a matrix save -- the save really does
      # rewrite every cell of it -- and wrong for a copy, which acts on a set of
      # exact pairs and skips any whose source resolves to the target itself.
      # Stamping the cross product there named the operator as the last person to
      # change a workflow the copy had not been near (finding F04).
      def self.touch_combinations(combinations, rule_type, user = User.current)
        combinations = ScopeCombinations.normalize(combinations)
        return 0 if combinations.empty?

        stamp = { updated_by_id: author_id_for(user), updated_at: Time.now.utc }
        touched = 0
        each_batch_predicate(combinations, ProjectWorkflowScope.arel_table) do |predicate|
          touched += ProjectWorkflowScope.where(rule_type: rule_type).where(predicate)
                                         .update_all(stamp) # rubocop:disable Rails/SkipsModelValidations
        end
        touched
      end

      # Action one: give these projects their own workflow.
      #
      # Only combinations that currently inherit are touched, so pressing the
      # button twice does not throw away the rules the first press produced.
      # +copy_generic+ decides where the new workflow starts: a copy of the
      # generic rules, or nothing at all. It defaults to the copy because a
      # scope replaces (INV-5) -- an empty one permits no transition, and
      # arriving there by accident would freeze every issue in the project.
      def self.enable(project_ids:, tracker_ids:, role_ids:, rule_type:, copy_generic: true, user: User.current)
        sti_type = ProjectWorkflowScope.rule_model_for(rule_type).name
        touched = 0

        ProjectWorkflowScope.transaction do
          combinations = missing_combinations(
            project_ids: project_ids, tracker_ids: tracker_ids, role_ids: role_ids, rule_type: rule_type
          )
          next if combinations.empty?

          # Everything below acts on the combinations this call actually
          # created, not on the ones it set out to create. The two differ when
          # a second administrator pressed the same button first: that scope is
          # theirs, its rules are the ones they just copied, and clearing and
          # re-copying them here would undo a decision this request never made.
          created = create_scopes(combinations, rule_type, user)
          next if created.empty?

          # Defensive: a combination that inherits should carry no rules of its
          # own, but a database that predates the scope table may. Clearing
          # first makes the result of "enable" the same either way.
          delete_rules(created, rule_type)
          if copy_generic
            created.each do |project_id, tracker_id, role_id|
              WorkflowRule.copy_generic_to_project(project_id, tracker_id, role_id, sti_type)
            end
          end
          touched = created.size
        end
        # create_scopes already resets, but only when it created something, and
        # this action deletes and re-copies rules either way.
        Resolver.reset_cache! if touched.positive?
        touched
      end

      # Action two: return these projects to the generic workflow. The scope and
      # the rules both go; nothing about the project is left in the tables.
      #
      # The scopes are locked before either delete, which is the same order the
      # rule writers take (MatrixScope#writable_pairs). It is what decides the
      # race between this action and a matrix save: whichever of the two gets
      # the scope rows first runs to completion, and the other one sees the
      # table as it left it. Taking the rules first instead would let a save
      # write project rules whose scope this transaction is about to delete --
      # rows the resolver then ignores, because a project without a scope
      # follows the generic workflow (INV-3).
      def self.return_to_inheritance(project_ids:, tracker_ids:, role_ids:, rule_type:)
        touched = 0

        ProjectWorkflowScope.transaction do
          combinations = existing_combinations(
            project_ids: project_ids, tracker_ids: tracker_ids, role_ids: role_ids,
            rule_type: rule_type, lock: true
          )
          next if combinations.empty?

          delete_rules(combinations, rule_type)
          delete_scopes(combinations, rule_type)
          touched = combinations.size
        end
        Resolver.reset_cache! if touched.positive?
        touched
      end

      # Action three: empty the matrix. The scope stays, so the project keeps
      # its own workflow -- one that permits nothing.
      #
      # Only combinations that already have a scope are touched. Emptying a
      # matrix a project does not own would otherwise read as a change while
      # leaving it inheriting, which is the very confusion the scope table
      # exists to end.
      def self.clear_rules(project_ids:, tracker_ids:, role_ids:, rule_type:, user: User.current)
        project_ids, tracker_ids, role_ids = normalize(project_ids, tracker_ids, role_ids)
        touched = 0

        ProjectWorkflowScope.transaction do
          # Locked, for the reason .return_to_inheritance gives: this action
          # deletes rules too, and it must not be deleting the rules of a scope
          # somebody else is removing from under it in the other order.
          combinations = existing_combinations(
            project_ids: project_ids, tracker_ids: tracker_ids, role_ids: role_ids,
            rule_type: rule_type, lock: true
          )
          next if combinations.empty?

          delete_rules(combinations, rule_type)
          # Emptying a matrix is a change to the rules like any other, so it is
          # the same stamp the writers leave. The relation covers exactly the
          # combinations found above, because those are the scopes this selection
          # has.
          touch_scopes(
            project_ids: project_ids, tracker_ids: tracker_ids, role_ids: role_ids,
            rule_type: rule_type, user: user
          )
          touched = combinations.size
        end
        # No scope was created or removed, but every rule of these combinations
        # was deleted, and StatusListQuery caches an answer derived from rules.
        Resolver.reset_cache! if touched.positive?
        touched
      end

      # (project_id, tracker_id, role_id) triples in this selection that have a
      # scope for this rule type.
      #
      # +lock+ takes SELECT ... FOR UPDATE on exactly those rows, and only
      # means anything inside a transaction, which is where every caller that
      # passes it is. It makes "does this project run its own workflow here?"
      # and "write its rules" one decision instead of two: without it the
      # answer can be true when it is read and false by the time the rules are
      # written, and the rules are then stored under a scope that no longer
      # exists -- rows the resolver ignores, on a save that reported success.
      def self.existing_combinations(project_ids:, tracker_ids:, role_ids:, rule_type:, lock: false)
        project_ids, tracker_ids, role_ids = normalize(project_ids, tracker_ids, role_ids)
        return [] if project_ids.empty? || tracker_ids.empty? || role_ids.empty?

        relation = scope_relation(project_ids, tracker_ids, role_ids, rule_type)
        return relation.pluck(:project_id, :tracker_id, :role_id) unless lock

        lock_combinations(relation)
      end

      # The lock is taken by primary key in a second statement, in id order,
      # and what that statement returns is the answer -- not what the first one
      # found. Three reasons for the shape:
      #
      #   * a row this transaction had to wait for, because the transaction it
      #     waited for was deleting it, is simply absent from the second read.
      #     That is the whole point: the caller sees the table as the other
      #     transaction left it, never as it was before.
      #   * locking by primary key rather than by the (project, tracker, role)
      #     predicate keeps InnoDB from taking gap locks over a range that is
      #     mostly empty, which would block inserts nobody in this request
      #     cares about.
      #   * the id order makes two callers take the same locks in the same
      #     order, so a pair of concurrent saves queue rather than deadlock.
      def self.lock_combinations(relation)
        ids = relation.order(:id).pluck(:id)
        return [] if ids.empty?

        ProjectWorkflowScope.where(id: ids).order(:id).lock
                            .pluck(:project_id, :tracker_id, :role_id)
      end
      private_class_method :lock_combinations

      # The complement: triples in this selection that inherit.
      def self.missing_combinations(project_ids:, tracker_ids:, role_ids:, rule_type:)
        project_ids, tracker_ids, role_ids = normalize(project_ids, tracker_ids, role_ids)
        return [] if project_ids.empty? || tracker_ids.empty? || role_ids.empty?

        existing = existing_combinations(
          project_ids: project_ids, tracker_ids: tracker_ids, role_ids: role_ids, rule_type: rule_type
        ).to_set
        project_ids.product(tracker_ids, role_ids).reject { |triple| existing.include?(triple) }
      end

      def self.scope_relation(project_ids, tracker_ids, role_ids, rule_type)
        ProjectWorkflowScope.where(
          project_id: project_ids, tracker_id: tracker_ids,
          role_id: role_ids, rule_type: rule_type
        )
      end
      private_class_method :scope_relation

      def self.normalize(project_ids, tracker_ids, role_ids)
        [project_ids, tracker_ids, role_ids].map do |ids|
          Array(ids).compact.map { |id| id.respond_to?(:id) ? id.id : id.to_i }.uniq
        end
      end
      private_class_method :normalize

      # One validated record per combination, not one insert_all for the lot.
      #
      # 0.1.1 batched these rows with insert_all, and the comment that stood
      # here argued the case: nothing in the row comes from a request, so INV-2
      # was not really at stake. Two things were wrong with that. The
      # forbidden-constructs table in CLAUDE.md is a hard gate (G7) and bans
      # insert_all outside the two rule writers whatever the argument; and the
      # safety the comment claimed -- "a concurrent duplicate raises
      # RecordNotUnique with create! as well" -- is not what insert_all does.
      # insert_all is the *skipping* form (ON CONFLICT DO NOTHING, INSERT
      # IGNORE): the duplicate row was quietly dropped and this method reported
      # the combination created anyway. Two administrators pressing "give own
      # workflow" at the same moment were both told they had created every
      # scope, and the loser went on to clear and re-copy rules that belonged
      # to the winner.
      #
      # So: ProjectWorkflowScope#save!, which runs the model's validations,
      # once per combination. Returns the combinations whose row this call
      # actually inserted -- never the ones it found already there -- because
      # .enable acts on the answer.
      #
      # The cost is one round trip per combination where there used to be one
      # per thousand, on an action whose largest selection is projects x
      # trackers x roles. It is an administrator's explicit bulk action rather
      # than a hot path, and correctness is not negotiable against it. Whether
      # a formally approved bulk boundary should exist anyway was put to Jan
      # and answered on 2026-08-27: it should not. So this is the decided
      # shape, not a safe default waiting for review -- the round trips here
      # are not a performance defect, and a later session should not "optimise"
      # them back into one statement. If the slow case is ever actually met it
      # is the ADR that gets written, not this method that gets rewritten.
      def self.create_scopes(combinations, rule_type, user)
        return [] if combinations.empty?

        # Kept in front of the per-row validation so that a rule type nothing
        # can read fails the whole call rather than being reported, row by row,
        # as a combination that already existed.
        unless ProjectWorkflowScope::RULE_TYPES.include?(rule_type)
          raise ArgumentError, "unknown workflow scope rule type #{rule_type.inspect}"
        end

        author_id = author_id_for(user)
        created = combinations.select do |project_id, tracker_id, role_id|
          create_scope(project_id, tracker_id, role_id, rule_type, author_id)
        end
        Resolver.reset_cache! unless created.empty?
        created
      end
      private_class_method :create_scopes

      # True when this call inserted the row, false when somebody else already
      # had. The difference matters to .enable, which clears and re-copies the
      # rules of what it created.
      #
      # Two rescues because a duplicate arrives as either of two exceptions.
      # The uniqueness validation catches the ordinary case with a SELECT and
      # raises RecordInvalid; RecordNotUnique is the narrow race where the
      # other transaction committed between that SELECT and this INSERT, and
      # there the table's own unique index is what settles it. RecordInvalid
      # for anything *else* is a bug and is re-raised -- swallowing it would
      # turn a rejected row into a silently skipped one.
      #
      # requires_new is what makes the second case survivable: PostgreSQL
      # refuses every further statement of a transaction after a failed one, so
      # without the savepoint one lost race would take the rest of the
      # selection down with it.
      def self.create_scope(project_id, tracker_id, role_id, rule_type, author_id)
        scope = ProjectWorkflowScope.new(
          project_id: project_id, tracker_id: tracker_id, role_id: role_id,
          rule_type: rule_type, created_by_id: author_id, updated_by_id: author_id
        )
        ProjectWorkflowScope.transaction(requires_new: true) { scope.save! }
        true
      rescue ActiveRecord::RecordNotUnique
        false
      rescue ActiveRecord::RecordInvalid
        raise unless scope.errors.of_kind?(:project_id, :taken)

        false
      end
      private_class_method :create_scope

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
      private_class_method :each_batch_predicate

      def self.delete_rules(combinations, rule_type)
        return if combinations.empty?

        model = ProjectWorkflowScope.rule_model_for(rule_type)
        each_batch_predicate(combinations, model.arel_table) do |predicate|
          model.where(predicate).delete_all
        end
      end
      private_class_method :delete_rules

      def self.delete_scopes(combinations, rule_type)
        return if combinations.empty?

        each_batch_predicate(combinations, ProjectWorkflowScope.arel_table) do |predicate|
          ProjectWorkflowScope.where(rule_type: rule_type).where(predicate).delete_all
        end
      end
      private_class_method :delete_scopes

      def self.author_id_for(user)
        ProjectWorkflowScope.author_id_for(user)
      end
      private_class_method :author_id_for
    end
  end
end
