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

  it 'updates both global and project transitions when combined selection is saved' do
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

  it 'updates both global and project permissions when combined selection is saved' do
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

  it 'updates both global and project transitions when combined selection is saved' do
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

  it 'updates both global and project permissions when combined selection is saved' do
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
end
