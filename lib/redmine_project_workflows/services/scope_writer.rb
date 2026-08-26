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

      # Creates the scopes a project write implies, and nothing else. Called by
      # TransitionWriter and PermissionWriter so that saving a project matrix
      # records the decision along with the rules.
      #
      # Combinations that already have a scope are left exactly as they are --
      # their audit columns included -- so that repeating a save is not mistaken
      # for a fresh decision.
      def self.ensure_scopes(project_ids:, tracker_ids:, role_ids:, rule_type:, user: User.current)
        combinations = missing_combinations(
          project_ids: project_ids, tracker_ids: tracker_ids, role_ids: role_ids, rule_type: rule_type
        )
        create_scopes(combinations, rule_type, user)
      end

      # Records the decision for the combinations that already carry rules, and
      # for no others.
      #
      # This is what the copy screen needs. WorkflowRule.copy_for_project writes
      # rules straight into a project, and without a scope the resolver would
      # ignore every one of them; but creating a scope where nothing was copied
      # would hand the project an *empty* workflow, which for transitions means
      # no issue in it can change status. So the scope follows the rows.
      def self.ensure_scopes_for_existing_rules(project_ids:, tracker_ids:, role_ids:, rule_type:, user: User.current)
        project_ids, tracker_ids, role_ids = normalize(project_ids, tracker_ids, role_ids)
        return [] if project_ids.empty? || tracker_ids.empty? || role_ids.empty?

        with_rules = ProjectWorkflowScope.rule_model_for(rule_type).where(
          project_id: project_ids, tracker_id: tracker_ids, role_id: role_ids
        ).distinct.pluck(:project_id, :tracker_id, :role_id).to_set
        return [] if with_rules.empty?

        missing = missing_combinations(
          project_ids: project_ids, tracker_ids: tracker_ids, role_ids: role_ids, rule_type: rule_type
        ).select { |triple| with_rules.include?(triple) }
        create_scopes(missing, rule_type, user)
      end

      # The copy screen's entry point: both rule types at once, because
      # WorkflowRule.copy_for_project moves both.
      def self.ensure_scopes_for_copy(project_ids:, tracker_ids:, role_ids:, user: User.current)
        ProjectWorkflowScope::RULE_TYPES.flat_map do |rule_type|
          ensure_scopes_for_existing_rules(
            project_ids: project_ids, tracker_ids: tracker_ids,
            role_ids: role_ids, rule_type: rule_type, user: user
          )
        end
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

          create_scopes(combinations, rule_type, user)
          # Defensive: a combination that inherits should carry no rules of its
          # own, but a database that predates the scope table may. Clearing
          # first makes the result of "enable" the same either way.
          delete_rules(combinations, rule_type)
          if copy_generic
            combinations.each do |project_id, tracker_id, role_id|
              WorkflowRule.copy_generic_to_project(project_id, tracker_id, role_id, sti_type)
            end
          end
          touched = combinations.size
        end
        # create_scopes already resets, but only when it created something, and
        # this action deletes and re-copies rules either way.
        Resolver.reset_cache! if touched.positive?
        touched
      end

      # Action two: return these projects to the generic workflow. The scope and
      # the rules both go; nothing about the project is left in the tables.
      def self.return_to_inheritance(project_ids:, tracker_ids:, role_ids:, rule_type:)
        touched = 0

        ProjectWorkflowScope.transaction do
          combinations = existing_combinations(
            project_ids: project_ids, tracker_ids: tracker_ids, role_ids: role_ids, rule_type: rule_type
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
          combinations = existing_combinations(
            project_ids: project_ids, tracker_ids: tracker_ids, role_ids: role_ids, rule_type: rule_type
          )
          next if combinations.empty?

          delete_rules(combinations, rule_type)
          # The relation covers exactly the combinations found above, because
          # those are the scopes this selection has. One statement rather than
          # one per scope: emptying a matrix for a wide selection is an ordinary
          # thing to do, and there is nothing here for a validation to check --
          # only the two audit columns change.
          scope_relation(project_ids, tracker_ids, role_ids, rule_type)
            .update_all( # rubocop:disable Rails/SkipsModelValidations
              updated_by_id: author_id_for(user), updated_at: Time.now.utc
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
      def self.existing_combinations(project_ids:, tracker_ids:, role_ids:, rule_type:)
        project_ids, tracker_ids, role_ids = normalize(project_ids, tracker_ids, role_ids)
        return [] if project_ids.empty? || tracker_ids.empty? || role_ids.empty?

        scope_relation(project_ids, tracker_ids, role_ids, rule_type)
          .pluck(:project_id, :tracker_id, :role_id)
      end

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

      def self.create_scopes(combinations, rule_type, user)
        return [] if combinations.empty?

        author_id = author_id_for(user)
        created = combinations.map do |project_id, tracker_id, role_id|
          ProjectWorkflowScope.create!(
            project_id: project_id, tracker_id: tracker_id, role_id: role_id,
            rule_type: rule_type, created_by_id: author_id, updated_by_id: author_id
          )
        end
        Resolver.reset_cache!
        created
      end
      private_class_method :create_scopes

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
