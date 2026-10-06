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
      # Core's Project#copy, remembering one thing and otherwise untouched.
      #
      # The workflow is copied by Hooks::ProjectCopyHook, from the
      # `model_project_copy_before_save` hook core calls inside this method --
      # which is the right place for it (inside core's own transaction, at the
      # point core chose) and which core hands **no options**. So the answer to
      # "was the workflow checkbox ticked" has to be carried the one step from
      # here to there.
      #
      # It is carried on the destination project itself rather than in
      # RedmineProjectWorkflows::Current or any other process-wide store: the
      # object is the one thing both halves already have, it cannot outlive the
      # copy, and two copies running on two threads cannot see each other's
      # answer. There is nothing to reset and nothing to leak.
      #
      # The rule is core's own, applied to one more name: no `:only` at all
      # means everything (a console or API `project.copy(source)`), and an
      # explicit list means exactly what it names.
      def copy(project, options = {})
        @copy_project_workflow = copy_project_workflow_requested?(options[:only])
        super
      end

      # Whether #copy was asked for the workflow. True when nothing asked --
      # a destination the hook reaches without #copy having run is not something
      # core can produce, and "no instruction means everything" is the same
      # default core applies to its own eight items.
      def copy_project_workflow?
        @copy_project_workflow.nil? || @copy_project_workflow
      end

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
      # Array.wrap rather than Array(), because Array() on a Hash yields its
      # pairs; and to_s on each entry, because a hand-built request can put a
      # number or a nested hash there. Anything that is not our key answers
      # false, so a malformed +only+ narrows the copy rather than widening it --
      # which is the same thing it does to core's own eight items.
      def copy_project_workflow_requested?(only)
        return true if only.nil?

        Array.wrap(only).map(&:to_s).include?(
          RedmineProjectWorkflows::Services::ProjectWorkflowCopier::COPY_ONLY_KEY
        )
      end
      private :copy_project_workflow_requested?

      def rolled_up_project_tracker_ids
        rolled_up_trackers_base_scope
          .where("#{Project.table_name}.lft >= ? AND #{Project.table_name}.rgt <= ?", lft, rgt)
          .reorder(nil)
          .pluck("#{Project.table_name}.id", "#{Tracker.table_name}.id")
      end
    end
  end
end
