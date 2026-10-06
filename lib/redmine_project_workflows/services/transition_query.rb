# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # The transitions half of the resolver: which statuses an issue may move to.
    #
    # This replaces IssueStatus.new_statuses_allowed rather than falling back to
    # it. Core's query carries no project_id predicate, so it reads generic and
    # project rows together and would hand a project its neighbours' rules
    # (INV-4). Every scope built here names a project_id, nil included.
    class TransitionQuery
      # The two populations come from WorkflowPopulations rather than from a
      # base relation narrowed here and given a project_id on each branch
      # (finding F02 of 2026-08-28, second run). The answer is the same one --
      # every branch did add a project_id -- but the relation that had none
      # cannot be built here any more, so there is no half for a later edit to
      # execute by accident. An issue with no project reads the generic
      # workflow, unchanged: WorkflowPopulations says so in its own comment.
      #
      # Everything that is not the population split is added to what comes back,
      # never to the halves, because .or refuses a relation whose two sides have
      # already been narrowed differently. `(own OR generic) AND status AND
      # author/assignee` is the same set as the old `(status AND author/assignee
      # AND own) OR (status AND author/assignee AND generic)`.
      def self.allowed_statuses(issue:, user:, initial_status:, author:, assignee:)
        tracker = issue.tracker
        return [] unless tracker

        roles = issue.send(:roles_for_workflow, user)
        return [] if roles.empty?

        combined_scope = WorkflowPopulations.combined(
          model: WorkflowTransition, project_id: issue.project_id,
          tracker_id: tracker.id, role_ids: roles.map(&:id)
        )
        return [] if combined_scope.nil?

        combined_scope = combined_scope.where(old_status_id: initial_status&.id || 0)
        unless author && assignee
          combined_scope = if author || assignee
                             combined_scope.where('author = ? OR assignee = ?', author, assignee)
                           else
                             combined_scope.where(author: false, assignee: false)
                           end
        end

        # One statement, no join, no DISTINCT (finding F04). This used to be a
        # join *plus* a subquery against the same table -- one primary-key
        # lookup back into `workflows` per matching transition row, for an
        # answer `IN` already gives -- where core does one join with a WHERE.
        # This is the hottest path the plugin owns: Issue#safe_attributes= calls
        # new_statuses_allowed_to on every issue save, and the bulk-edit form,
        # the bulk-save loop and the context menu each fan it out once per
        # selected issue.
        #
        # `IN` is already a semi-join, so the DISTINCT was redundant.
        # +combined_scope+ is untouched, so every project_id predicate stays
        # exactly where it was (INV-4). A NULL new_status_id cannot produce a
        # false positive -- `id IN (NULL, 3)` is NULL, not true -- and
        # TransitionWriter whitelists new_status_id against IssueStatus ids
        # anyway, so the plugin cannot write one.
        #
        # Not `combined_scope.distinct.pluck(:new_status_id)` followed by a
        # second query: that adds a round trip on this path, and `pluck` on a
        # relation built with `.or()` takes on a PostgreSQL-only fragility the
        # day any default ordering appears on WorkflowRule.
        IssueStatus.where(id: combined_scope.select(:new_status_id)).to_a.sort
      end
    end
  end
end
