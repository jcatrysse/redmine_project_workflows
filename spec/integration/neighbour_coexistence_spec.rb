# frozen_string_literal: true

require_relative '../spec_helper'

# What the synthetic neighbour saw. A wrapper that is silently skipped looks
# exactly like a wrapper that composed, so every example asserts the neighbour
# actually ran as well as asserting the answer.
#
# A module rather than a global, because rubocop bans the global and a constant
# inside an example group would be re-opened by every `define_method` block that
# closes over it.
module NeighbourCallLog
  class << self
    def calls
      @calls ||= []
    end

    def record(name)
      calls << name
    end

    # `delegate` would say the same thing; a plain method keeps the module
    # readable as the three-line log it is.
    def clear # rubocop:disable Rails/Delegate
      calls.clear
    end
  end
end

# WP15 item 1 -- a synthetic neighbouring plugin, in both load orders.
#
# This plugin shares a process with every other plugin the host has installed,
# and two of the three worst defects found so far were interactions with one: a
# permission name a neighbour had already claimed (F01, 2026-08-28) and a
# settings tab a neighbour's `alias_method` chain took the `super` out of (F03,
# the same day). Both were found by building a 45-plugin host by hand. That is
# an annual exercise; this file is the gate that runs every time.
#
# **What a load order is, here.** Redmine loads every plugin's `init.rb` in
# alphabetical directory order, and what a neighbour does when its turn comes
# lands in a different place depending on whether this plugin has already had
# its own:
#
#   * a neighbour that **prepends** and runs *after* this plugin puts its module
#     at the front of the chain, above the plugin's;
#   * a neighbour that **alias-chains** and runs *before* it copies core's body
#     into a `_without_` name and leaves the replacement in the class itself --
#     below anything prepended later.
#
# Those two can both be built inside a running process, and between them they
# cover both idioms on both sides of this plugin. (A module already prepended
# cannot be pushed back down the chain, so "prepends before us" is not
# constructible at spec time -- and it is the harmless one: two prepends compose
# through `super` in either order.)
#
# The combination that is neither harmless nor constructible here is a
# neighbour that **alias-chains a method this plugin has prepended**. Inside a
# class nothing can survive it: `alias_method` resolves through `ancestors`, so
# the neighbour copies the *prepended* body, and that copy's `super` finds the
# neighbour's own alias again -- forever. Every Redmine plugin that prepends a
# core class carries that exposure, and it is the neighbour's own idiom,
# deprecated since Rails 5, that causes it. Where this plugin *does* have a
# choice is core's **helper modules**, which is where plugins have actually been
# alias-chaining since 2013; two groups near the end of this file are about
# that choice.
#
# **The asymmetry these examples measure, and it is not obvious.** Most of this
# plugin's patch methods do not call `super` at all: they reimplement core's
# body with the one project-blind query replaced, because for an inheriting
# project `super` would read every other project's rows (INV-4, and the decision
# of 2026-08-26 in docs/DECISIONS.md). A neighbour *above* the plugin therefore
# composes normally, while a neighbour *below* it -- one that aliased first --
# is **bypassed rather than broken**: nothing raises, the answer stays right,
# and the neighbour's wrapper simply never runs. That is a property of the
# design rather than a defect with a fix, and it is asserted here so that it is
# a stated property rather than a surprise. The two methods that *do* delegate
# through `super` -- `Project#copy` and the settings tab -- are the contrast,
# and they have a group of their own.
describe 'living beside another plugin' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers, :enumerations

  let(:project) { projects(:projects_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:role) { roles(:roles_001) }
  let(:open_status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }

  before { NeighbourCallLog.clear }

  # "A plugin whose init.rb runs after this one and prepends the same method."
  # The modern idiom, and the one nearly every Redmine plugin written since
  # Rails 5 uses. It composes through `super`, so the only thing that can go
  # wrong is this plugin not being in the chain underneath it.
  def with_later_prepending_neighbour(target, method_name)
    neighbour = Module.new do
      define_method(method_name) do |*args, **kwargs, &block|
        NeighbourCallLog.record(method_name)
        super(*args, **kwargs, &block)
      end
    end
    target.prepend(neighbour)
    yield neighbour
  ensure
    # A prepended module cannot be removed from a chain. Emptying it leaves it
    # there doing nothing, which `undef_method` would not do: that makes the
    # name raise NoMethodError from the front of the chain for the rest of the
    # suite.
    neighbour.send(:remove_method, method_name) if neighbour.method_defined?(method_name, false)
  end

  # "A plugin whose init.rb runs before this one and takes the method over with
  # a 2013-era alias chain." It copies whatever the chain answers with at the
  # time -- in a real installation, core's own body -- and leaves the
  # replacement in the class, underneath this plugin's prepend, which has not
  # happened yet.
  #
  # The copy is taken from the class's **own** definition rather than with
  # `alias_method`, and that difference is what makes this faithful: at spec
  # time the plugin's module is already at the front of the chain, so a bare
  # `alias_method` would copy that and put the neighbour somewhere no real
  # installation puts it.
  def with_earlier_alias_chain_neighbour(target, method_name)
    own = target.instance_method(method_name)
    own = own.super_method until own.owner == target
    without = :"#{method_name}_without_neighbour"

    target.class_eval do
      define_method(without, own)
      define_method(method_name) do |*args, **kwargs, &block|
        NeighbourCallLog.record(method_name)
        send(without, *args, **kwargs, &block)
      end
    end
    yield
  ensure
    target.class_eval do
      define_method(method_name, own)
      remove_method(without)
    end
  end

  # --- the issue hot path -----------------------------------------------------

  describe 'a neighbour on Issue#new_statuses_allowed_to' do
    # Persisted, because core reads the transitions *out of the issue's current
    # status* only for a saved issue: a new record is the "new issue" pseudo
    # status and would be answered from rules this example does not write.
    let(:issue) do
      Issue.create!(project: project, tracker: tracker, status: open_status,
                    priority: enumerations(:enumerations_004), author: users(:users_002),
                    subject: 'neighbour coexistence spec')
    end

    before do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: open_status.id, new_status_id: new_status.id)
      RedmineProjectWorkflows::Services::Resolver.reset_cache!
    end

    # The project's own workflow permits exactly one move away from the current
    # status, and the generic workflow the fixtures carry permits a different
    # set -- so this answer can only have come through the plugin's own body.
    it 'still answers from the project workflow when the neighbour prepends after it' do
      with_later_prepending_neighbour(Issue, :new_statuses_allowed_to) do
        allowed = issue.new_statuses_allowed_to(users(:users_002))

        expect(NeighbourCallLog.calls).to include(:new_statuses_allowed_to)
        expect(allowed.map(&:id)).to include(new_status.id)
        expect(allowed.map(&:id)).not_to include(issue_statuses(:issue_statuses_003).id)
      end
    end

    # The other order, and the asymmetry the file header describes: this method
    # does not call `super`, so a neighbour underneath it never runs. Asserted
    # rather than glossed over -- the answer is still right and nothing raises,
    # which is the whole of what the plugin promises here, and an installation
    # combining this plugin with one that filters the same method by aliasing
    # first will find its filter silently ignored.
    it 'bypasses a neighbour that aliased before it, without breaking it' do
      with_earlier_alias_chain_neighbour(Issue, :new_statuses_allowed_to) do
        allowed = issue.new_statuses_allowed_to(users(:users_002))

        expect(NeighbourCallLog.calls).to be_empty
        expect(allowed.map(&:id)).to include(new_status.id)
      end
    end
  end

  # --- INV-1, with a neighbour in the chain -----------------------------------
  #
  # Write isolation is the invariant with the most to lose from a neighbour.
  # Core's own `replace_transitions` is routed through this plugin's writer, and
  # that routing "is not an implementation detail to be simplified away"; a
  # neighbour wrapping the same class method is the one thing that could put
  # core's own body back in front of it without anybody editing this repository.
  # These assert the isolation rather than the routing, so they say what an
  # installation actually loses if it breaks.

  describe "a neighbour on WorkflowTransition's class methods" do
    before do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: open_status.id, new_status_id: new_status.id)
    end

    # The shape core's own controller submits: old status, new status, rule name,
    # checkbox value.
    def generic_write
      WorkflowTransition.replace_transitions(
        [tracker], [role], { open_status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } }
      )
    end

    def project_transitions
      WorkflowTransition.where(project_id: project.id, tracker_id: tracker.id, role_id: role.id).count
    end

    def generic_transitions
      WorkflowTransition.where(project_id: nil, tracker_id: tracker.id, role_id: role.id).count
    end

    it 'keeps a generic write off the project rows when the neighbour prepends after it' do
      with_later_prepending_neighbour(WorkflowTransition.singleton_class, :replace_transitions) do
        generic_write

        expect(NeighbourCallLog.calls).to include(:replace_transitions)
        expect(generic_transitions).to eq(1)
        expect(project_transitions).to eq(1)
      end
    end

    # Bypassed rather than broken again, and here it is worth more than a
    # documented property: a neighbour that aliased `replace_transitions` before
    # this plugin cannot put core's project-blind write back in front of the
    # plugin's writer, whatever it does. INV-1 does not depend on the neighbour
    # behaving.
    it 'keeps a generic write off the project rows when the neighbour aliased before it' do
      with_earlier_alias_chain_neighbour(WorkflowTransition.singleton_class, :replace_transitions) do
        generic_write

        expect(NeighbourCallLog.calls).to be_empty
        expect(generic_transitions).to eq(1)
        expect(project_transitions).to eq(1)
      end
    end
  end

  # --- the methods that do delegate -------------------------------------------
  #
  # `Project#copy` is one of the two patch methods that calls `super` (the other
  # is the status-deletion warning, and the settings tab does the same thing in
  # a helper chain). It exists to record one flag and hand straight on, so a
  # neighbour underneath it *does* run -- which is the contrast that makes the
  # groups above say something. If this ever stopped delegating, the plugin
  # would have taken over core's whole project copy.

  describe 'a neighbour on Project#copy, which the plugin delegates' do
    let(:destination) do
      Project.new(name: 'neighbour copy', identifier: 'neighbour-copy-spec')
    end

    it 'runs when it aliased before the plugin' do
      with_earlier_alias_chain_neighbour(Project, :copy) do
        destination.copy(project, only: [])

        expect(NeighbourCallLog.calls).to include(:copy)
      end
    end

    it 'runs when it prepends after the plugin' do
      with_later_prepending_neighbour(Project, :copy) do
        destination.copy(project, only: [])

        expect(NeighbourCallLog.calls).to include(:copy)
      end
    end
  end

  # --- where the plugin attaches to core's helper modules ---------------------

  # The structural rule, stated over both modules the plugin holds copies of
  # core bodies for, so that a refactor putting either back inside a core helper
  # fails here rather than on somebody's settings page.
  describe 'the attachment to core helper modules' do
    {
      'RedmineProjectWorkflows::Patches::ProjectsHelperPatch' => 'ProjectsHelper',
      'ProjectWorkflowMatrixHelper' => 'WorkflowsHelper'
    }.each do |ours_name, core_name|
      it "keeps #{ours_name} beside #{core_name} and never inside it" do
        ours = ours_name.constantize
        core_module = core_name.constantize

        expect(core_module.ancestors).not_to include(ours),
                                             "#{ours_name} is inside #{core_name} again -- a neighbour's alias " \
                                             'chain will copy it and lose its super'
      end
    end

    # ProjectsHelper's half of this is in spec/controllers/projects_settings_tab_spec.rb,
    # beside the tab it is about.
    it "reaches core's workflow screens through the controller helper chain instead" do
      chain = WorkflowsController._helpers.ancestors

      expect(chain).to include(ProjectWorkflowMatrixHelper),
                       'the matrix helper is not in the controller helper chain at all'
      # Asserted rather than assumed: without it the comparison below would
      # compare against nil and fail as a confusing TypeError.
      expect(chain).to include(WorkflowsHelper), 'core stopped putting WorkflowsHelper in the chain'
      expect(chain.index(ProjectWorkflowMatrixHelper)).to be < chain.index(WorkflowsHelper),
                                                          'the plugin sits below WorkflowsHelper, so core\'s own ' \
                                                          'definitions win and the row actions never render'
    end
  end

  # --- the reload guard -------------------------------------------------------

  # **These two are forward gates, and cannot be made red on today's code.**
  # Stated plainly because CLAUDE.md asks every fix to carry a test that fails
  # on the old code, and these do not: `Module#prepend` is itself idempotent, so
  # emptying `prepend_once`'s guard changes nothing an example can see. What
  # they catch is a *future* `apply_patches` that stops being idempotent -- one
  # that wraps each patch in a fresh anonymous module, or includes rather than
  # prepends -- which would grow the chain on every reload of a development
  # host and never on CI. That is exactly the shape of defect nobody finds by
  # running the suite.
  describe 'applying the patches again, as a code reload does' do
    it 'moves nothing in a chain a neighbour has since joined' do
      with_later_prepending_neighbour(Issue, :new_statuses_allowed_to) do |neighbour|
        before_order = Issue.ancestors.take_while { |mod| mod != Issue }

        RedmineProjectWorkflows.apply_patches

        expect(Issue.ancestors.take_while { |mod| mod != Issue }).to eq(before_order)
        expect(before_order.index(neighbour))
          .to be < before_order.index(RedmineProjectWorkflows::Patches::IssuePatch)
      end
    end

    it 'adds no second copy of any patch module' do
      RedmineProjectWorkflows.apply_patches

      { Issue => 'IssuePatch', Project => 'ProjectPatch', Role => 'RolePatch',
        Tracker => 'TrackerPatch', IssueStatusesController => 'IssueStatusesControllerPatch',
        WorkflowsController => 'WorkflowsControllerPatch' }.each do |klass, patch_name|
        patch = "RedmineProjectWorkflows::Patches::#{patch_name}".constantize
        expect(klass.ancestors.count(patch)).to eq(1), "#{patch_name} is in #{klass}'s chain more than once"
      end

      { WorkflowTransition => 'WorkflowTransitionPatch', WorkflowPermission => 'WorkflowPermissionPatch',
        WorkflowRule => 'WorkflowRulePatch' }.each do |klass, patch_name|
        patch = "RedmineProjectWorkflows::Patches::#{patch_name}".constantize
        expect(klass.singleton_class.ancestors.count(patch)).to eq(1)
      end
    end
  end
end

# The behavioural half of the helper-module rule, which needs a rendered page
# and therefore a controller.
#
# Core's own Administration -> Workflow screens carry three of the plugin's five
# surviving Deface overrides (ADR-003), and all three call helpers the plugin
# puts into `WorkflowsController._helpers` rather than into `WorkflowsHelper` --
# precisely so that a neighbour's alias chain on that module cannot reach them.
# Each screen also calls core's own
# `field_permission_tag` or `options_for_workflow_select` from the same module,
# so a rendered page proves both directions at once: the neighbour's wrapper
# ran, and the plugin's markup is still on the page.
#
# This is the load order a prepend cannot survive, applied with a real
# `alias_method` -- the construct that springs the trap.
describe WorkflowsController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  render_views

  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }

  before do
    @request.session[:user_id] = 1
    NeighbourCallLog.clear
  end

  def selection
    { role_id: [role.id.to_s], tracker_id: [tracker.id.to_s], used_statuses_only: '0' }
  end

  def with_neighbour_alias_chain_on(method_name)
    without = :"#{method_name}_without_neighbour"
    WorkflowsHelper.class_eval do
      alias_method without, method_name
      define_method(method_name) do |*args, **kwargs, &block|
        NeighbourCallLog.record(method_name)
        send(without, *args, **kwargs, &block)
      end
    end
    yield
  ensure
    WorkflowsHelper.class_eval do
      alias_method method_name, without
      remove_method without
    end
  end

  describe 'living beside a plugin that takes a WorkflowsHelper method over' do
    it "renders core's transitions matrix with the plugin's row actions still on it" do
      with_neighbour_alias_chain_on(:options_for_workflow_select) do
        get :edit, params: selection

        expect(response).to have_http_status(:ok)
        expect(NeighbourCallLog.calls).to include(:options_for_workflow_select)
        # The plugin's own contribution to core's screen, and what a lost helper
        # chain takes away: a page that renders is not the same as a page intact.
        expect(response.body).to include('project-workflow-bulk')
      end
    end

    it "renders core's field permissions matrix with the plugin's cross link still on it" do
      with_neighbour_alias_chain_on(:options_for_workflow_select) do
        get :permissions, params: selection

        expect(response).to have_http_status(:ok)
        expect(NeighbourCallLog.calls).to include(:options_for_workflow_select)
        # This screen carries the action-menu override rather than the row
        # actions, and its link is drawn by VersionHelper -- which reaches the
        # page through the same one attachment.
        expect(css_select("div.contextual a[href='#{project_workflow_rules_path}']")).not_to be_empty
      end
    end

    # `field_permission_tag` is the one WorkflowsHelper method the plugin holds
    # a copy of (ADR-003), so a neighbour aliasing it lands *below* the plugin's
    # copy in the controller's chain and its wrapper does not run on this screen.
    # That is the arrangement working: core's own module keeps a definition the
    # neighbour can chain safely, and the plugin's copy above it is out of the
    # alias's reach in either load order. What the page must not do is raise.
    it 'renders when a neighbour chains the one method the plugin holds a copy of' do
      with_neighbour_alias_chain_on(:field_permission_tag) do
        get :permissions, params: selection

        expect(response).to have_http_status(:ok)
        expect(NeighbourCallLog.calls).to be_empty
        expect(css_select("div.contextual a[href='#{project_workflow_rules_path}']")).not_to be_empty
      end
    end
  end
end
