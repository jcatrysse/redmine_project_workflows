# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module WorkflowPermissionPatch
      # Core's only caller is WorkflowsController#permissions, the generic
      # Fields permissions screen, and core's query has no project_id
      # predicate, so it mixed every project's rules into the generic matrix
      # (INV-4). Answered here, for the generic workflow, so that the action
      # itself can stay core's: another plugin wrapping it -- as
      # redmine_itil_priority does to add Impact and Urgency -- then runs,
      # which it did not while this plugin replaced the action without
      # `super` (decision q3, Jan 2026-10-07; finding C2).
      def rules_by_status_id(trackers, roles)
        RedmineProjectWorkflows::Services::PermissionQuery.rules_by_status_id_for_project(trackers, roles, [nil])
      end

      def replace_permissions(trackers, roles, permissions)
        RedmineProjectWorkflows::Services::PermissionWriter.replace_permissions_for_project_id(
          nil,
          trackers,
          roles,
          permissions
        )
      end
    end
  end
end
