# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module ProjectPatch
      def rolled_up_statuses
        status_ids = RedmineProjectWorkflows::Services::StatusListQuery.status_ids_for_project(
          project: self,
          trackers: rolled_up_trackers
        )
        IssueStatus.where(id: status_ids).sorted
      end
    end
  end
end
