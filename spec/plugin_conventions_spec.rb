# frozen_string_literal: true

#
# That the plugin is actually installed into the host it is running in, and the
# conventions that keep it that way.
#
require_relative 'spec_helper'

describe RedmineProjectWorkflows do
  it 'prepends a patch once, and only to a target that does not already have it' do
    target = Class.new
    patch = Module.new

    described_class.prepend_once(target, patch)
    described_class.prepend_once(target, patch)

    expect(target.ancestors).to include(patch)
    expect(target.ancestors.count { |ancestor| ancestor == patch }).to eq(1)
  end

  # WP0 / claude F05. The suite boots a real Redmine and applies nothing of its
  # own, so this is the assertion that the plugin is installed at all. It is
  # what catches an init.rb that registers its patches somewhere Rails never
  # calls -- Rails::Application::Configuration#to_prepare only appends to an
  # array that the :add_to_prepare_blocks initializer has already consumed by
  # the time any plugin's init.rb is loaded, so such a block never runs and
  # every patch below is missing.
  it 'is patched into the host that booted this suite' do
    expect(Issue.ancestors).to include(RedmineProjectWorkflows::Patches::IssuePatch)
    expect(WorkflowsController.ancestors).to include(RedmineProjectWorkflows::Patches::WorkflowsControllerPatch)
    expect(WorkflowsHelper.ancestors).to include(RedmineProjectWorkflows::Patches::WorkflowsHelperPatch)
    expect(Project.ancestors).to include(RedmineProjectWorkflows::Patches::ProjectPatch)
    expect(WorkflowTransition.singleton_class.ancestors).to include(RedmineProjectWorkflows::Patches::WorkflowTransitionPatch)
    expect(WorkflowPermission.singleton_class.ancestors).to include(RedmineProjectWorkflows::Patches::WorkflowPermissionPatch)
    expect(WorkflowRule.singleton_class.ancestors).to include(RedmineProjectWorkflows::Patches::WorkflowRulePatch)
    # The settings tab is the one patch that is deliberately *not* a prepend --
    # see Patches::ProjectsHelperPatch#apply!, and the alias-chain examples in
    # spec/controllers/projects_settings_tab_spec.rb. It has to be in the
    # controller's helper chain, and nowhere near ProjectsHelper itself.
    expect(ProjectsController._helpers.ancestors)
      .to include(RedmineProjectWorkflows::Patches::ProjectsHelperPatch)
    expect(ProjectsHelper.ancestors)
      .not_to include(RedmineProjectWorkflows::Patches::ProjectsHelperPatch)
  end

  # WP4. The permissions are declared inside Redmine::Plugin.register, which is
  # a different mechanism from the patches above and fails differently: a
  # permission that never reaches Redmine::AccessControl cannot be granted to
  # any role, so the settings tab would be invisible to everyone but an
  # administrator and no spec that logs one in would notice.
  it 'registers its two project permissions under the issue tracking module' do
    %i[view_project_workflow manage_project_workflow].each do |name|
      permission = Redmine::AccessControl.permission(name)

      expect(permission).not_to be_nil, "#{name} is not registered"
      expect(permission.project_module).to eq(:issue_tracking)
      # Both have to reach projects#settings: that is the action the tab is
      # rendered from, so without it a role holding only one of them could not
      # open the page the tab lives on.
      expect(permission.actions).to include('projects/settings')
      expect(permission.actions).to include('project_workflows/transitions')
    end
  end

  it 'lets only the managing permission write' do
    view = Redmine::AccessControl.permission(:view_project_workflow)
    manage = Redmine::AccessControl.permission(:manage_project_workflow)

    expect(view.actions).not_to include('project_workflows/update_transitions')
    expect(view.actions).not_to include('project_workflows/enable')
    expect(manage.actions).to include('project_workflows/update_transitions')
    expect(manage.actions).to include('project_workflows/update_permissions')
    %w[enable inherit clear].each do |action|
      expect(manage.actions).to include("project_workflows/#{action}")
    end
  end

  # Reading a workflow is a read action, so it goes on working in a closed
  # project; managing one is not, so it stops there.
  it 'marks viewing as a read action and managing as a write' do
    expect(Redmine::AccessControl.permission(:view_project_workflow)).to be_read
    expect(Redmine::AccessControl.permission(:manage_project_workflow)).not_to be_read
    expect(Redmine::AccessControl.permission(:manage_project_workflow)).to be_require_member
  end
end

describe 'the invisible custom field role map' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles,
           :enumerations

  let(:issue) { Issue.new(project: projects(:projects_001), tracker: trackers(:trackers_001)) }

  after { RedmineProjectWorkflows::Current.reset }

  # WP0 / external F09. A threaded application server reuses a thread across
  # requests, so a Thread.current cache outlives the request that filled it and
  # a configuration change is not seen until the thread is recycled. The review
  # called that branch dead code because Redmine bundles request_store -- true
  # up to 6.1, but Redmine 7.0 dropped the gem, so on 7.0 it was the only path
  # the cache ever took. See RedmineProjectWorkflows::Current.
  #
  # The point of the cache is that it lasts exactly one request: long enough
  # that rendering many issues costs one query rather than one per issue, and
  # no longer, so an administrator's change to a custom field is visible on the
  # next request rather than when the server happens to recycle the thread.
  it 'is cached within one request and not beyond it' do
    field = IssueCustomField.create!(name: 'Invisible map spec field', field_format: 'string',
                                     visible: false, role_ids: [roles(:roles_001).id])

    expect(issue.send(:invisible_custom_field_role_map)).to have_key(field.id)

    field.destroy!
    expect(issue.send(:invisible_custom_field_role_map)).to have_key(field.id)

    RedmineProjectWorkflows::Current.reset
    expect(Issue.new(project: projects(:projects_001), tracker: trackers(:trackers_001))
                .send(:invisible_custom_field_role_map)).not_to have_key(field.id)
  end
end
