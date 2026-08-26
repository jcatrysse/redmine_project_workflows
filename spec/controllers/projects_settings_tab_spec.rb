# frozen_string_literal: true

require_relative '../spec_helper'

# WP4: the project settings tab. Its rows come from ProjectsController#settings,
# because Redmine renders every tab's partial on every visit to the page --
# showTab only hides and shows what is already there -- so the data has to be
# there before the view is.
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

  describe 'the rows' do
    it 'are not loaded for somebody who may not view the workflow' do
      log_in(2, :edit_project)

      get :settings, params: { id: project.id }

      expect(response).to have_http_status(:ok)
      expect(assigns(:project_workflow_rows)).to be_nil
    end

    it 'are one per tracker the project has enabled times role with members in it' do
      log_in(2, :view_project_workflow)

      get :settings, params: { id: project.id }

      expect(response).to have_http_status(:ok)
      pairs = assigns(:project_workflow_rows).map { |row| [row.tracker.id, row.role.id] }
      expect(pairs).to eq(project.trackers.sorted.flat_map do |enabled|
        [[enabled.id, role.id], [enabled.id, developer.id]]
      end)
    end

    # The builtin roles have no members anywhere, so a project never sees them;
    # deciding the workflow for the people who are not its members stays a
    # system administrator's job.
    it 'leaves out a role that has no member in this project' do
      log_in(2, :view_project_workflow)

      get :settings, params: { id: project.id }

      role_ids = assigns(:project_workflow_rows).map { |row| row.role.id }.uniq
      expect(role_ids).not_to include(roles(:roles_003).id)
      expect(role_ids).not_to include(roles(:roles_004).id)
    end

    it 'names the state and the project\'s own rule count per kind of rule' do
      log_in(2, :view_project_workflow)
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: issue_statuses(:issue_statuses_001).id,
                                 new_status_id: issue_statuses(:issue_statuses_002).id)

      get :settings, params: { id: project.id }

      row = assigns(:project_workflow_rows).detect { |r| r.tracker.id == tracker.id && r.role.id == role.id }
      expect(row.cells[ProjectWorkflowScope::TRANSITIONS].state).to eq(:own)
      expect(row.cells[ProjectWorkflowScope::TRANSITIONS].rule_count).to eq(1)
      expect(row.cells[ProjectWorkflowScope::PERMISSIONS].state).to eq(:inherits)
    end

    # ProjectsController#update calls the settings method itself and then renders
    # its view, so a failed save must not render the tab without its rows.
    it 'are loaded again when a failed save re-renders the settings page' do
      log_in(2, :edit_project, :view_project_workflow)

      put :update, params: { id: project.id, project: { name: '' } }

      expect(response).to have_http_status(:ok)
      expect(assigns(:project_workflow_rows)).not_to be_nil
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

    it 'offers no action to somebody who may only view the workflow' do
      log_in(2, :view_project_workflow)

      get :settings, params: { id: project.id }

      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_copy)))
    end

    it 'offers the actions, carrying a way back to the tab, to somebody who may manage it' do
      log_in(2, :manage_project_workflow)

      get :settings, params: { id: project.id }

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
end
