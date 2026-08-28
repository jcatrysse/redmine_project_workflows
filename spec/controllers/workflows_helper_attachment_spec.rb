# frozen_string_literal: true

require_relative '../spec_helper'

# Where the workflow matrices' cell helpers are attached, tested on the screens
# that render them.
#
# `Patches::WorkflowsHelperPatch` is put into the helper chains of
# `WorkflowsController` and `ProjectWorkflowsController` and deliberately never
# into `WorkflowsHelper` itself. Many Redmine plugins still take a core helper
# over with a 2013-era alias chain, and `alias_method` resolves the name through
# `WorkflowsHelper.ancestors` -- so with a prepend in place the neighbour copies
# **our** method into its `_without_` alias and that copy's `super` looks above
# `WorkflowsHelper`, where core's method is not.
#
# This is the sibling of the group at the end of
# `spec/controllers/projects_settings_tab_spec.rb`, and the same measurement
# stands behind both: on a Redmine 5.1 carrying 44 other plugins,
# `ProjectsHelper.prepend` turns the settings page into an HTTP 500. No
# neighbour on that host alias-chains `WorkflowsHelper`, which is why finding
# F01 of `2026-08-28-claude-audit` was latent rather than live -- and why it
# needs a spec rather than a bug report.
describe 'WorkflowsHelperPatch attachment' do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers

  # A **plain `alias_method`**, which is the whole point and was nearly got
  # wrong: this file's first draft copied `WorkflowsHelper`'s own definition by
  # walking `super_method` down to it, the way
  # `projects_settings_tab_spec.rb`'s `with_neighbour_alias_chain` does. That
  # models a neighbour whose `init.rb` runs *before* this plugin, which is the
  # safe order -- and the examples below then passed with the prepend restored,
  # i.e. they were tests that could not fail. Measured, not reasoned: reverting
  # to `WorkflowsHelper.prepend` turned exactly one of five examples red.
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

  it 'is not in WorkflowsHelper\'s own ancestors' do
    expect(WorkflowsHelper.ancestors)
      .not_to include(RedmineProjectWorkflows::Patches::WorkflowsHelperPatch)
  end

  # One controller since ADR-003, and it is core's: the plugin's own screens
  # render their own project selector, so nothing of theirs goes through
  # `options_for_workflow_select`.
  it 'is in the helper chain of core\'s own workflow controller' do
    expect(WorkflowsController._helpers.ancestors)
      .to include(RedmineProjectWorkflows::Patches::WorkflowsHelperPatch)
  end

  # The cells are a separate module and travel further, because three controllers
  # render a matrix. Naming one would leave the others' cells unrendered -- and
  # `ProjectWorkflowMatrixHelper` must stay out of `WorkflowsHelper` for exactly
  # the reason the patch above must: a neighbour's alias chain there would copy
  # our method and take core's with it.
  it 'puts the matrix cells in every chain that renders one, and in no core helper' do
    [WorkflowsController, ProjectWorkflowsController, ProjectWorkflowRulesController].each do |controller|
      expect(controller._helpers.ancestors)
        .to include(ProjectWorkflowMatrixHelper), "#{controller} does not carry the cells"
    end
    expect(WorkflowsHelper.ancestors).not_to include(ProjectWorkflowMatrixHelper)
  end

  describe WorkflowsController, type: :controller do
    render_views

    let(:role) { roles(:roles_001) }
    let(:tracker) { trackers(:trackers_001) }

    before { @request.session[:user_id] = 1 }

    # Red with `WorkflowsHelper.prepend(WorkflowsHelperPatch)` restored:
    # NoMethodError, "super: no superclass method
    # `options_for_workflow_select'", reproduced on a running Redmine 5.1.
    it 'still renders the administration matrix beside a neighbour\'s alias chain' do
      with_later_neighbour_alias_chain do
        get :edit, params: { role_id: [role.id], tracker_id: [tracker.id] }
      end

      expect(response).to have_http_status(:ok)
    end

    # The quieter half of the same defect. `#transition_tag` and
    # `#field_permission_tag` replace core outright, so a neighbour that
    # alias-chains one of those has its redefinition land on `WorkflowsHelper`
    # itself -- below a prepended module -- and never run at all. Asserting the
    # neighbour's own contribution reaches the page is what tells the two apart:
    # the screen rendering is not enough, the neighbour has to still work.
    it 'lets the neighbour\'s own wrapper run' do
      with_later_neighbour_alias_chain do
        get :edit, params: { role_id: [role.id], tracker_id: [tracker.id] }
      end

      expect(response.body).to include('neighbour-was-here')
    end
  end

  # The project matrix renders the same partial from a different controller and
  # never touches `options_for_workflow_select`, so what it proves is the other
  # half of `apply!`: naming only `WorkflowsController` would leave every cell
  # here unrendered.
  describe ProjectWorkflowsController, type: :controller do
    render_views

    let(:project) { projects(:projects_001) }
    let(:role) { roles(:roles_001) }
    let(:tracker) { trackers(:trackers_001) }

    before { @request.session[:user_id] = 1 }

    it 'renders the project matrix, whose cells come from the same patch' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: { project_id: project.id, tracker_id: tracker.id, role_id: role.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('transitions[')
    end
  end
end
