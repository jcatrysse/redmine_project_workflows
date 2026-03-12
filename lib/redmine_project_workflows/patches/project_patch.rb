# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module ProjectPatch
      def rolled_up_statuses
        @rolled_up_statuses ||= begin
          role_ids = Member.joins(:member_roles).where(project_id: self_and_descendants).distinct.pluck(:role_id)
          status_ids = RedmineProjectWorkflows::Services::StatusListQuery.status_ids_for_project(
            project: self,
            trackers: rolled_up_trackers,
            role_ids: role_ids
          )
          IssueStatus.where(id: status_ids).sorted
        end
      end
    end
  end
end
