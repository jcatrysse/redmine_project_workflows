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
    #
    # It used to carry #writable_pairs as well -- "which pairs may this write
    # touch, with their rows locked". That is Services::WriteCoordinator since
    # WP13, which is the one place both populations' locking policy now lives;
    # the writers call it by name rather than through a delegation here, so that
    # the thing deciding is the thing named at the call site.
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
    end
  end
end
