# frozen_string_literal: true

require_relative '../spec_helper'

describe WorkflowsController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:target_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:target_tracker) { trackers(:trackers_002) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }
  let(:other_project_status) { issue_statuses(:issue_statuses_004) }

  before do
    @request.session[:user_id] = 1
  end

  # WP3 / claude F01. This was the last characterization example: core's
  # summary page groups every workflow row by tracker and role with no
  # project_id predicate at all (INV-4), so a project that had taken over one
  # tracker made the generic workflow look like it had rules it does not have.
  describe 'the summary page' do
    it 'leaves a project\'s rules out of the generic totals' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: old_status.id, new_status_id: new_status.id,
                                 project_id: nil)
      get :index
      generic_only = assigns(:workflow_counts)[[tracker.id, role.id]]

      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: old_status.id, new_status_id: new_status.id,
                                 project_id: project.id)
      get :index

      expect(generic_only).to eq(1)
      expect(assigns(:workflow_counts)[[tracker.id, role.id]]).to eq(1)
    end

    it 'counts the selected project instead of the generic workflow' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: old_status.id, new_status_id: new_status.id,
                                 project_id: nil)
      give_own_workflow(project, tracker, role)
      [project_status, other_project_status].each do |status|
        WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                   old_status_id: old_status.id, new_status_id: status.id,
                                   project_id: project.id)
      end

      get :index, params: { project_id: [project.id.to_s] }

      expect(assigns(:workflow_counts)[[tracker.id, role.id]]).to eq(2)
    end

    # A project that inherits holds no rules of its own, and the page says so
    # with a zero rather than by quietly showing the generic ones.
    it 'counts nothing for a project that inherits' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: old_status.id, new_status_id: new_status.id,
                                 project_id: nil)

      get :index, params: { project_id: [project.id.to_s] }

      expect(assigns(:workflow_counts)[[tracker.id, role.id]]).to be_nil
    end

    it 'keeps the default selection out of the count links' do
      get :index

      expect(assigns(:project_workflow_selection)).to be_nil
    end

    it 'carries a real selection into the count links' do
      get :index, params: { project_id: [project.id.to_s] }

      expect(assigns(:project_workflow_selection)).to eq([project.id])
    end

    it 'refuses a project id that does not resolve' do
      get :index, params: { project_id: ['99999999'] }

      expect(response).to have_http_status(:not_found)
    end
  end

  it 'filters project-specific transitions from global workflow edit view' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    get :edit, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global'],
      used_statuses_only: '0'
    }

    workflows = assigns(:workflows)

    expect(workflows['always']).to all(have_attributes(project_id: nil))
  end

  it 'limits used statuses to the selected project in edit view' do
    give_own_workflow(project, tracker, role)
    give_own_workflow(other_project, tracker, role)
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: other_project_status.id,
      project_id: other_project.id,
      author: false,
      assignee: false
    )

    get :edit, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: [project.id.to_s],
      used_statuses_only: '1'
    }

    status_ids = assigns(:statuses).map(&:id)

    expect(status_ids).to include(project_status.id)
    expect(status_ids).not_to include(new_status.id)
    expect(status_ids).not_to include(other_project_status.id)
  end

  it 'filters project-specific permissions from global workflow permissions view' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: nil
    )
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'required',
      project_id: project.id
    )

    get :permissions, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global'],
      used_statuses_only: '0'
    }

    permissions = assigns(:permissions)

    expect(permissions[old_status.id]['subject']).to eq(['readonly'])
  end

  it 'allows combining global and project workflows in edit view' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    get :edit, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global', project.id.to_s],
      used_statuses_only: '0'
    }

    workflows = assigns(:workflows)

    expect(response).to have_http_status(:ok)
    project_ids = workflows['always'].map(&:project_id)
    expect(project_ids).to include(nil, project.id)
  end

  it 'allows combining global and project workflows in permissions view' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: nil
    )
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'required',
      project_id: project.id
    )

    get :permissions, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global', project.id.to_s],
      used_statuses_only: '0'
    }

    permissions = assigns(:permissions)

    expect(response).to have_http_status(:ok)
    expect(permissions[old_status.id]['subject']).to match_array(%w[readonly required])
  end

  it 'includes global and project statuses when used statuses only with combined selection' do
    give_own_workflow(project, tracker, role)
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    get :permissions, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global', project.id.to_s],
      used_statuses_only: '1'
    }

    status_ids = assigns(:statuses).map(&:id)

    expect(status_ids).to include(new_status.id, project_status.id)
  end

  it 'excludes project-specific statuses when only global is selected' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    get :edit, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global'],
      used_statuses_only: '1'
    }

    status_ids = assigns(:statuses).map(&:id)

    expect(status_ids).to include(new_status.id)
    expect(status_ids).not_to include(project_status.id)
  end

  it 'includes statuses from all projects when project_id=all is selected' do
    give_own_workflow(project, tracker, role)
    give_own_workflow(other_project, tracker, role)
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: other_project_status.id,
      project_id: other_project.id,
      author: false,
      assignee: false
    )

    get :edit, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['all'],
      used_statuses_only: '1'
    }

    status_ids = assigns(:statuses).map(&:id)

    expect(status_ids).to include(new_status.id, project_status.id, other_project_status.id)
  end

  it 'returns 404 for unknown project ids' do
    get :edit, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['999999'],
      used_statuses_only: '0'
    }

    expect(response).to have_http_status(:not_found)
  end

  it 'renders permissions when project is selected without tracker or role' do
    get :permissions, params: {
      project_id: [project.id.to_s],
      used_statuses_only: '0'
    }

    expect(response).to have_http_status(:ok)
  end

  it 'renders permissions when project and role are selected without tracker' do
    get :permissions, params: {
      project_id: [project.id.to_s],
      role_id: [role.id],
      used_statuses_only: '0'
    }

    expect(response).to have_http_status(:ok)
  end

  it 'renders permissions when project and tracker are selected without role' do
    get :permissions, params: {
      project_id: [project.id.to_s],
      tracker_id: [tracker.id],
      used_statuses_only: '0'
    }

    expect(response).to have_http_status(:ok)
  end

  it 'updates both global and project transitions when combined selection is saved (status-first payload)' do
    post :update, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global', project.id.to_s],
      used_statuses_only: '0',
      transitions: {
        old_status.id.to_s => {
          new_status.id.to_s => {
            'always' => '1',
            'author' => '0',
            'assignee' => '0'
          }
        }
      }
    }

    expect(response).to redirect_to(
      edit_workflows_path(
        project_id: ['global', project.id],
        tracker_id: [tracker.id],
        role_id: [role.id],
        used_statuses_only: '0'
      )
    )

    expect(
      WorkflowTransition.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        new_status_id: new_status.id,
        project_id: nil
      )
    ).to be_present
    expect(
      WorkflowTransition.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        new_status_id: new_status.id,
        project_id: project.id
      )
    ).to be_present
  end

  it 'updates both global and project permissions when combined selection is saved (field-first payload)' do
    post :update_permissions, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global', project.id.to_s],
      used_statuses_only: '0',
      permissions: {
        'subject' => {
          old_status.id.to_s => 'readonly'
        }
      }
    }

    expect(response).to redirect_to(
      permissions_workflows_path(
        project_id: ['global', project.id],
        tracker_id: [tracker.id],
        role_id: [role.id],
        used_statuses_only: '0'
      )
    )

    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        field_name: 'subject',
        project_id: nil
      )
    ).to have_attributes(rule: 'readonly')
    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'readonly')
  end

  it 'treats project_id=all as all projects plus generic' do
    get :edit, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['all'],
      used_statuses_only: '0'
    }

    expect(response).to have_http_status(:ok)
    expect(assigns(:global_selected)).to be(true)
    expect(assigns(:selected_projects).size).to eq(Project.count)
  end

  it 'updates both global and project permissions when combined selection is saved (status-first payload)' do
    post :update_permissions, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global', project.id.to_s],
      used_statuses_only: '0',
      permissions: {
        old_status.id.to_s => {
          'subject' => 'readonly'
        }
      }
    }

    expect(response).to redirect_to(
      permissions_workflows_path(
        project_id: ['global', project.id],
        tracker_id: [tracker.id],
        role_id: [role.id],
        used_statuses_only: '0'
      )
    )

    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        field_name: 'subject',
        project_id: nil
      )
    ).to have_attributes(rule: 'readonly')
    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'readonly')
  end

  it 'updates permissions when params are field-first' do
    post :update_permissions, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global', project.id.to_s],
      used_statuses_only: '0',
      permissions: {
        'subject' => {
          old_status.id.to_s => 'required'
        }
      }
    }

    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        field_name: 'subject',
        project_id: nil
      )
    ).to have_attributes(rule: 'required')
    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'required')
  end

  it 'copies project-specific workflow rules when duplicating' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )
    WorkflowPermission.create!(
      tracker_id: target_tracker.id,
      role_id: target_role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'required',
      project_id: nil
    )
    WorkflowTransition.create!(
      tracker_id: target_tracker.id,
      role_id: target_role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    post :duplicate, params: {
      source_tracker_id: tracker.id,
      source_role_id: role.id,
      source_project_id: project.id,
      target_tracker_ids: [target_tracker.id],
      target_role_ids: [target_role.id],
      target_project_ids: [project.id]
    }

    copied_transition = WorkflowTransition.find_by(
      tracker_id: target_tracker.id,
      role_id: target_role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: project.id
    )
    copied_permission = WorkflowPermission.find_by(
      tracker_id: target_tracker.id,
      role_id: target_role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      project_id: project.id
    )
    global_transition = WorkflowTransition.find_by(
      tracker_id: target_tracker.id,
      role_id: target_role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: nil
    )
    global_permission = WorkflowPermission.find_by(
      tracker_id: target_tracker.id,
      role_id: target_role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      project_id: nil
    )

    expect(response).to redirect_to(
      copy_workflows_path(
        source_tracker_id: tracker.id,
        source_role_id: role.id,
        source_project_id: project.id
      )
    )
    expect(copied_transition).to be_present
    expect(copied_permission).to have_attributes(rule: 'readonly')
    expect(global_transition).to be_present
    expect(global_permission).to have_attributes(rule: 'required')
  end

  it 'replaces existing target rules when duplicating to multiple roles' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )
    WorkflowPermission.create!(
      tracker_id: target_tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'required',
      project_id: project.id
    )
    WorkflowPermission.create!(
      tracker_id: target_tracker.id,
      role_id: target_role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'required',
      project_id: project.id
    )
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: target_role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'required',
      project_id: project.id
    )

    post :duplicate, params: {
      source_tracker_id: tracker.id,
      source_role_id: role.id,
      source_project_id: project.id,
      target_tracker_ids: [target_tracker.id],
      target_role_ids: [role.id, target_role.id],
      target_project_ids: [project.id]
    }

    expect(
      WorkflowPermission.find_by(
        tracker_id: target_tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'readonly')
    expect(
      WorkflowPermission.find_by(
        tracker_id: target_tracker.id,
        role_id: target_role.id,
        old_status_id: old_status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'readonly')
    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: target_role.id,
        old_status_id: old_status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'required')
  end

  it 'copies global rules to the same tracker/role on a target project' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: nil
    )

    post :duplicate, params: {
      source_tracker_id: tracker.id,
      source_role_id: role.id,
      source_project_id: 'global',
      target_tracker_ids: [tracker.id],
      target_role_ids: [role.id],
      target_project_ids: [project.id]
    }

    expect(
      WorkflowTransition.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        new_status_id: new_status.id,
        project_id: project.id
      )
    ).to be_present
    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'readonly')
  end

  it 'clears source project selection when source is invalid' do
    post :duplicate, params: {
      source_tracker_id: 'any',
      source_role_id: 'any',
      source_project_id: 'any',
      target_tracker_ids: [target_tracker.id],
      target_role_ids: [target_role.id],
      target_project_ids: [project.id]
    }

    expect(response).to have_http_status(:ok)
    expect(assigns(:source_project_id)).to be_nil
    expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_source_project))
  end

  # M2: regressietest voor niet-bestaand numeriek source_project_id
  it 'rejects a numeric source_project_id that does not exist and preserves target data' do
    existing = WorkflowTransition.create!(
      tracker_id: target_tracker.id,
      role_id: target_role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    post :duplicate, params: {
      source_tracker_id: tracker.id,
      source_role_id: role.id,
      source_project_id: '999999',
      target_tracker_ids: [target_tracker.id],
      target_role_ids: [target_role.id],
      target_project_ids: [project.id]
    }

    expect(response).to have_http_status(:ok)
    expect(assigns(:source_project_id)).to be_nil
    expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_source_project))
    # Target data mag niet gewist zijn
    expect(WorkflowTransition.exists?(existing.id)).to be(true)
  end

  # S4: gedrag bij lege bron (bestaand project, maar geen regels)
  it 'clears target rules when duplicating from a project with no workflow rules' do
    WorkflowTransition.create!(
      tracker_id: target_tracker.id,
      role_id: target_role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    # other_project heeft geen regels
    post :duplicate, params: {
      source_tracker_id: tracker.id,
      source_role_id: role.id,
      source_project_id: other_project.id,
      target_tracker_ids: [target_tracker.id],
      target_role_ids: [target_role.id],
      target_project_ids: [project.id]
    }

    expect(response).to redirect_to(
      copy_workflows_path(
        source_tracker_id: tracker.id,
        source_role_id: role.id,
        source_project_id: other_project.id
      )
    )
    # Gedocumenteerd gedrag: bij lege bron worden bestaande target-regels gewist
    expect(
      WorkflowTransition.find_by(
        tracker_id: target_tracker.id,
        role_id: target_role.id,
        project_id: project.id
      )
    ).to be_nil
  end

  # WP0 / external F02. duplicate used to decide on the resolved project list,
  # which is empty when only the generic workflow is selected; the action then
  # fell through to core, which copied generic to generic and ignored the
  # source project. It now decides on the presence of the plugin's parameters.
  it 'copies from the source project when the generic workflow is the only target' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    post :duplicate, params: {
      source_project_id: project.id.to_s,
      source_tracker_id: tracker.id.to_s,
      source_role_id: role.id.to_s,
      target_tracker_ids: [tracker.id.to_s],
      target_role_ids: [target_role.id.to_s],
      target_project_ids: ['global']
    }

    expect(
      WorkflowTransition.where(project_id: nil, role_id: target_role.id, tracker_id: tracker.id)
    ).to exist
  end

  # WP0 / external F03. load_project_options called render_404, which renders
  # and returns false rather than aborting the action, so duplicate ran on and
  # rendered a second time. Invalid copy targets are now a translated
  # validation error on the copy form.
  describe 'invalid copy targets' do
    def duplicate_with_target(target_project_ids)
      post :duplicate, params: {
        source_tracker_id: tracker.id.to_s,
        source_role_id: role.id.to_s,
        target_tracker_ids: [tracker.id.to_s],
        target_role_ids: [target_role.id.to_s],
        target_project_ids: target_project_ids
      }
    end

    it 'reports a project id that does not exist' do
      expect { duplicate_with_target(['999999']) }.not_to raise_error
      expect(response).to have_http_status(:ok)
      expect(response).to render_template(:copy)
      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_target_project))
    end

    it 'reports a non-numeric project id' do
      expect { duplicate_with_target(['abc']) }.not_to raise_error
      expect(response).to have_http_status(:ok)
      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_target_project))
    end

    # 'all' belongs to the matrix selector, not to the copy form.
    it 'reports the matrix selector keyword as a target' do
      duplicate_with_target(['all'])

      expect(response).to have_http_status(:ok)
      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_target_project))
    end

    it 'writes nothing when a target is invalid' do
      expect { duplicate_with_target([project.id.to_s, '999999']) }
        .not_to change(WorkflowTransition, :count)
    end

    it 'accepts the same project id twice' do
      WorkflowTransition.create!(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: old_status.id,
        new_status_id: new_status.id,
        project_id: nil,
        author: false,
        assignee: false
      )

      post :duplicate, params: {
        source_tracker_id: tracker.id.to_s,
        source_role_id: role.id.to_s,
        target_tracker_ids: [tracker.id.to_s],
        target_role_ids: [target_role.id.to_s],
        target_project_ids: [project.id.to_s, project.id.to_s]
      }

      expect(response).to have_http_status(:found)
      expect(
        WorkflowTransition.where(project_id: project.id, role_id: target_role.id).count
      ).to eq(1)
    end
  end

  # The same de-duplication on the matrix selector: two identical ids used to
  # fail the "all ids resolved" count and produce a 404.
  it 'accepts the same project id twice in the matrix selector' do
    get :edit, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: [project.id.to_s, project.id.to_s],
      used_statuses_only: '0'
    }

    expect(response).to have_http_status(:ok)
  end

  it 'returns 404 for a non-numeric project id in the matrix selector' do
    get :edit, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['abc'],
      used_statuses_only: '0'
    }

    expect(response).to have_http_status(:not_found)
  end

  # WP1: a copy that lands in a project must record the decision too, or the
  # resolver ignores every row it just wrote (INV-3).
  describe 'the copy screen and scopes' do
    before do
      WorkflowRule.delete_all
      ProjectWorkflowScope.delete_all
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: old_status.id, new_status_id: new_status.id)
    end

    def duplicate_to(target_project_id)
      post :duplicate, params: {
        source_tracker_id: tracker.id.to_s, source_role_id: role.id.to_s,
        source_project_id: 'global',
        target_tracker_ids: [target_tracker.id.to_s], target_role_ids: [target_role.id.to_s],
        target_project_ids: [target_project_id]
      }
    end

    it 'gives the target project a scope for what it copied' do
      duplicate_to(project.id.to_s)

      expect(WorkflowTransition.where(project_id: project.id, tracker_id: target_tracker.id,
                                      role_id: target_role.id).count).to eq(1)
      expect(own_workflow?(project, target_tracker, target_role,
                           ProjectWorkflowScope::TRANSITIONS)).to be(true)
      # Nothing was copied into the permissions matrix, and an empty scope there
      # is not the same as no scope.
      expect(own_workflow?(project, target_tracker, target_role,
                           ProjectWorkflowScope::PERMISSIONS)).to be(false)
    end

    it 'creates no scope when the copy targets the generic workflow' do
      duplicate_to('global')

      expect(WorkflowTransition.where(project_id: nil, tracker_id: target_tracker.id,
                                      role_id: target_role.id).count).to eq(1)
      expect(ProjectWorkflowScope.count).to eq(0)
    end
  end

  describe 'the used-statuses filter (external F04)' do
    before { WorkflowTransition.delete_all }

    def generic_transition(from, to, for_role: role)
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: for_role.id,
        old_status_id: from.id, new_status_id: to.id,
        project_id: nil, author: false, assignee: false
      )
    end

    it 'shows the generic statuses for a project that inherits' do
      generic_transition(old_status, new_status)

      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: [project.id.to_s], used_statuses_only: '1' }

      # Before this it found no rows for the project, .presence fell back to
      # every status, and the filter silently did nothing.
      expect(assigns(:statuses).map(&:id)).to contain_exactly(old_status.id, new_status.id)
      expect(assigns(:statuses).size).to be < IssueStatus.count
    end

    it 'shows the generic statuses for a project that inherits on the permissions screen' do
      generic_transition(old_status, new_status)

      get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id],
                                  project_id: [project.id.to_s], used_statuses_only: '1' }

      expect(assigns(:statuses).map(&:id)).to contain_exactly(old_status.id, new_status.id)
    end

    it 'falls back to every status for a project whose own workflow is empty' do
      generic_transition(old_status, new_status)
      give_own_workflow(project, tracker, role)
      Role.all.select(&:consider_workflow?).each do |other|
        give_own_workflow(project, tracker, other) unless other == role
      end

      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: [project.id.to_s], used_statuses_only: '1' }

      # Nothing is in use, and an empty matrix cannot be filled in. This is the
      # one case where showing everything is the right answer -- it is what core
      # does on a fresh installation too.
      expect(assigns(:statuses).size).to eq(IssueStatus.count)
    end

    it 'still shows the generic statuses when no project is selected at all' do
      generic_transition(old_status, new_status)

      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id], used_statuses_only: '1' }

      expect(assigns(:statuses).map(&:id)).to contain_exactly(old_status.id, new_status.id)
    end

    it 'leaves the checkbox off alone' do
      generic_transition(old_status, new_status)

      get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                           project_id: [project.id.to_s], used_statuses_only: '0' }

      expect(assigns(:statuses).size).to eq(IssueStatus.count)
    end
  end

  # finding G01. Core declares find_trackers_roles_and_statuses_for_edit before
  # require_admin, so a render from that callback halts the chain and answers
  # before anyone has checked who is asking.
  describe 'authorization on the matrix screens' do
    before { @request.session[:user_id] = nil }

    %i[edit permissions].each do |action|
      it "sends an anonymous visitor to the login page for a project id that does not exist (#{action})" do
        get action, params: { project_id: ['99999999'] }

        expect(response).to redirect_to(%r{/login})
      end

      it "sends an anonymous visitor to the login page for a project id that does exist (#{action})" do
        get action, params: { project_id: [project.id.to_s] }

        expect(response).to redirect_to(%r{/login})
      end
    end

    it 'answers a logged-in non-administrator with 403, whether the project exists or not' do
      @request.session[:user_id] = 2

      get :edit, params: { project_id: ['99999999'] }
      expect(response).to have_http_status(:forbidden)

      get :edit, params: { project_id: [project.id.to_s] }
      expect(response).to have_http_status(:forbidden)
    end

    it 'still answers an administrator with 404 for a project id that does not exist' do
      @request.session[:user_id] = 1

      get :edit, params: { project_id: ['99999999'] }

      expect(response).to have_http_status(:not_found)
    end

    it 'still answers an administrator with 404 on the copy screen' do
      @request.session[:user_id] = 1

      get :copy, params: { project_id: ['99999999'] }

      expect(response).to have_http_status(:not_found)
    end
  end
end
