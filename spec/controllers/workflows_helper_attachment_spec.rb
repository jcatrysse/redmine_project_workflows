# frozen_string_literal: true

require_relative '../spec_helper'

# Where the workflow matrices' cell helpers are attached, tested on the screens
# that render them.
#
# `ProjectWorkflowMatrixHelper` holds the plugin's versions of core's
# `transition_tag` and `field_permission_tag`, and it is put into the helper
# *chains* of the three controllers that render a matrix -- never into
# `WorkflowsHelper` itself. Many Redmine plugins still take a core helper over
# with a 2013-era alias chain, and `alias_method` resolves the name through
# `WorkflowsHelper.ancestors` -- so with a prepend in place the neighbour copies
# **our** method into its `_without_` alias and that copy's `super` looks above
# `WorkflowsHelper`, where core's method is not.
#
# ADR-003 removed the module that made this live: `WorkflowsHelperPatch` wrapped
# core's `options_for_workflow_select` and called `super`, which is the shape
# that raises. The plugin renders its own project selector on its own screens
# now, so nothing of the plugin's calls `super` into `WorkflowsHelper` at all --
# and what is left is the rule, which these examples keep.
#
# This is the sibling of the group at the end of
# `spec/controllers/projects_settings_tab_spec.rb`, and the same measurement
# stands behind both: on a Redmine 5.1 carrying 44 other plugins,
# `ProjectsHelper.prepend` turns the settings page into an HTTP 500. No
# neighbour on that host alias-chains `WorkflowsHelper`, which is why finding
# F01 of `2026-08-28-claude-audit` was latent rather than live -- and why it
# needs a spec rather than a bug report.
describe 'the workflow matrix helper attachment' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers

  # A **plain `alias_method`**, which is the whole point and was nearly got
  # wrong: this file's first draft copied `WorkflowsHelper`'s own definition by
  # walking `super_method` down to it, the way
  # `projects_settings_tab_spec.rb`'s `with_neighbour_alias_chain` does. That
  # models a neighbour whose `init.rb` runs *before* this plugin, which is the
  # safe order -- and the examples below then passed with a prepend restored,
  # i.e. they were tests that could not fail.
  #
  # `alias_method` resolves the name through `WorkflowsHelper.ancestors`, so a
  # neighbour loading *after* this plugin copies whatever sits at the front. With
  # a prepend in place that is **our** method, and the copy -- now owned by
  # `WorkflowsHelper` -- has no `super` to reach. Plugins load alphabetically and
  # `redmine_project_workflows` sorts before everything from `redmine_q` on, so
  # this is the ordinary order rather than a corner case.
  def with_later_neighbour_alias_chain
    WorkflowsHelper.class_eval do
      alias_method :options_for_workflow_select_without_later, :options_for_workflow_select
      def options_for_workflow_select_with_later(name, objects, selected, options = {})
        options_for_workflow_select_without_later(name, objects, selected, options) +
          content_tag(:span, 'neighbour-was-here', class: 'neighbour-marker')
      end
      alias_method :options_for_workflow_select, :options_for_workflow_select_with_later
    end
    yield
  ensure
    WorkflowsHelper.class_eval do
      alias_method :options_for_workflow_select, :options_for_workflow_select_without_later
      remove_method :options_for_workflow_select_without_later
      remove_method :options_for_workflow_select_with_later
    end
  end

  # Three controllers render a matrix and every one of them needs the cells.
  # Naming fewer would leave the others' cells unrendered -- and core's own
  # workflow controller is the one that cannot name the module itself, which is
  # what `Patches::WorkflowsControllerHelperPatch` exists for: core's
  # `workflows/_form` carries the plugin's row and column actions, and those call
  # `project_workflow_bulk_actions`.
  it 'puts the matrix cells in every chain that renders one, and in no core helper' do
    [WorkflowsController, ProjectWorkflowsController, ProjectWorkflowRulesController].each do |controller|
      expect(controller._helpers.ancestors)
        .to include(ProjectWorkflowMatrixHelper), "#{controller} does not carry the cells"
    end
    expect(WorkflowsHelper.ancestors).not_to include(ProjectWorkflowMatrixHelper)
  end

  # ADR-003's deletion, asserted rather than assumed: nothing of the plugin's is
  # mixed into core's workflow helper any more, under any name.
  it 'mixes nothing of the plugin\'s into WorkflowsHelper' do
    plugin_modules = WorkflowsHelper.ancestors.select do |mod|
      mod.name.to_s.start_with?('RedmineProjectWorkflows', 'ProjectWorkflow')
    end

    expect(plugin_modules).to be_empty
  end

  describe WorkflowsController, type: :controller do
    render_views

    let(:role) { roles(:roles_001) }
    let(:tracker) { trackers(:trackers_001) }

    before { @request.session[:user_id] = 1 }

    it 'still renders the administration matrix beside a neighbour\'s alias chain' do
      with_later_neighbour_alias_chain do
        get :edit, params: { role_id: [role.id], tracker_id: [tracker.id] }
      end

      expect(response).to have_http_status(:ok)
    end

    # Asserting the neighbour's own contribution reaches the page is what tells
    # "the screen rendered" apart from "the neighbour still works". Core's own
    # tracker and role selectors go through `options_for_workflow_select`, so the
    # marker appears twice on this page whatever the plugin does -- and would
    # appear nowhere at all if the plugin had taken the method over with a
    # prepend.
    it 'lets the neighbour\'s own wrapper run' do
      with_later_neighbour_alias_chain do
        get :edit, params: { role_id: [role.id], tracker_id: [tracker.id] }
      end

      expect(response.body).to include('neighbour-was-here')
    end
  end

  # The plugin's own administration matrix calls `options_for_workflow_select`
  # too -- for the tracker and role selectors, which are core's helper rendered
  # from the plugin's view (`helper :workflows`). A neighbour's alias chain has
  # to survive there as well, and it does for the same reason: nothing of the
  # plugin's is in front of the method.
  describe ProjectWorkflowRulesController, type: :controller do
    render_views

    let(:role) { roles(:roles_001) }
    let(:tracker) { trackers(:trackers_001) }

    before { @request.session[:user_id] = 1 }

    it 'renders its own matrix beside a neighbour\'s alias chain, and lets it run' do
      with_later_neighbour_alias_chain do
        get :edit, params: { role_id: [role.id], tracker_id: [tracker.id] }
      end

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('neighbour-was-here')
    end
  end

  # The project matrix renders the same partial from a third controller, and what
  # it proves is the rest of the attachment: naming only the two administration
  # controllers would leave every cell here unrendered.
  describe ProjectWorkflowsController, type: :controller do
    render_views

    let(:project) { projects(:projects_001) }
    let(:role) { roles(:roles_001) }
    let(:tracker) { trackers(:trackers_001) }

    before { @request.session[:user_id] = 1 }

    it 'renders the project matrix, whose cells come from the same helper' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: { project_id: project.id, tracker_id: tracker.id, role_id: role.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('transitions[')
    end
  end
end
