# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module WorkflowTransitionPatch
      def replace_transitions(trackers, roles, transitions)
        RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions_for_project_id(
          nil,
          trackers,
          roles,
          transitions
        )
      end
    end
  end
end
