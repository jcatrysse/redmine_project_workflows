# frozen_string_literal: true

Redmine::Plugin.register :redmine_project_workflows do
  name 'Redmine Project Workflows'
  author 'Jan Catrysse'
  description 'Project workflows for Redmine'
  url 'https://github.com/jcatrysse/redmine_project_workflows'
  version '0.1.3'
  # 5.1 rather than 5.0: CI runs 5.1, 6.1 and 7.0 and nothing has ever tested
  # 5.0, so declaring it was a claim with nothing behind it.
  #
  # A floor is all Redmine offers, and it is weaker than the claim it looks like:
  # 5.2, 6.0, 6.2 and 7.1 still install, and none of those is in CI either. What
  # this stops is the one version below everything the plugin has ever run on.
  # The README's Compatibility section is where the real answer lives.
  # Reverting this is one line.
  requires_redmine version_or_higher: '5.1'

  # WP5. The plugin's first setting, and the reason it has a settings screen at
  # all: a row or column action on an administration matrix can write a great
  # many rules from one click, and how many is "many" depends on the
  # installation. Above this number the action asks first; 0 asks every time.
  #
  # The same number is the fallback in
  # RedmineProjectWorkflows::BulkActionsHelper::DEFAULT_BULK_CONFIRM_THRESHOLD,
  # which is what answers for a settings hash saved before this key existed.
  # spec/plugin_conventions_spec.rb asserts the two agree.
  settings default: { 'bulk_confirm_threshold' => '50' },
           partial: 'settings/redmine_project_workflows'

  # WP4. Both permissions map projects#settings, because that is the action the
  # settings tab is rendered from: without it a role that may read its own
  # project's workflow could not open the page the tab lives on. Redmine's own
  # :manage_categories is declared exactly this way.
  #
  # The screens themselves are the plugin's, under /projects/:project_id/workflow,
  # and every one of them authorizes against the project in its own path
  # (INV-7). The administration screens stay administrator-only.
  project_module :issue_tracking do
    permission :view_project_workflow,
               { projects: :settings,
                 project_workflows: %i[transitions permissions compare] },
               read: true
    permission :manage_project_workflow,
               { projects: :settings,
                 project_workflows: %i[transitions permissions compare update_transitions
                                       update_permissions enable inherit clear] },
               require: :member
  end
end

begin
  require 'deface'
rescue LoadError => e
  raise LoadError, "redmine_project_workflows requires deface: #{e.message}"
end
require_relative 'lib/redmine_project_workflows'

# Applied here, in the body of init.rb, and deliberately not from a hook.
#
# Redmine's PluginLoader loads every init.rb from inside a to_prepare block, so
# this file is re-executed after each code reload and the prepends land on the
# classes the reload has just produced -- which is exactly what a to_prepare
# hook is for.
#
# Registering one would not work: Rails::Application::Configuration#to_prepare
# only appends to config.to_prepare_blocks, and the initializer that wires that
# array into the reloader (:add_to_prepare_blocks) has already run by the time
# any plugin's init.rb is loaded. A block registered here is never called, and
# the whole plugin silently does nothing.
#
# config.after_initialize would work -- on a reload the :after_initialize load
# hook has already fired, so the block runs immediately -- but it says the
# opposite of what happens, and it registers a further callback on every
# reload.
RedmineProjectWorkflows.apply_patches

# Deface registers its overrides with Deface rather than on a host class, and
# `require` is a no-op the second time, so these are loaded once.
RedmineProjectWorkflows.load_deface_overrides!
