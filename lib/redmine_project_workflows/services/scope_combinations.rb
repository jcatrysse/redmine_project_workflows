# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # A set of exact (project_id, tracker_id, role_id) triples, and the questions
    # the scope table can be asked about one.
    #
    # A set of triples is not a cross product, and that distinction is the whole
    # reason this exists. The older selections in ScopeWriter are three id lists
    # whose cross product *is* the selection, which is right for a matrix save --
    # the save really does rewrite every cell of it. The copy screen's selection
    # is not that shape: it acts on exact pairs and skips any whose source
    # resolves to the target itself, so asking the database about the cross
    # product and using the answer whole spoke for workflows the copy had never
    # been near (findings F03, F04).
    #
    # Read-only, and every query names its project ids (INV-4). One query per
    # question over the distinct ids of the set, narrowed back to the exact
    # triples in Ruby: a set of triples cannot be expressed as three id lists,
    # and one statement per triple would be a round trip per combination on a
    # screen whose selection can be every project on the installation.
    class ScopeCombinations
      # The triples, as ids, de-duplicated. A triple naming no project is the
      # generic workflow, which has no scope at all, so it is dropped rather
      # than turned into project 0.
      def self.normalize(combinations)
        Array(combinations).filter_map do |triple|
          triple = Array(triple)
          next unless triple.size == 3 && triple.none?(&:nil?)

          triple.map { |value| value.respond_to?(:id) ? value.id : value.to_i }
        end.uniq
      end

      # The triples one copy into one project acted on, from the [[tracker, role],
      # ...] pairs copy_for_project reports it copied. The generic workflow has no
      # scope, so a copy whose target is 'global' contributes none.
      def self.for_project(project_id, pairs)
        return [] unless project_id

        Array(pairs).map { |tracker, role| [project_id, tracker.id, role.id] }
      end

      # The combinations that carry rules of this type and have no scope for it:
      # the rows a copy has just written that the resolver would otherwise
      # ignore (INV-3). A combination the copy left with no rules is not here,
      # because a scope with no rules is an own *empty* workflow, which for
      # transitions stops every issue in the project from changing status.
      def self.with_rules_and_no_scope(combinations, rule_type)
        combinations = normalize(combinations)
        return [] if combinations.empty?

        scoped, with_rules = scope_and_rule_sets(combinations, rule_type)
        combinations.select { |triple| with_rules.include?(triple) && scoped.exclude?(triple) }
      end

      # How many of these combinations have a scope with no rules under it --
      # an own *empty* workflow, in which nothing at all is permitted -- counted
      # over both rule types.
      #
      # A replacing copy can produce one without anybody asking for it: it
      # deletes the target pair's rows of both rule types and then inserts
      # whatever the source has, so a source with no rules of one type leaves the
      # target's scope of that type standing and empty. That is a valid
      # configuration (ADR-001) rather than an error, and the copy is also how
      # somebody deliberately empties a project -- so the screen reports it
      # rather than refusing it (finding F03).
      def self.own_empty_count(combinations)
        combinations = normalize(combinations)
        return 0 if combinations.empty?

        ProjectWorkflowScope::RULE_TYPES.sum do |rule_type|
          scoped, with_rules = scope_and_rule_sets(combinations, rule_type)
          combinations.count { |triple| scoped.include?(triple) && with_rules.exclude?(triple) }
        end
      end

      # Which of these triples have a scope for this rule type, and which of them
      # carry at least one rule of it.
      def self.scope_and_rule_sets(combinations, rule_type)
        project_ids = combinations.map { |triple| triple[0] }.uniq
        tracker_ids = combinations.map { |triple| triple[1] }.uniq
        role_ids = combinations.map { |triple| triple[2] }.uniq
        [triples_of(ProjectWorkflowScope.where(rule_type: rule_type), project_ids, tracker_ids, role_ids),
         triples_of(ProjectWorkflowScope.rule_model_for(rule_type), project_ids, tracker_ids, role_ids)]
      end
      private_class_method :scope_and_rule_sets

      def self.triples_of(relation, project_ids, tracker_ids, role_ids)
        relation.where(project_id: project_ids, tracker_id: tracker_ids, role_id: role_ids)
                .distinct.pluck(:project_id, :tracker_id, :role_id).to_set
      end
      private_class_method :triples_of
    end
  end
end
