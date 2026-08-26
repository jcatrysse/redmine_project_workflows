# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module ProjectPatch
      # Core's own body, with its one project-blind query replaced. Two things
      # the previous version of this patch got wrong:
      #
      # * It filtered by the roles that have members somewhere in the tree.
      #   Core has no role filter here, and adding one empties the status
      #   filter and the status report for every project without members --
      #   whether or not any override exists anywhere (external F08).
      # * It resolved the workflow against +self+ while collecting trackers
      #   from the whole tree, so a subproject's own workflow was read as if it
      #   were this project's. Nothing is inherited between projects (INV-6),
      #   so each project in the tree has to be resolved against itself and the
      #   results unioned.
      def rolled_up_statuses
        @rolled_up_statuses ||= begin
          status_ids = RedmineProjectWorkflows::Services::StatusListQuery.status_ids_for_pairs(
            pairs: rolled_up_project_tracker_ids
          )
          IssueStatus.where(id: status_ids).sorted
        end
      end

      # The (project, tracker) pairs that core's #rolled_up_trackers flattens
      # into trackers alone -- same base scope, so the same projects and the
      # same trackers, only not yet collapsed. One query.
      #
      # +sorted+ has to go: it orders by a column that DISTINCT does not
      # select, which PostgreSQL rejects outright.
      def rolled_up_project_tracker_ids
        rolled_up_trackers_base_scope
          .where("#{Project.table_name}.lft >= ? AND #{Project.table_name}.rgt <= ?", lft, rgt)
          .reorder(nil)
          .pluck("#{Project.table_name}.id", "#{Tracker.table_name}.id")
      end
    end
  end
end
