# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # Which projects a status deletion would leave with an own **empty**
    # workflow (audit finding F03).
    #
    # Core deletes every workflow row naming a status being destroyed, across
    # both populations and with no project predicate. That is core's business
    # and it is right. What core cannot know is that this plugin's *scope* row
    # survives the deletion, and a scope with no rules is not "nothing here" --
    # it is an own empty workflow, which for transitions permits no change of
    # status at all (INV-3). A status deletion can therefore move a project from
    # "own workflow with N transitions" to "deny everything", silently.
    #
    # **This service only counts; it changes nothing.** Deleting the emptied
    # scope would return the combination to the generic workflow, which collapses
    # two of INV-3's three meanings on the administrator's behalf -- the exact
    # defect the scope model exists to prevent. So the deletion goes through
    # untouched and the administrator is told what it did (Patches::
    # IssueStatusesControllerPatch).
    #
    # Cost: two statements, whatever the size of the installation. One grouped
    # pass over the project population of +workflows+, and one lookup of the
    # scopes for the combinations that pass it. Both carry an explicit project
    # predicate (INV-4): +project_id IS NOT NULL+ is the project population, the
    # same predicate WorkflowRule.delete_duplicate_rules! sweeps it with.
    class StatusDeletionImpact
      # One (project, tracker, role, rule type) that holds rules today and would
      # hold none after the deletion.
      Combination = Struct.new(:project_id, :tracker_id, :role_id, :rule_type, keyword_init: true)

      # What the deletion of +status_id+ would leave behind.
      #
      # +combinations+ are only those that have a scope: a project rule row with
      # no scope over it is invisible to the resolver (INV-3), so counting one
      # would report a workflow that is not in force.
      Result = Struct.new(:combinations, keyword_init: true) do
        # Struct's own #any? and #count answer about the struct's *members*,
        # which is one whatever the deletion found. Delegating them is what makes
        # `impact.count` the number of emptied workflows rather than 1.
        delegate :any?, :count, to: :combinations

        def project_ids
          combinations.map(&:project_id).uniq
        end
      end

      def self.of(status_id)
        new(status_id).result
      end

      def initialize(status_id)
        @status_id = Integer(status_id)
      end

      def result
        Result.new(combinations: scoped(emptied_by_deletion))
      end

      private

      attr_reader :status_id

      # The project combinations whose every rule names the status. Expressed as
      # one grouped pass rather than "the ones that name it" minus "the ones with
      # a survivor", which is two scans of the same table and a set difference in
      # Ruby.
      #
      # `COUNT(*) = SUM(CASE ...)` needs no `> 0` beside it: a group produced by
      # GROUP BY has at least one row, so equality already implies the group
      # names the status. `SUM(CASE WHEN ... THEN 1 ELSE 0 END)` rather than
      # `COUNT(*) FILTER` or `COUNT(IF(...))`, because it is the one spelling
      # PostgreSQL, MySQL and MariaDB all read.
      #
      # Neither status column is nullable -- core's own migration declares both
      # `null: false`, with 0 standing for "new issue" on a transition and for
      # "no target status" on a permission -- so plain equality is the whole
      # test and there is no NULL branch to get wrong.
      def emptied_by_deletion
        WorkflowRule
          .where.not(project_id: nil)
          .group(:project_id, :tracker_id, :role_id, :type)
          .having(
            'COUNT(*) = SUM(CASE WHEN old_status_id = :id OR new_status_id = :id THEN 1 ELSE 0 END)',
            id: status_id
          )
          .pluck(:project_id, :tracker_id, :role_id, :type)
          .filter_map { |project_id, tracker_id, role_id, type| combination_for(project_id, tracker_id, role_id, type) }
      end

      # A row whose STI class is neither of the two the plugin knows is not a
      # rule type it can name a scope for; there is no such class in Redmine
      # today, and inventing a scope for one would be worse than ignoring it.
      def combination_for(project_id, tracker_id, role_id, type)
        rule_type = ProjectWorkflowScope::RULE_TYPE_BY_MODEL_NAME[type]
        return nil unless rule_type

        Combination.new(project_id: project_id, tracker_id: tracker_id, role_id: role_id, rule_type: rule_type)
      end

      # Only the combinations a scope makes real, matched on the whole key. The
      # lookup is one query over the projects involved and the comparison is an
      # exact tuple: a scope for the same project and tracker under a *different*
      # role must not answer for this one.
      def scoped(combinations)
        return [] if combinations.empty?

        keys = ProjectWorkflowScope
               .where(project_id: combinations.map(&:project_id).uniq,
                      tracker_id: combinations.map(&:tracker_id).uniq,
                      role_id: combinations.map(&:role_id).uniq,
                      rule_type: combinations.map(&:rule_type).uniq)
               .pluck(:project_id, :tracker_id, :role_id, :rule_type)
               .to_set

        combinations.select do |combination|
          keys.include?([combination.project_id, combination.tracker_id, combination.role_id, combination.rule_type])
        end
      end
    end
  end
end
