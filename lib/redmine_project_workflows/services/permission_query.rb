# frozen_string_literal: true

module RedmineProjectWorkflows
  module Services
    # The field-permissions half of the resolver. Like TransitionQuery, it
    # replaces core's lookup instead of falling back to it: core queries
    # workflows without a project_id predicate (INV-4).
    class PermissionQuery
      def self.rules_for(issue:, user:, old_status_id:)
        roles = issue.send(:roles_for_workflow, user)
        return [] if roles.empty?

        role_ids = roles.map(&:id)
        resolver = Resolver.new(project_id: issue.project_id, tracker_id: issue.tracker_id, role_ids: role_ids)
        overridden_role_ids = resolver.overridden_role_ids_for(WorkflowPermission)
        global_role_ids = role_ids - overridden_role_ids

        base_scope = WorkflowPermission.where(tracker_id: issue.tracker_id, old_status_id: old_status_id)
        scopes = []
        if overridden_role_ids.any?
          scopes << base_scope.where(project_id: issue.project_id, role_id: overridden_role_ids)
        end
        if global_role_ids.any?
          scopes << base_scope.where(project_id: nil, role_id: global_role_ids)
        end
        return [] if scopes.empty?

        combined_scope = scopes.shift
        scopes.each { |scope| combined_scope = combined_scope.or(scope) }
        combined_scope.to_a
      end

      def self.rules_by_status_id_for_project(trackers, roles, project_ids)
        WorkflowPermission.where(
          tracker_id: trackers.map(&:id),
          role_id: roles.map(&:id),
          project_id: project_ids
        ).inject({}) do |hash, rule|
          hash[rule.old_status_id] ||= {}
          hash[rule.old_status_id][rule.field_name] ||= []
          hash[rule.old_status_id][rule.field_name] << rule.rule
          hash
        end
      end
    end
  end
end
