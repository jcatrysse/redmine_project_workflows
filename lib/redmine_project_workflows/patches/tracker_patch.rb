# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module TrackerPatch
      # The tracker half of RolePatch#copy_workflow_rules -- same defect, same
      # repair (claude F03). Called from TrackersController#create only.
      def copy_workflow_rules(source_tracker)
        WorkflowRule.copy_with_projects(source_tracker, nil, self, nil)
      end
    end
  end
end
