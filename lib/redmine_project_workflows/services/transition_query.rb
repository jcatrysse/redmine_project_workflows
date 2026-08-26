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
      def self.allowed_statuses(issue:, user:, initial_status:, author:, assignee:)
        tracker = issue.tracker
        return [] unless tracker

        roles = issue.send(:roles_for_workflow, user)
        return [] if roles.empty?

        role_ids = roles.map(&:id)
        resolver = Resolver.new(project_id: issue.project_id, tracker_id: tracker.id, role_ids: role_ids)
        overridden_role_ids = resolver.overridden_role_ids_for(WorkflowTransition)
        global_role_ids = role_ids - overridden_role_ids

        status_id = initial_status&.id || 0
        workflow_scope = WorkflowTransition.where(tracker_id: tracker.id, old_status_id: status_id)
        unless author && assignee
          workflow_scope = if author || assignee
                             workflow_scope.where('author = ? OR assignee = ?', author, assignee)
                           else
                             workflow_scope.where(author: false, assignee: false)
                           end
        end

        scopes = []
        if overridden_role_ids.any?
          scopes << workflow_scope.where(project_id: issue.project_id, role_id: overridden_role_ids)
        end
        scopes << workflow_scope.where(project_id: nil, role_id: global_role_ids) if global_role_ids.any?
        return [] if scopes.empty?

        combined_scope = scopes.shift
        scopes.each { |scope| combined_scope = combined_scope.or(scope) }

        IssueStatus
          .joins(:workflow_transitions_as_new_status)
          .where(WorkflowTransition.table_name => { id: combined_scope.select(:id) })
          .distinct
          .to_a
          .sort
      end
    end
  end
end
