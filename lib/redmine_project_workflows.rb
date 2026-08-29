# frozen_string_literal: true

require_relative 'redmine_project_workflows/current'
# Before everything: the compatibility manifest owns every version fact, and
# VersionHelper is the first thing that asks it one (ADR-002).
require_relative 'redmine_project_workflows/compatibility'
require_relative 'redmine_project_workflows/version_helper'
require_relative 'redmine_project_workflows/services/core_method_digest'
require_relative 'redmine_project_workflows/bulk_actions_helper'
require_relative 'redmine_project_workflows/services/write_budget'
require_relative 'redmine_project_workflows/services/write_coordinator'
require_relative 'redmine_project_workflows/services/matrix_scope'
require_relative 'redmine_project_workflows/services/resolver'
require_relative 'redmine_project_workflows/services/workflow_populations'
require_relative 'redmine_project_workflows/services/transition_query'
require_relative 'redmine_project_workflows/services/permission_query'
require_relative 'redmine_project_workflows/services/matrix_save_result'
require_relative 'redmine_project_workflows/services/transition_writer'
require_relative 'redmine_project_workflows/services/permission_writer'
require_relative 'redmine_project_workflows/services/scope_combinations'
require_relative 'redmine_project_workflows/services/scope_writer'
require_relative 'redmine_project_workflows/services/scope_copier'
require_relative 'redmine_project_workflows/services/project_workflow_copier'
require_relative 'redmine_project_workflows/services/scope_state'
require_relative 'redmine_project_workflows/services/status_list_query'
require_relative 'redmine_project_workflows/services/inventory_query'
require_relative 'redmine_project_workflows/services/project_options'
require_relative 'redmine_project_workflows/services/transition_map_query'
require_relative 'redmine_project_workflows/services/workflow_graph_query'
require_relative 'redmine_project_workflows/services/workflow_graph_text'
require_relative 'redmine_project_workflows/services/workflow_graph_ranking'
require_relative 'redmine_project_workflows/services/workflow_graph_extent'
require_relative 'redmine_project_workflows/services/workflow_graph_layout'
require_relative 'redmine_project_workflows/workflow_selection'
require_relative 'redmine_project_workflows/copy_selection'
require_relative 'redmine_project_workflows/copy_scopes'
require_relative 'redmine_project_workflows/admin_matrix'
require_relative 'redmine_project_workflows/patches/issue_patch'
require_relative 'redmine_project_workflows/patches/issues_controller_patch'
require_relative 'redmine_project_workflows/patches/workflows_controller_patch'
require_relative 'redmine_project_workflows/patches/workflow_transition_patch'
require_relative 'redmine_project_workflows/patches/workflow_permission_patch'
require_relative 'redmine_project_workflows/patches/workflow_rule_patch'
require_relative 'redmine_project_workflows/patches/workflows_controller_helper_patch'
require_relative 'redmine_project_workflows/patches/project_patch'
require_relative 'redmine_project_workflows/patches/projects_helper_patch'
require_relative 'redmine_project_workflows/patches/role_patch'
require_relative 'redmine_project_workflows/patches/tracker_patch'
# The hook listener registers itself with Redmine::Hook the moment the class
# body is read, and `require` is a no-op the second time -- so a reload cannot
# register it twice. The same reasoning as the Deface overrides in init.rb.
require_relative 'redmine_project_workflows/hooks/project_copy_hook'
require_relative 'redmine_project_workflows/hooks/project_copy_form_hook'

module RedmineProjectWorkflows
  def self.load_deface_overrides!
    overrides_path = File.join(__dir__, 'redmine_project_workflows', 'overrides')
    files = Dir.glob(File.join(overrides_path, '**', '*.rb')).sort

    files.each do |file|
      require file
    rescue StandardError => e
      Rails.logger.error "[redmine_project_workflows] error loading #{file}: #{e.class} #{e.message}"
      raise
    end
  end

  # Called from a to_prepare hook, so it runs again after every code reload in
  # development. The guard makes a repeat application a no-op on a class that
  # was not reloaded; on one that was, the fresh class gets the prepend it
  # would otherwise have lost.
  def self.apply_patches
    prepend_once(Issue, Patches::IssuePatch)
    prepend_once(WorkflowsController, Patches::WorkflowsControllerPatch)
    prepend_once(WorkflowTransition.singleton_class, Patches::WorkflowTransitionPatch)
    prepend_once(WorkflowPermission.singleton_class, Patches::WorkflowPermissionPatch)
    prepend_once(WorkflowRule.singleton_class, Patches::WorkflowRulePatch)
    prepend_once(Project, Patches::ProjectPatch)
    # Deliberately not a prepend on ProjectsHelper -- see the patch: a
    # neighbouring plugin's alias chain would copy the prepended method and lose
    # its super, taking core's own tabs down with it.
    Patches::ProjectsHelperPatch.apply!
    # Nor a prepend: this only puts the plugin's issue-form helper into the
    # controller's helper chain, which Rails' include_all_helpers does not do
    # for a plugin's app/helpers. See the patch.
    Patches::IssuesControllerPatch.apply!
    # Nor a prepend: this only puts the plugin's matrix helper into core's
    # workflow controller's chain, which core's own workflows/_form needs since
    # the row and column actions of WP5 are rendered into it. See the patch.
    Patches::WorkflowsControllerHelperPatch.apply!
    prepend_once(Role, Patches::RolePatch)
    prepend_once(Tracker, Patches::TrackerPatch)
  end

  def self.prepend_once(target, patch)
    target.prepend(patch) unless target.ancestors.include?(patch)
  end
end
