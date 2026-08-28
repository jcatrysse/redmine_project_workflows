# frozen_string_literal: true

module RedmineProjectWorkflows
  module Patches
    # The project settings tab.
    #
    # Redmine offers no hook for adding one -- `project_settings_tabs` builds a
    # literal array and filters it -- so the list is extended by overriding the
    # method and calling `super`. Where that override is *attached* is the
    # load-bearing part; see {apply!}. The filtering is repeated here because
    # `super` has already applied it to core's own tabs by the time this one is
    # appended: the project module has to be enabled and the viewer has to be
    # allowed the action the tab leads to.
    #
    # A hidden tab is not authorization. `ProjectWorkflowsController` checks
    # again, per action, against the project in its own path (INV-7).
    #
    # Not a Deface override either: the tab list is data, so adding an entry to
    # it is an append rather than a match against rendered markup, with no
    # anchor to go stale (INV-9 exists because an unmatched anchor is silent).
    module ProjectsHelperPatch
      # The entry names the controller action it leads to rather than a
      # permission, because two permissions reach it and somebody who may
      # *manage* this project's workflow must see the tab without also holding
      # the permission to *view* it. Redmine's `allowed_to?` takes either shape,
      # and asking it about the action asks exactly what the controller will.
      TAB_ACTION = { controller: 'project_workflows', action: 'transitions' }.freeze
      TAB = {
        name: 'project_workflows',
        action: TAB_ACTION,
        module: :issue_tracking,
        partial: 'project_workflows/settings_tab',
        label: :label_workflow
      }.freeze

      class << self
        # Attach to the **controller's** helper chain, never to `ProjectsHelper`
        # itself. This is not a style preference; `ProjectsHelper.prepend(self)`
        # is a measured bug, and the plugin used it until Jan pointed at how
        # `redmine_ai_triage` solved the same problem (its K-29).
        #
        # Many Redmine plugins take `project_settings_tabs` over with a classic
        # alias chain -- `alias_method :x_without_y, :x` then
        # `alias_method :x, :x_with_y` -- and plugins load alphabetically, so
        # some of them run after this one. `alias_method` resolves the name
        # through `ProjectsHelper.ancestors`, which with a prepend in place
        # *starts* at the prepended module: the neighbour therefore copies **our**
        # method into its `_without_` alias, and that copy's `super` looks above
        # `ProjectsHelper`, where nothing answers. Core's own method drops out of
        # the chain and every project's settings page raises `NoMethodError`.
        #
        # `ProjectsController.helper` avoids it by construction. The override
        # lands in `ProjectsController._helpers` -- above `ProjectsHelper` but
        # not inside it -- so no alias chain can copy it, and `super` always
        # reaches whatever `ProjectsHelper` holds: core's method, or a
        # neighbour's aliased version, in either load order. Applying later
        # would fix one load order and leave the trap for the other.
        #
        # **Measured, not argued.** On 2026-08-28 this was tried both ways on a
        # running Redmine 5.1 carrying 44 other plugins: with
        # `ProjectsController.helper` the settings page renders 27 tabs from 15
        # plugins; with `ProjectsHelper.prepend(self)` the same page is an HTTP
        # **500**, `NoMethodError: super: no superclass method
        # 'project_settings_tabs'`. The neighbour that springs it is
        # `redmine_wiki_extensions`, which sorts after this plugin and takes the
        # method over with a classic alias chain. Finding F03 of
        # `docs/review/findings/2026-08-28-claude-plugin-compat-5.1.md`.
        #
        # Referencing the controller constant autoloads it, which is what puts
        # `ProjectsHelper` in the chain before us -- the order this needs.
        # Including a module twice is a no-op, so a code reload is harmless.
        #
        # What this narrows, stated rather than left implicit: the tab now
        # reaches `projects/settings` through `ProjectsController` only. A plugin
        # rendering that view from a controller of its own would not see it --
        # and would not see core's own tabs either, since the view reads
        # `@project` straight from `ProjectsController`.
        def apply!
          ProjectsController.helper(ProjectWorkflowsHelper)
          # The settings tab offers WP9's drawing per row, and that link and its
          # gate live in a helper of their own. Named here for the same reason
          # ProjectWorkflowsHelper is: Rails' include_all_helpers is built from
          # the host application's helper paths and does not reach a plugin's
          # app/helpers, so a partial rendered by *core's* controller sees only
          # what is named here.
          ProjectsController.helper(ProjectWorkflowGraphsHelper)
          ProjectsController.helper(self)
          self
        end

        # `project` is the settings page's own project. Nil is possible only if
        # the helper is called outside that page, and then the plugin adds
        # nothing rather than raising.
        def tab_for(project)
          return [] if project.nil?
          return [] unless project.module_enabled?(TAB[:module])
          return [] unless User.current.allowed_to?(TAB_ACTION, project)

          [TAB.dup]
        end
      end

      def project_settings_tabs
        super + RedmineProjectWorkflows::Patches::ProjectsHelperPatch.tab_for(@project)
      end
    end
  end
end
