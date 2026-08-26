# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # The settings tab's data.
    #
    # Redmine's tab strip renders every tab's partial on every visit to the
    # settings page -- +showTab+ only hides and shows what is already there --
    # so this runs whenever someone with the permission opens project settings.
    # It is InventoryQuery over a single project: four queries whatever the
    # number of trackers and roles, and none of them per row (G6).
    #
    # +settings+ is patched rather than a before_action added, because core's
    # +update+ calls the +settings+ method itself and then renders its view; a
    # callback would have left the tab without its data on a failed save.
    module ProjectsControllerPatch
      def self.prepended(base)
        # Rails' include_all_helpers is built from the host application's helper
        # paths, so a plugin helper has to be named even though Zeitwerk loads
        # it perfectly well.
        base.helper(ProjectWorkflowsHelper)
      end

      def settings
        super
        return if performed?

        load_project_workflow_tab
      end

      private

      def load_project_workflow_tab
        @project_workflow_rows = nil
        # The same question ProjectsHelperPatch asks before it adds the tab, and
        # the same one ProjectWorkflowsController asks before it answers: either
        # permission reaches this screen.
        return unless User.current.allowed_to?(ProjectsHelperPatch::TAB_ACTION, @project)

        trackers = RedmineProjectWorkflows::Services::ProjectOptions.trackers(@project)
        roles = RedmineProjectWorkflows::Services::ProjectOptions.roles(@project)
        @project_workflow_rule_types = ProjectWorkflowScope::RULE_TYPES
        query = RedmineProjectWorkflows::Services::InventoryQuery.new(
          projects: [@project], trackers: trackers, roles: roles,
          rule_types: @project_workflow_rule_types, deviations_only: false
        )
        # The whole list, not a page: it is one project's own trackers times the
        # roles somebody holds in it, and the tab is where you go to see all of
        # them at once. The administration inventory is the paged screen.
        @project_workflow_rows = query.rows(offset: 0, limit: query.total)
      end
    end
  end
end
