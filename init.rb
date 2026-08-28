# frozen_string_literal: true

Redmine::Plugin.register :redmine_project_workflows do
  name 'Redmine Project Workflows'
  author 'Jan Catrysse'
  description 'Project workflows for Redmine'
  url 'https://github.com/jcatrysse/redmine_project_workflows'
  version '0.1.6'
  # 5.1 rather than 5.0, and it is a **hard dependency**, not merely the oldest
  # version anyone has tested (finding F03). `Issue#roles_for_workflow` does not
  # exist before 5.1 -- core introduced it there, replacing
  # `user.admin ? Role.all.to_a : user.roles_for_project(project)` -- and
  # `TransitionQuery` calls it. Lowering this floor does not widen support, it
  # ships a NoMethodError on every issue save. CI running 5.1, 6.1 and 7.0 is the
  # separate, weaker claim.
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
  #
  # **The `_rules` suffix is not decoration.** These were `view_project_workflow`
  # and `manage_project_workflow` until 2026-08-28, and the second collided with
  # `redmine_custom_workflows`, which registers a permission of that exact name
  # with an empty action hash. Redmine keeps `AccessControl.@permissions` as a
  # flat array and `AccessControl.permission(name)` returns the **first** match;
  # plugins load in alphabetical directory order, so the neighbour won and every
  # write action of this plugin answered 403 -- administrators included, because
  # `Project#allows_to?` is consulted before `User#allowed_to?` reaches its
  # `return true if admin?`. Nothing warned: the losing registration is silent.
  # Measured on a 45-plugin Redmine 5.1 host on 2026-08-28
  # (`docs/review/findings/2026-08-28-claude-plugin-compat-5.1.md`, F01), and
  # answered **B** by Jan the same day -- rename both, so the pair stays
  # symmetric and the names say what they govern: this project's workflow
  # *rules*, not the workflow feature. Migration 006 carries existing grants
  # across. **Do not shorten either name back.**
  # The one administration entry point this plugin has, and the first of the two
  # ADR-003 accepts. `Redmine::MenuManager.map :admin_menu` is a stable
  # extension point on all three supported versions, so an administration screen
  # of the plugin's own needs no Deface override to be reachable (INV-9 stays at
  # fifteen).
  #
  # Administrator-only twice over: Redmine renders the admin menu only for
  # administrators, and the controller requires one itself -- a menu that is not
  # drawn is not an authorization.
  # Both the sprite name and the CSS class, exactly as core's own eleven entries
  # pass them: 6.0 and later read `:icon` and draw `sprite_icon(name)` from
  # core's own sheet -- `summary` is in it on 6.1 and 7.0 -- while 5.1's
  # MenuItem ignores the option entirely and draws the picture behind
  # `.icon-summary`, which its stylesheet defines. Deliberately no `plugin:`
  # option: that would send `sprite_icon` looking for a sheet in this plugin's
  # assets, and this plugin ships none.
  menu :admin_menu, :project_workflow_diagnostics,
       { controller: 'project_workflow_diagnostics', action: 'show' },
       caption: :label_project_workflow_diagnostics,
       icon: 'summary',
       html: { class: 'icon icon-summary' }

  project_module :issue_tracking do
    permission :view_project_workflow_rules,
               { projects: :settings,
                 project_workflows: %i[transitions permissions compare graph] },
               read: true
    permission :manage_project_workflow_rules,
               { projects: :settings,
                 project_workflows: %i[transitions permissions compare graph update_transitions
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

# ADR-002's three states, resolved once per process and only ever spoken about
# in the log. A verified Redmine says nothing and measures nothing; an
# unverified one measures what the plugin copied from core and says whether any
# of it has changed.
#
# After apply_patches deliberately: every class the measurement reads is one the
# patches have just referenced, so this triggers no autoload of its own -- and on
# a verified host it does not measure at all.
RedmineProjectWorkflows::Compatibility.announce!

# Deface registers its overrides with Deface rather than on a host class, and
# `require` is a no-op the second time, so these are loaded once.
RedmineProjectWorkflows.load_deface_overrides!
