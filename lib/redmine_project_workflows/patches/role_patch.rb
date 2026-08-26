# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    module RolePatch
      # Core copies a role's workflow with WorkflowRule.copy, which sees the
      # generic rules only -- so a role copied from one that has project
      # overrides arrives without them, silently (claude F03). The copy has to
      # carry the project rules and the decisions that make them visible.
      #
      # Called from RolesController#create on a role that has just been saved,
      # and from nowhere else in core.
      def copy_workflow_rules(source_role)
        WorkflowRule.copy_with_projects(nil, source_role, nil, self)
      end
    end
  end
end
