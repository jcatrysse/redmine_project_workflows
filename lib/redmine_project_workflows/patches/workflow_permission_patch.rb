# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module WorkflowPermissionPatch
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
