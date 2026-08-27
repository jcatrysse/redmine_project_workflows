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
      #
      # Two divergences from core that "core's own body" does not cover, named
      # here because a reviewer found them absent (finding F18):
      #
      # * The result is **memoised** and core's is not. Defensible rather than
      #   accidental: core reserves and clears this same ivar in Project#reload
      #   on 5.1, 6.1 and 7.0, so the memo is invalidated where core expects it
      #   to be. It is worth having because the plugin's replacement query is
      #   an OR with a branch per overriding (project, tracker) pair, and this
      #   method fills the status filter and the status report on a project
      #   issue list.
      # * #rolled_up_project_tracker_ids below is a **new public method on
      #   Project**, not a core one with a body replaced. Public because the
      #   query service is the caller; there is no core method of that name to
      #   collide with on any supported version.
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
