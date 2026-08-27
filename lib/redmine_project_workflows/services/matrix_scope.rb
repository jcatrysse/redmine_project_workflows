# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # The one predicate both rule writers need, in one place so they cannot
    # disagree about it.
    #
    # A matrix save used to name its trackers and its roles as two lists and let
    # the database take the cross product. It cannot any more: a selection can be
    # writable for one role of a tracker and not for the next, because a project
    # takes a workflow over per (tracker, role) and a combination that still
    # inherits is left alone (INV-3). So the predicate is an OR of the exact
    # pairs -- grouped by tracker, which makes a full selection one branch per
    # tracker rather than one per combination.
    #
    # Extended into the two writers, each of which answers +rule_model+ with the
    # workflow class it writes.
    module MatrixScope
      # +pairs+ is [[tracker, role], ...] of records, as the writers hold them.
      def pair_predicate(pairs)
        table = rule_model.arel_table
        conditions = pairs.group_by { |tracker, _role| tracker.id }.map do |tracker_id, tracker_pairs|
          table[:tracker_id].eq(tracker_id)
                            .and(table[:role_id].in(tracker_pairs.map { |_tracker, role| role.id }))
        end
        conditions.reduce { |memo, condition| memo.or(condition) }
      end

      # The (tracker, role) pairs of this selection that the project has taken
      # over, in the order the caller listed them. Every pair for a generic
      # write, which has no scope and cannot be inherited.
      #
      # The scope rows are *locked* (`lock: true`), and both callers ask inside
      # the transaction that then writes the rules. Reading them without the
      # lock made the answer a snapshot: a project could own its workflow when
      # the question was asked and be back on the generic one by the time the
      # rules were written, and those rules stayed in the table under no scope,
      # invisible to the resolver, after a save that had said it succeeded.
      # With the lock the two are one decision -- the concurrent return to the
      # generic workflow either finishes first, and the pair is skipped and
      # reported skipped, or it waits for this write and then removes both.
      def writable_pairs(project_id, trackers, roles, rule_type)
        all_pairs = trackers.product(roles)
        return all_pairs if project_id.nil?

        scoped = ScopeWriter.existing_combinations(
          project_ids: [project_id], tracker_ids: trackers.map(&:id), role_ids: roles.map(&:id),
          rule_type: rule_type, lock: true
        ).to_set
        all_pairs.select { |tracker, role| scoped.include?([project_id.to_i, tracker.id, role.id]) }
      end
    end
  end
end
