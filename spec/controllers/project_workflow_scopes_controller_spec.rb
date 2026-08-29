# frozen_string_literal: true

require_relative '../spec_helper'

describe ProjectWorkflowScopesController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles,
           :enabled_modules

  let(:project) { projects(:projects_001) }
  let(:other) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }

  def base_params(overrides = {})
    { project_id: [project.id.to_s], tracker_id: [tracker.id.to_s], role_id: [role.id.to_s],
      rule_type: ProjectWorkflowScope::TRANSITIONS }.merge(overrides)
  end

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
    @request.session[:user_id] = 1 # administrator
  end

  describe 'authorization' do
    # INV-7. WP4 opens these actions to project managers; until then they are
    # administrator-only, and no parameter widens that.
    it 'refuses a non-administrator' do
      @request.session[:user_id] = users(:users_002).id

      post :create, params: base_params

      expect(response).to have_http_status(:forbidden)
      expect(ProjectWorkflowScope.count).to eq(0)
    end

    it 'refuses an anonymous request' do
      @request.session[:user_id] = nil

      post :create, params: base_params

      expect(response).not_to have_http_status(:ok)
      expect(ProjectWorkflowScope.count).to eq(0)
    end
  end

  describe 'parameter validation' do
    it 'rejects an unknown rule type' do
      post :create, params: base_params(rule_type: 'everything')

      expect(response).to have_http_status(:not_found)
      expect(ProjectWorkflowScope.count).to eq(0)
    end

    it 'rejects a project id that does not exist' do
      post :create, params: base_params(project_id: [(Project.maximum(:id) + 1).to_s])

      expect(response).to have_http_status(:not_found)
      expect(ProjectWorkflowScope.count).to eq(0)
    end

    # Rails resolves where(id: ['1e5']) and where(id: ['01']) to project 1, so
    # the shape of a value is checked before it reaches a query.
    it 'rejects a project id that is not a plain number' do
      ['1e5', ' 1', '1;', 'one'].each do |value|
        post :create, params: base_params(project_id: [value])

        expect(response).to have_http_status(:not_found)
      end
      expect(ProjectWorkflowScope.count).to eq(0)
    end

    it 'rejects a tracker or role that does not exist' do
      post :create, params: base_params(tracker_id: [(Tracker.maximum(:id) + 1).to_s])
      expect(response).to have_http_status(:not_found)

      post :create, params: base_params(role_id: [(Role.maximum(:id) + 1).to_s])
      expect(response).to have_http_status(:not_found)

      expect(ProjectWorkflowScope.count).to eq(0)
    end

    it 'accepts the generic entry and simply has nothing to do for it' do
      post :create, params: base_params(project_id: %w[global])

      expect(response).to redirect_to(%r{project_workflow_rules/edit})
      expect(ProjectWorkflowScope.count).to eq(0)
    end
  end

  describe 'the three actions' do
    before do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: s1.id, new_status_id: s2.id)
    end

    it 'enables a project workflow as a copy of the generic one' do
      post :create, params: base_params(source: 'copy')

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(1)
      expect(flash[:notice]).to be_present
      expect(response).to redirect_to(%r{project_workflow_rules/edit})
    end

    it 'enables an empty project workflow when asked to' do
      post :create, params: base_params(source: 'empty')

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
    end

    # Copy is the safe default: an accidental empty scope freezes every issue.
    it 'copies when the source is missing or unrecognised' do
      post :create, params: base_params

      expect(WorkflowTransition.where(project_id: project.id).count).to eq(1)
    end

    it 'returns a project to inheritance' do
      post :create, params: base_params(source: 'copy')

      delete :destroy, params: base_params

      expect(own_workflow?(project, tracker, role)).to be(false)
      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
      expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
    end

    it 'empties the matrix and keeps the scope' do
      post :create, params: base_params(source: 'copy')

      post :clear, params: base_params

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
    end

    it 'says so when there was nothing to do' do
      post :clear, params: base_params

      expect(flash[:warning]).to be_present
      expect(flash[:notice]).to be_blank
    end

    it 'acts on the permissions matrix separately and returns to it' do
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: s1.id, field_name: 'due_date', rule: 'required')

      post :create, params: base_params(rule_type: ProjectWorkflowScope::PERMISSIONS, source: 'copy')

      expect(own_workflow?(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)).to be(true)
      expect(own_workflow?(project, tracker, role, ProjectWorkflowScope::TRANSITIONS)).to be(false)
      expect(WorkflowPermission.where(project_id: project.id).count).to eq(1)
      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
      expect(response).to redirect_to(%r{project_workflow_rules/permissions})
    end

    it 'acts on every selected project' do
      post :create, params: base_params(project_id: [project.id.to_s, other.id.to_s], source: 'copy')

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(own_workflow?(other, tracker, role)).to be(true)
    end

    it 'never touches a project that was not selected' do
      give_own_workflow(other, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: other.id,
                                 old_status_id: s1.id, new_status_id: s2.id)

      delete :destroy, params: base_params(project_id: [project.id.to_s])

      expect(own_workflow?(other, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: other.id).count).to eq(1)
    end

    it 'never touches the generic workflow' do
      post :create, params: base_params(project_id: [project.id.to_s, 'global'], source: 'copy')
      delete :destroy, params: base_params(project_id: [project.id.to_s, 'global'])

      expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
    end

    # WP13, audit finding F09. 'all' is what the selector offered, and an
    # archived project is not on that list -- so *give every project its own
    # workflow* does not quietly write one for a project nobody can reach. Named
    # directly it still works, which is what keeps an archived project's existing
    # workflow removable.
    it 'leaves an archived project out of the all keyword, and acts on it when named' do
      other.update!(status: Project::STATUS_ARCHIVED)

      post :create, params: base_params(project_id: ['all'], source: 'empty')

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(own_workflow?(other, tracker, role)).to be(false)

      post :create, params: base_params(project_id: [other.id.to_s], source: 'empty')

      expect(own_workflow?(other, tracker, role)).to be(true)
    end
  end
end
