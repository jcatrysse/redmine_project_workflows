# frozen_string_literal: true

require_relative 'redmine_project_workflows/services/resolver'
require_relative 'redmine_project_workflows/services/transition_query'
require_relative 'redmine_project_workflows/services/permission_query'
require_relative 'redmine_project_workflows/services/transition_writer'
require_relative 'redmine_project_workflows/services/permission_writer'
require_relative 'redmine_project_workflows/services/status_list_query'
require_relative 'redmine_project_workflows/patches/issue_patch'
require_relative 'redmine_project_workflows/patches/workflows_controller_patch'
require_relative 'redmine_project_workflows/patches/workflow_transition_patch'
require_relative 'redmine_project_workflows/patches/workflow_permission_patch'
require_relative 'redmine_project_workflows/patches/workflow_rule_patch'
require_relative 'redmine_project_workflows/patches/workflows_helper_patch'
require_relative 'redmine_project_workflows/patches/project_patch'

module RedmineProjectWorkflows
  def self.load_deface_overrides!
    overrides_path = File.join(__dir__, 'redmine_project_workflows', 'overrides')
    files = Dir.glob(File.join(overrides_path, '**', '*.rb')).sort

    files.each do |file|
      load file
    rescue => e
      Rails.logger.error "[redmine_project_workflows] error loading #{file}: #{e.class} #{e.message}"
      raise
    end
  end

  def self.apply_patches
    Issue.prepend(RedmineProjectWorkflows::Patches::IssuePatch)
    WorkflowsController.prepend(RedmineProjectWorkflows::Patches::WorkflowsControllerPatch)
    WorkflowTransition.singleton_class.prepend(RedmineProjectWorkflows::Patches::WorkflowTransitionPatch)
    WorkflowPermission.singleton_class.prepend(RedmineProjectWorkflows::Patches::WorkflowPermissionPatch)
    WorkflowRule.singleton_class.prepend(RedmineProjectWorkflows::Patches::WorkflowRulePatch)
    WorkflowsHelper.prepend(RedmineProjectWorkflows::Patches::WorkflowsHelperPatch)
    Project.prepend(RedmineProjectWorkflows::Patches::ProjectPatch)
  end
end
