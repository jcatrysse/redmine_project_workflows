# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # Puts the plugin's matrix helper into the chain of Redmine's own workflow
    # controller (WP12, ADR-003).
    #
    # Nothing of core's is overridden here, so this is not a prepend. What it
    # exists for is `workflows/_form.html.erb`: core's transition grid, which
    # carries the plugin's two surviving Deface overrides on core's screens (the
    # row and column actions of WP5). Those call
    # `project_workflow_bulk_actions`, and Rails' `include_all_helpers` is built
    # from the host application's helper paths -- it never reaches a plugin's
    # `app/helpers`. Without this, **core's own workflow screen raises
    # NoMethodError**.
    #
    # It is also right on the merits rather than merely necessary. With no
    # project selection `project_workflow_selection_size` is `trackers x roles`,
    # which is exactly the count core's own `@roles.size * @trackers.size`
    # produces, so core's screen behaves identically -- and the row and column
    # actions are a real fix on it too, because core's own toggle selects on
    # `input[type=checkbox]` and cannot reach the `<select>` a mixed cell
    # renders as (claude F06).
    #
    # `controller.helper` rather than `WorkflowsHelper.prepend`, which is the
    # construct CLAUDE.md's forbidden-constructs table bans: a neighbouring
    # plugin's 2013-era `alias_method` chain on that module resolves the name
    # through `WorkflowsHelper.ancestors`, which with a prepend in place *starts*
    # at the prepended module -- so the neighbour copies our method and the copy's
    # `super` looks above `WorkflowsHelper`, where core's own method is not.
    # Reproduced on a running Redmine 5.1 as finding F01 of
    # 2026-08-28-claude-audit. A module in the controller's own `_helpers` sits
    # above `WorkflowsHelper` but not inside it, so no alias chain can reach it.
    #
    # The plugin's own screens declare `helper ProjectWorkflowMatrixHelper` in
    # their class bodies like any other Rails controller. Core's is the only one
    # that cannot, which is why this module exists at all.
    #
    # Including a module twice is a no-op, so a code reload is harmless.
    module WorkflowsControllerHelperPatch
      def self.apply!
        WorkflowsController.helper(ProjectWorkflowMatrixHelper)
        self
      end
    end
  end
end
