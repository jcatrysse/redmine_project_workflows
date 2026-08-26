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

  # A prepended patch that reimplements a core method inherits none of core's
  # own visibility declarations. Core says `private :workflow_rule_by_attribute`
  # right after its definition, and the patch's copy was public -- which widens
  # core's API on every host the plugin is installed on, quietly.
  it 'keeps core\'s visibility on the methods it reimplements' do
    expect(Issue.private_method_defined?(:workflow_rule_by_attribute)).to be(true)
    expect(Issue.public_method_defined?(:workflow_rule_by_attribute)).to be(false)
    # The other two are public in core and have to stay so.
    expect(Issue.public_method_defined?(:new_statuses_allowed_to)).to be(true)
    expect(Issue.public_method_defined?(:tracker=)).to be(true)
  end

  # The plugin injects a call to one of its own helpers into a partial that
  # *core* owns. Patches::IssuesControllerPatch puts that helper into
  # IssuesController's chain, and core renders issues/_attributes from
  # issues/_form only -- but a neighbouring plugin rendering issues/_form from a
  # controller of its own would reach the expression with no such helper and
  # raise NoMethodError on its own screen. Structural, because the negative case
  # needs a controller that does not exist in this suite.
  it 'guards the helper it injects into a core partial' do
    source = File.read(
      File.expand_path('../lib/redmine_project_workflows/overrides/issues_attributes_add_transition_map_link.rb',
                       __dir__)
    )
    calls = source.scan(/project_workflow_map_link\(@issue\)[^%]*/)

    expect(calls.size).to eq(2)
    calls.each { |call| expect(call).to include('respond_to?(:project_workflow_map_link)') }
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

  # WP5. The plugin's first setting. Redmine defines it from the register block,
  # so a setting declared in the wrong place would simply not exist -- and the
  # threshold would silently be the helper's fallback for everybody.
  it 'registers the bulk confirmation threshold as a plugin setting' do
    plugin = Redmine::Plugin.find(:redmine_project_workflows)

    expect(plugin).to be_configurable
    expect(plugin.settings[:partial]).to eq('settings/redmine_project_workflows')
    expect(Setting.available_settings).to have_key('plugin_redmine_project_workflows')
    expect(Setting.plugin_redmine_project_workflows).to have_key('bulk_confirm_threshold')
  end

  # The number is written down twice on purpose -- once as the setting's default
  # and once as the fallback for a settings hash saved before the key existed --
  # so this is the assertion that the two never drift apart.
  it 'declares the same default the helper falls back to' do
    declared = Redmine::Plugin.find(:redmine_project_workflows).settings[:default]

    expect(declared['bulk_confirm_threshold'].to_i)
      .to eq(RedmineProjectWorkflows::BulkActionsHelper::DEFAULT_BULK_CONFIRM_THRESHOLD)
  end

  # WP6 added an action and forgot this mapping, and the symptom was a 403 for
  # everybody including administrators -- not an obvious "unmapped action" error.
  # So this is structural rather than a list: every action this controller
  # actually has must be named by at least one of the two permissions, and the
  # example fails the moment the next one is added without one.
  #
  # The difference against ApplicationController is what leaves the plugin's own
  # actions: action_methods on a controller includes everything public it
  # inherited as well.
  it 'names every action of its own controller in a permission' do
    actions = ProjectWorkflowsController.action_methods - ApplicationController.action_methods
    granted = %i[view_project_workflow manage_project_workflow].flat_map do |name|
      Redmine::AccessControl.permission(name).actions
    end

    expect(actions).not_to be_empty
    actions.each do |action|
      expect(granted).to include("project_workflows/#{action}"),
                         "project_workflows##{action} is reachable and no permission names it"
    end
  end

  # WP7. The version lives in init.rb and the release notes live in CHANGELOG.md,
  # and nothing but a habit kept them agreeing. Bumping one and forgetting the
  # other ships a plugin whose own changelog describes a different release, which
  # nobody notices until somebody asks what version they are running.
  #
  # The declared minimum Redmine version needs no assertion of its own: it is
  # checked by the nine-cell matrix itself. Raise it above a version CI runs and
  # `Redmine::Plugin.register` raises on that cell before a single example loads.
  it 'declares the same version its changelog most recently describes' do
    declared = Redmine::Plugin.find(:redmine_project_workflows).version
    changelog = File.read(File.expand_path('../CHANGELOG.md', __dir__))
    newest = changelog[/^## (\S+)/, 1]

    expect(newest).to eq(declared),
                      "init.rb declares #{declared}; CHANGELOG.md's newest entry is #{newest}"
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
