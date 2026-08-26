# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # The project settings tab.
    #
    # A patch on the helper rather than a Deface override, on purpose: the tab
    # list is data, so adding an entry to it is an append rather than a match
    # against rendered markup, and it lands in the tab strip without an anchor
    # to go stale (INV-9 exists because an unmatched anchor is silent).
    # +docs/design.md+ records the choice.
    #
    # The entry's +action+ is the controller action the tab leads to rather than
    # a permission name, because two permissions reach it: someone who may
    # manage this project's workflow must see the tab without also having to
    # hold the permission to view it. Redmine's +allowed_to?+ takes either
    # shape, and asking it about the action is asking exactly what the
    # controller will ask.
    module ProjectsHelperPatch
      TAB_ACTION = { controller: 'project_workflows', action: 'transitions' }.freeze
      TAB = {
        name: 'project_workflows',
        action: TAB_ACTION,
        module: :issue_tracking,
        partial: 'project_workflows/settings_tab',
        label: :label_workflow
      }.freeze

      def project_settings_tabs
        tabs = super
        # Core filters what it returns before returning it, so the plugin's
        # entry is filtered here the same way rather than appended past it.
        return tabs unless @project&.module_enabled?(TAB[:module])
        return tabs unless User.current.allowed_to?(TAB_ACTION, @project)

        tabs + [TAB.dup]
      end
    end
  end
end
