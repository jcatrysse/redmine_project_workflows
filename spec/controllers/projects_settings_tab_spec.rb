# frozen_string_literal: true

require_relative '../spec_helper'

# WP4: the project settings tab, tested where it actually lives -- on core's own
# project settings page.
#
# The last group is the one that matters most. The plugin extends
# `project_settings_tabs` in ProjectsController's helper chain and deliberately
# never inside `ProjectsHelper`, because many Redmine plugins take that method
# over with an alias chain and would copy a prepended override into their
# `_without_` alias, losing its `super` and core's own tabs with it. That is a
# measured failure in `redmine_ai_triage` (its K-29), not a hypothesis.
describe ProjectsController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:developer) { roles(:roles_002) }

  def log_in(user_id, *permissions)
    role.add_permission!(*permissions) if permissions.any?
    @request.session[:user_id] = user_id
  end

  # Exactly the shape the neighbouring plugins use: a `_without_` copy of the
  # method that was there, and the real name pointing at a `_with_` that calls
  # it.
  #
  # The copy is taken from ProjectsHelper's **own** definition rather than with
  # `alias_method`, and that difference is what makes this faithful.
  # `alias_method` resolves through `ProjectsHelper.ancestors`, so at spec time
  # it would copy whatever sits at the front; in a real installation the alias
  # chain runs from a plugin's `init.rb` and copies core's method, landing below
  # anything applied later. Reproducing that position is the point.
  def with_neighbour_alias_chain
    own = ProjectsHelper.instance_method(:project_settings_tabs)
    own = own.super_method until own.owner == ProjectsHelper

    ProjectsHelper.class_eval do
      define_method(:project_settings_tabs_without_neighbour, own)
      def project_settings_tabs_with_neighbour
        project_settings_tabs_without_neighbour + [{ name: 'neighbour', label: :label_general }]
      end
      alias_method :project_settings_tabs, :project_settings_tabs_with_neighbour
    end
    yield
  ensure
    ProjectsHelper.class_eval do
      alias_method :project_settings_tabs, :project_settings_tabs_without_neighbour
      remove_method :project_settings_tabs_without_neighbour
      remove_method :project_settings_tabs_with_neighbour
    end
  end

  describe 'the rows' do
    render_views

    def rendered_pairs
      response.body.scan(%r{workflow/transitions\?role_id=(\d+)&amp;tracker_id=(\d+)})
              .map { |role_id, tracker_id| [tracker_id.to_i, role_id.to_i] }.uniq
    end

    it 'are one per tracker the project has enabled times role with members in it' do
      log_in(2, :view_project_workflow)

      get :settings, params: { id: project.id }

      expect(response).to have_http_status(:ok)
      expect(rendered_pairs).to eq(project.trackers.sorted.flat_map do |enabled|
        [[enabled.id, role.id], [enabled.id, developer.id]]
      end)
    end

    # The builtin roles have no members anywhere, so a project never sees them;
    # deciding the workflow for the people who are not its members stays a
    # system administrator's job.
    it 'leave out a role that has no member in this project' do
      log_in(2, :view_project_workflow)

      get :settings, params: { id: project.id }

      role_ids = rendered_pairs.map(&:last).uniq
      expect(role_ids).not_to include(roles(:roles_003).id)
      expect(role_ids).not_to include(roles(:roles_004).id)
    end

    it "name the state and the project's own rule count per kind of rule" do
      log_in(2, :view_project_workflow)
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: issue_statuses(:issue_statuses_001).id,
                                 new_status_id: issue_statuses(:issue_statuses_002).id)

      get :settings, params: { id: project.id }

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_own)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_inherits)))
    end

    # ProjectsController#update calls the settings method itself and then renders
    # its view. The rows come from a helper rather than from that method, so this
    # path needs nothing of its own -- which is exactly what it asserts.
    it 'are there when a failed save re-renders the settings page' do
      log_in(2, :edit_project, :view_project_workflow)

      put :update, params: { id: project.id, project: { name: '' } }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('tab-project_workflows')
      expect(rendered_pairs).not_to be_empty
    end
  end

  describe 'the tab' do
    render_views

    it 'is absent for somebody who may not view the workflow' do
      log_in(2, :edit_project)

      get :settings, params: { id: project.id }

      expect(response.body).not_to include('tab-project_workflows')
    end

    it 'lists the combinations, with a link into each matrix' do
      log_in(2, :view_project_workflow)

      get :settings, params: { id: project.id }

      expect(response.body).to include('tab-project_workflows')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_inherits)))
      # The route helpers themselves, so the assertion cannot drift from the
      # links: what the tab renders has to be openable as it stands.
      transitions = project_workflow_transitions_path(project, tracker_id: tracker.id, role_id: role.id)
      permissions = project_workflow_permissions_path(project, tracker_id: tracker.id, role_id: role.id)
      expect(response.body).to include(ERB::Util.html_escape(transitions))
      expect(response.body).to include(ERB::Util.html_escape(permissions))
    end

    # WP6: the same audit line the administration inventory carries, on the tab
    # a project manager actually looks at.
    it 'says who last changed a workflow the project owns' do
      log_in(2, :view_project_workflow)
      RedmineProjectWorkflows::Services::ScopeWriter.enable(
        project_ids: [project.id], tracker_ids: [tracker.id], role_ids: [role.id],
        rule_type: ProjectWorkflowScope::TRANSITIONS, copy_generic: false,
        user: users(:users_003)
      )

      get :settings, params: { id: project.id }

      expect(response.body).to include('project-workflow-scope-audit')
      # Scoped to the audit element, not to the page: dlopper is a member of
      # this project, so core's own Members tab renders that name into the same
      # response whatever the audit line says. The unscoped assertion this
      # replaces passed for that reason.
      expect(css_select('span.project-workflow-scope-audit').to_s)
        .to include(users(:users_003).name)
    end

    it 'says nothing about a combination the project inherits' do
      log_in(2, :view_project_workflow)

      get :settings, params: { id: project.id }

      expect(response.body).to include('tab-project_workflows')
      expect(response.body).not_to include('project-workflow-scope-audit')
    end

    # WP6: the second of the comparison's three entry points.
    it 'links to the comparison for a workflow the project owns' do
      log_in(2, :view_project_workflow)
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::TRANSITIONS)

      get :settings, params: { id: project.id }

      path = project_workflow_compare_path(project, tracker_id: tracker.id, role_id: role.id,
                                                    rule_type: ProjectWorkflowScope::TRANSITIONS)
      expect(response.body).to include(ERB::Util.html_escape(path))
    end

    it 'does not link to the comparison for a combination the project inherits' do
      log_in(2, :view_project_workflow)

      get :settings, params: { id: project.id }

      expect(response.body).to include('tab-project_workflows')
      expect(response.body).not_to include('project-workflow-compare-link')
    end

    it 'offers no action to somebody who may only view the workflow' do
      log_in(2, :view_project_workflow)

      get :settings, params: { id: project.id }

      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_copy)))
    end

    # A permission that manages but does not view still opens the tab: the entry
    # names the action it leads to, not one of the two permissions.
    it 'offers the actions, carrying a way back to the tab, to somebody who may manage it' do
      log_in(2, :manage_project_workflow)

      get :settings, params: { id: project.id }

      expect(response.body).to include('tab-project_workflows')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_copy)))
      expect(response.body).to match(/back_url=[^"']*settings/)
    end

    it 'is absent once issue tracking is switched off for the project' do
      log_in(2, :view_project_workflow, :edit_project)
      project.enabled_module_names = project.enabled_module_names - ['issue_tracking']

      get :settings, params: { id: project.id }

      expect(response.body).not_to include('tab-project_workflows')
    end
  end

  # The other load order, and the one that actually breaks a prepend: a plugin
  # whose init.rb runs *after* this one and uses a real `alias_method`. That
  # resolves the name through ProjectsHelper.ancestors, so with anything
  # prepended to ProjectsHelper it copies the *prepended* method -- and the
  # copy, now owned by ProjectsHelper, has no super to reach.
  #
  # Plugins load alphabetically, and `redmine_project_workflows` sorts before
  # `redmine_q...` and everything after it, so this is not a corner case.
  def with_later_neighbour_alias_chain
    ProjectsHelper.class_eval do
      alias_method :project_settings_tabs_without_later, :project_settings_tabs
      def project_settings_tabs_with_later
        project_settings_tabs_without_later + [{ name: 'later', label: :label_general }]
      end
      alias_method :project_settings_tabs, :project_settings_tabs_with_later
    end
    yield
  ensure
    ProjectsHelper.class_eval do
      alias_method :project_settings_tabs, :project_settings_tabs_without_later
      remove_method :project_settings_tabs_without_later
      remove_method :project_settings_tabs_with_later
    end
  end

  describe 'living beside a plugin that takes the tab list over' do
    render_views

    # The behavioural half. While the tab list was extended with
    # ProjectsHelper.prepend, a neighbour's alias chain copied the plugin's
    # method into its `_without_` alias; that copy's `super` looked above
    # ProjectsHelper, where nothing answers, so core's own method dropped out of
    # the chain and every settings page raised NoMethodError.
    it 'keeps its own tab, the neighbour\'s and core\'s' do
      log_in(2, :view_project_workflow)

      with_neighbour_alias_chain do
        get :settings, params: { id: project.id }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('tab-project_workflows')
        expect(response.body).to include('tab-neighbour')
        # Core's own tabs have to survive too: losing them was the other half of
        # the failure, and a page that renders is not the same as a page intact.
        expect(response.body).to include('tab-info')
      end
    end

    # The load order that broke it, reproduced with a real `alias_method`: a
    # plugin whose init.rb runs after this one. This is the example that fails
    # outright -- NoMethodError on every project's settings page -- the moment
    # the tab override goes back inside ProjectsHelper.
    it 'survives a neighbour that aliases after this plugin has applied' do
      log_in(2, :view_project_workflow)

      with_later_neighbour_alias_chain do
        get :settings, params: { id: project.id }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('tab-project_workflows')
        expect(response.body).to include('tab-later')
        expect(response.body).to include('tab-info')
      end
    end

    # The structural half, stated so that a refactor back to `prepend` fails
    # here rather than on somebody's settings page.
    it 'lives beside ProjectsHelper and never inside it' do
      ours = RedmineProjectWorkflows::Patches::ProjectsHelperPatch

      expect(ProjectsHelper.ancestors).not_to include(ours),
                                              'the override is inside ProjectsHelper again -- a neighbour alias ' \
                                              'chain will copy it and lose its super'

      chain = ProjectsController._helpers.ancestors
      expect(chain).to include(ours), 'the override is not in the controller helper chain at all'
      # Asserted rather than assumed: without it the comparison below would
      # compare against nil and fail as a confusing TypeError.
      expect(chain).to include(ProjectsHelper), 'core stopped putting ProjectsHelper in the chain'
      expect(chain.index(ours)).to be < chain.index(ProjectsHelper),
                                   'the override sits below ProjectsHelper, so its tab never reaches the page'
    end
  end
end
