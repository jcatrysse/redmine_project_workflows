# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # Wraps the actions that ask every selected issue which statuses it may move
    # to, and which fields are read-only, in Services::WorkflowMemo.during.
    #
    # An around_action with a block rather than a method: nothing is mixed into
    # the controllers, so nothing becomes routable (forbidden-constructs table in
    # CLAUDE.md). Which controller serves the issue context menu is a version
    # fact, so it comes from the compatibility manifest.
    module MultiIssueActionsPatch
      MARKER = :@redmine_project_workflows_memo

      def self.apply!
        targets.each do |controller, actions|
          next if controller.instance_variable_get(MARKER)

          controller.around_action(only: actions) do |_controller, action|
            RedmineProjectWorkflows::Services::WorkflowMemo.during(&action)
          end
          controller.instance_variable_set(MARKER, true)
        end
        self
      end

      # [controller name, actions], the context menu's from the compatibility
      # manifest.
      def self.target_names
        menu, action = RedmineProjectWorkflows::Compatibility.issue_context_menu_action
        [[menu, [action]], ['IssuesController', %i[bulk_edit bulk_update]]]
      end

      def self.targets
        target_names.map { |name, actions| [name.constantize, actions] }
      end

      # Whether the wrap is on this controller -- what the diagnostics page asks.
      def self.attached?(controller)
        controller.instance_variable_get(MARKER) ? true : false
      end
    end
  end
end
