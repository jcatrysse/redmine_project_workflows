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

  # F01: nothing drove a save with the whole-installation keyword, so nothing
  # said what the redirect after one may carry. The two examples below are the
  # controller half of that fix; the form half -- that the hidden fields hand
  # the keyword back rather than every project id -- is asserted in
  # spec/integration/deface_overrides_spec.rb, which is where it was wrong.
  describe 'saving the whole-installation selection' do
    it 'writes every project and the generic workflow, and redirects with the keyword' do
      Project.sorted.each { |target| give_own_workflow(target, tracker, role) }

      post :update, params: {
        role_id: [role.id],
        tracker_id: [tracker.id],
        project_id: ['all'],
        used_statuses_only: '0',
        transitions: {
          old_status.id.to_s => {
            new_status.id.to_s => { 'always' => '1', 'author' => '0', 'assignee' => '0' }
          }
        }
      }

      expect(response).to redirect_to(
        edit_workflows_path(project_id: ['all'], tracker_id: [tracker.id],
                            role_id: [role.id], used_statuses_only: '0')
      )
      written = WorkflowTransition.where(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: new_status.id
      ).pluck(:project_id)
      expect(written).to match_array(Project.pluck(:id) + [nil])
    end

    it 'does the same for the field permissions matrix' do
      Project.sorted.each { |target| give_own_workflow(target, tracker, role, ProjectWorkflowScope::PERMISSIONS) }

      post :update_permissions, params: {
        role_id: [role.id],
        tracker_id: [tracker.id],
        project_id: ['all'],
        used_statuses_only: '0',
        permissions: { old_status.id.to_s => { 'subject' => 'readonly' } }
      }

      expect(response).to redirect_to(
        permissions_workflows_path(project_id: ['all'], tracker_id: [tracker.id],
                                   role_id: [role.id], used_statuses_only: '0')
      )
      written = WorkflowPermission.where(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, field_name: 'subject'
      ).pluck(:project_id)
      expect(written).to match_array(Project.pluck(:id) + [nil])
    end
  end

  it 'updates both global and project transitions when combined selection is saved (status-first payload)' do
    give_own_workflow(project, tracker, role)

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
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

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
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

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
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

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

  # F07. `copy` runs `invalid_project_selection?` after `load_project_options`
  # and `duplicate` does not, which reads like an omission. It is not: this
  # action never looks at params[:project_id], so a value there names nothing and
  # can widen nothing, and a 404 for a parameter the action ignores would report
  # a fault that does not exist. The asymmetry is deliberate and this pins it, so
  # that "adding the check for symmetry" fails an example that says why.
  #
  # The two selectors `duplicate` does read are validated in full elsewhere, and
  # those examples are above: shape as well as record, for the source and for
  # every target.
  it 'ignores a project_id on the copy POST, which does not read it' do
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                               old_status_id: old_status.id, new_status_id: new_status.id,
                               project_id: nil)

    post :duplicate, params: {
      source_tracker_id: tracker.id,
      source_role_id: role.id,
      source_project_id: 'global',
      target_tracker_ids: [target_tracker.id],
      target_role_ids: [target_role.id],
      target_project_ids: ['global'],
      project_id: ['999999']
    }

    expect(response).to have_http_status(:found)
    expect(flash[:notice]).to be_present
    expect(
      WorkflowTransition.exists?(tracker_id: target_tracker.id, role_id: target_role.id, project_id: nil)
    ).to be(true)
  end

  # F03 and F04, which are the copy screen's two halves of the same question:
  # what did this copy actually do, and does the screen say so.
  describe 'what a copy reports' do
    # The source pair carries field permissions and no transitions, which is
    # entirely ordinary -- a (tracker, role) whose transitions were never
    # configured. copy_for_project deletes the target's rows for the pair across
    # *both* rule types before inserting, so the target's transitions go and
    # nothing replaces them, while its transitions scope survives. The project
    # then has an own **empty** transitions workflow: no issue in it can change
    # status for that role. ADR-001 names that state as the one to keep
    # unreachable by accident, and until now nothing counted or named it.
    it 'says when the copy left a combination with its own empty workflow' do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: old_status.id, new_status_id: new_status.id,
                                 project_id: project.id)
      WorkflowPermission.create!(tracker_id: target_tracker.id, role_id: target_role.id,
                                 old_status_id: old_status.id, field_name: 'subject',
                                 rule: 'readonly', project_id: nil)

      post :duplicate, params: {
        source_tracker_id: target_tracker.id,
        source_role_id: target_role.id,
        source_project_id: 'global',
        target_tracker_ids: [tracker.id],
        target_role_ids: [role.id],
        target_project_ids: [project.id]
      }

      # The scope stays -- INV-3: no write path removes one implicitly -- and it
      # is now empty.
      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id)).to be_empty
      expect(flash[:warning]).to eq(
        I18n.t(:notice_project_workflow_copy_left_empty, count: 1)
      )
    end

    it 'says nothing of the kind when every targeted combination still has rules' do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: target_tracker.id, role_id: target_role.id,
                                 old_status_id: old_status.id, new_status_id: new_status.id,
                                 project_id: nil)

      post :duplicate, params: {
        source_tracker_id: target_tracker.id,
        source_role_id: target_role.id,
        source_project_id: 'global',
        target_tracker_ids: [tracker.id],
        target_role_ids: [role.id],
        target_project_ids: [project.id]
      }

      expect(WorkflowTransition.where(project_id: project.id)).not_to be_empty
      expect(flash[:warning]).to be_nil
      expect(flash[:notice]).to be_present
    end

    # F04. The audit stamp used to cover the cross product of the target
    # trackers and roles, whatever the copy did with them. A copy whose source
    # resolves to the target itself -- "any project, any role, this tracker" --
    # copies nothing at all: copy_for_project skips a pair whose source and
    # target are the same. The stamp ran anyway, so the project's Workflow tab
    # named whoever pressed the button as the last person to change a workflow
    # nothing had changed.
    it 'does not stamp a combination the copy skipped' do
      scope = give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: old_status.id, new_status_id: new_status.id,
                                 project_id: project.id)
      post :duplicate, params: {
        source_tracker_id: tracker.id,
        source_role_id: 'any',
        source_project_id: 'any',
        target_tracker_ids: [tracker.id],
        target_role_ids: [role.id],
        target_project_ids: [project.id]
      }

      expect(scope.reload.updated_by_id).to be_nil
    end

    it 'still stamps a combination the copy did write' do
      scope = give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: target_tracker.id, role_id: target_role.id,
                                 old_status_id: old_status.id, new_status_id: new_status.id,
                                 project_id: nil)
      post :duplicate, params: {
        source_tracker_id: target_tracker.id,
        source_role_id: target_role.id,
        source_project_id: 'global',
        target_tracker_ids: [tracker.id],
        target_role_ids: [role.id],
        target_project_ids: [project.id]
      }

      expect(scope.reload.updated_by_id).to eq(1)
    end
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

  # codex F01 and F02. Core reads a source tracker or role that names nothing
  # as nil, which is also how it spells "same as the target", and drops a
  # target tracker or role that names nothing from its `where(id: ...)`. Both
  # readings are silent, and both make the copy that follows a different copy
  # from the one that was asked for -- on a screen whose every write first
  # deletes what the target pair already had.
  describe 'copy selections that name something that does not exist' do
    before do
      WorkflowRule.delete_all
      ProjectWorkflowScope.delete_all
      WorkflowTransition.create!(
        tracker_id: tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: new_status.id,
        project_id: nil, author: false, assignee: false
      )
      WorkflowTransition.create!(
        tracker_id: target_tracker.id, role_id: role.id,
        old_status_id: old_status.id, new_status_id: project_status.id,
        project_id: nil, author: false, assignee: false
      )
    end

    def duplicate_with(overrides)
      post :duplicate, params: {
        source_tracker_id: tracker.id.to_s,
        source_role_id: role.id.to_s,
        source_project_id: 'global',
        target_tracker_ids: [target_tracker.id.to_s],
        target_role_ids: [target_role.id.to_s],
        target_project_ids: [project.id.to_s]
      }.merge(overrides)
    end

    # Every id in both tables, so that a rejected request is caught whether it
    # inserted rows, deleted the target pair's own before failing, or recorded a
    # scope for a copy that never happened (INV-3).
    def workflow_snapshot
      [WorkflowRule.order(:id).pluck(:id), ProjectWorkflowScope.order(:id).pluck(:id)]
    end

    it 'rejects a source tracker id that does not exist' do
      expect { duplicate_with(source_tracker_id: '999999') }.not_to(change { workflow_snapshot })

      expect(response).to have_http_status(:ok)
      expect(response).to render_template(:copy)
      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_source))
    end

    it 'rejects a source role id that does not exist' do
      expect { duplicate_with(source_role_id: '999999') }.not_to(change { workflow_snapshot })

      expect(response).to have_http_status(:ok)
      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_source))
    end

    # `'1abc'.to_i` is 1, so core resolves this to whichever tracker has id 1.
    it 'rejects a source tracker id that is not a number' do
      expect { duplicate_with(source_tracker_id: "#{tracker.id}abc") }.not_to(change { workflow_snapshot })

      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_source))
    end

    # Not in project context at all: the copy form's target project selector
    # submits nothing when nothing is selected, and that request goes to core.
    it 'rejects a source tracker id that does not exist when no project is named' do
      expect do
        post :duplicate, params: {
          source_tracker_id: '999999',
          source_role_id: role.id.to_s,
          target_tracker_ids: [target_tracker.id.to_s],
          target_role_ids: [target_role.id.to_s]
        }
      end.not_to(change { workflow_snapshot })

      expect(response).to have_http_status(:ok)
      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_source))
    end

    it 'rejects a source role id that is not a number' do
      expect { duplicate_with(source_role_id: "#{role.id}abc") }.not_to(change { workflow_snapshot })

      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_source))
    end

    # The pre-existing readings this guard must not intercept: a source that was
    # left blank is still the project branch's own error, not the new one.
    it 'leaves a blank source tracker to the branch that already reported it' do
      expect { duplicate_with(source_tracker_id: '') }.not_to(change { workflow_snapshot })

      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_source_project))
    end

    it 'rejects a target tracker id that does not exist' do
      expect { duplicate_with(target_tracker_ids: [target_tracker.id.to_s, '999999']) }
        .not_to(change { workflow_snapshot })

      expect(response).to have_http_status(:ok)
      expect(response).to render_template(:copy)
      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_target_tracker_or_role))
    end

    it 'rejects a target role id that does not exist' do
      expect { duplicate_with(target_role_ids: [target_role.id.to_s, '999999']) }
        .not_to(change { workflow_snapshot })

      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_target_tracker_or_role))
    end

    it 'rejects a target tracker id that is not a number' do
      expect { duplicate_with(target_tracker_ids: ["#{target_tracker.id}abc"]) }
        .not_to(change { workflow_snapshot })

      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_target_tracker_or_role))
    end

    it 'rejects a target tracker id that does not exist when no project is named' do
      expect do
        post :duplicate, params: {
          source_tracker_id: tracker.id.to_s,
          source_role_id: role.id.to_s,
          target_tracker_ids: [target_tracker.id.to_s, '999999'],
          target_role_ids: [target_role.id.to_s]
        }
      end.not_to(change { workflow_snapshot })

      expect(response).to have_http_status(:ok)
      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_target_tracker_or_role))
    end

    it 'keeps the submitted target selection on the form it renders back' do
      duplicate_with(target_tracker_ids: [target_tracker.id.to_s, '999999'])

      expect(response).to render_template(:copy)
      expect(assigns(:target_trackers).map(&:id)).to eq([target_tracker.id])
      expect(assigns(:source_project_id)).to eq('global')
    end

    # The rejection is a screen, not just a status code: the form has to come
    # back carrying the message, with the selectors intact, rather than raising
    # on a selection that only half resolved.
    describe 'the page the administrator is left on' do
      render_views

      it 'names what is missing about the target' do
        duplicate_with(target_tracker_ids: [target_tracker.id.to_s, '999999'])

        expect(response.body).to include(I18n.t(:error_workflow_copy_target_tracker_or_role))
        expect(response.body).to include('target_project_ids[]')
      end

      it 'names what is missing about the source' do
        duplicate_with(source_tracker_id: '999999')

        expect(response.body).to include(I18n.t(:error_workflow_copy_source))
      end
    end

    # The three legitimate readings of "any", none of which this may reject.
    it 'still copies with any as the source tracker' do
      duplicate_with(source_tracker_id: 'any')

      expect(response).to have_http_status(:found)
      expect(flash[:error]).to be_nil
      expect(
        WorkflowTransition.where(project_id: project.id, tracker_id: target_tracker.id,
                                 role_id: target_role.id).count
      ).to eq(1)
    end

    it 'still copies with any as the source role' do
      duplicate_with(source_role_id: 'any', target_role_ids: [role.id.to_s])

      expect(response).to have_http_status(:found)
      expect(flash[:error]).to be_nil
    end

    it 'accepts the same target tracker id twice' do
      duplicate_with(target_tracker_ids: [target_tracker.id.to_s, target_tracker.id.to_s])

      expect(response).to have_http_status(:found)
      expect(flash[:error]).to be_nil
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

  # The two defects this session's review found on the administration matrix,
  # both on the path "an administrator presses Save".
  describe 'saving the administration matrix' do
    def matrix_params(transitions)
      { role_id: [role.id], tracker_id: [tracker.id], used_statuses_only: '0',
        transitions: transitions }
    end

    # A cell of the transitions grid is three controls -- always, author,
    # assignee -- and each can independently render as a <select> whose default
    # is core's "no change". The writer keyed its delete on the cell alone, so
    # one submitted column deleted the rows of the other two.
    #
    # Red on the old code: the transition is gone and the flash still says
    # "Successful update".
    describe 'a cell left at (No change)' do
      it 'leaves the workflows that disagree exactly as they were' do
        [project, other_project].each { |target| give_own_workflow(target, tracker, role) }
        WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                   old_status_id: old_status.id, new_status_id: new_status.id,
                                   project_id: project.id, author: false, assignee: false)

        patch :update, params: matrix_params(
          old_status.id.to_s => {
            new_status.id.to_s => { 'always' => 'no_change', 'author' => '0', 'assignee' => '0' }
          }
        ).merge(project_id: [project.id.to_s, other_project.id.to_s])

        expect(
          WorkflowTransition.where(project_id: project.id, old_status_id: old_status.id,
                                   new_status_id: new_status.id)
        ).to exist
      end

      # The same rule on the generic workflow, which is what an administrator
      # editing several trackers or roles at once is doing. The plugin routes
      # core's own WorkflowTransition.replace_transitions through the writer, so
      # this was a change to what stock Redmine does.
      it 'leaves the generic workflow alone as well' do
        WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                   old_status_id: old_status.id, new_status_id: new_status.id,
                                   project_id: nil, author: false, assignee: false)

        patch :update, params: matrix_params(
          old_status.id.to_s => {
            new_status.id.to_s => { 'always' => 'no_change', 'author' => '0', 'assignee' => '0' }
          }
        ).merge(project_id: ['global'])

        expect(
          WorkflowTransition.where(project_id: nil, old_status_id: old_status.id,
                                   new_status_id: new_status.id)
        ).to exist
      end
    end

    # The grid shows what the selection *stores*, so a project that inherits
    # renders empty -- and a plain Save then wrote that emptiness back as an own
    # **empty** workflow, in which no issue in the project can change status at
    # all. ADR-001 names that state as the one to keep unreachable by accident.
    #
    # Red on the old code: a scope appeared, and the only flash was the success
    # notice.
    describe 'a project that still inherits' do
      let(:submission) do
        matrix_params(
          old_status.id.to_s => {
            new_status.id.to_s => { 'always' => '0', 'author' => '0', 'assignee' => '0' }
          }
        ).merge(project_id: [project.id.to_s])
      end

      it 'is not given a workflow of its own by pressing Save' do
        patch :update, params: submission

        expect(ProjectWorkflowScope.where(project_id: project.id)).to be_empty
        expect(WorkflowTransition.where(project_id: project.id)).to be_empty
      end

      it 'says how many combinations it left alone, and does not claim success' do
        patch :update, params: submission

        expect(flash[:warning]).to be_present
        expect(flash[:notice]).to be_nil
      end

      it 'still reports success for the combinations it did write' do
        give_own_workflow(project, tracker, role)

        patch :update, params: submission.deep_merge(
          project_id: ['global', project.id.to_s]
        )

        expect(flash[:notice]).to be_present
        expect(flash[:warning]).to be_nil
      end

      it 'refuses the field permissions matrix the same way' do
        patch :update_permissions, params: {
          role_id: [role.id], tracker_id: [tracker.id], project_id: [project.id.to_s],
          used_statuses_only: '0',
          permissions: { old_status.id.to_s => { 'subject' => 'readonly' } }
        }

        expect(ProjectWorkflowScope.where(project_id: project.id)).to be_empty
        expect(WorkflowPermission.where(project_id: project.id)).to be_empty
        expect(flash[:warning]).to be_present
      end
    end

    # F06. `report_matrix_save` used to infer what a save had written as
    # (projects x trackers x roles) - skipped, and the writers returned `skipped`
    # alone -- so a payload the whitelist had dropped in its entirety, which
    # refuses nothing because it never gets as far as the scopes, was reported as
    # a successful save of the whole selection. The README promises that a
    # rejected value "leaves the rule it names alone rather than clearing it";
    # that is the right behaviour, and telling the operator it was applied undoes
    # half of it.
    describe 'a save whose whole payload was rejected' do
      let(:existing_rule) do
        WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                   old_status_id: old_status.id, new_status_id: new_status.id,
                                   project_id: nil)
      end

      # 'sometimes' is not one of the three rules the matrix can submit, so the
      # whitelist drops the entry before the delete -- which is what keeps the
      # rule it names standing.
      let(:rejected) do
        matrix_params(
          old_status.id.to_s => { new_status.id.to_s => { 'sometimes' => '1' } }
        ).merge(project_id: ['global'])
      end

      it 'does not claim success' do
        existing_rule

        patch :update, params: rejected

        expect(flash[:notice]).to be_nil
        expect(flash[:warning]).to be_present
      end

      it 'leaves the rule it named alone' do
        existing_rule

        patch :update, params: rejected

        expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
      end

      it 'does not claim success on the field permissions matrix either' do
        patch :update_permissions, params: {
          role_id: [role.id], tracker_id: [tracker.id], project_id: ['global'],
          used_statuses_only: '0',
          permissions: { old_status.id.to_s => { 'no_such_field' => 'readonly' } }
        }

        expect(flash[:notice]).to be_nil
        expect(flash[:warning]).to be_present
      end

      # The other way an empty payload arrives, and the one core reports success
      # for: every control left at "(No change)". It is not a rejection, but it
      # is not a save either, and the same message is the honest one.
      it 'does not claim success when every cell was left at no change' do
        patch :update, params: matrix_params(
          old_status.id.to_s => {
            new_status.id.to_s => { 'always' => 'no_change', 'author' => 'no_change',
                                    'assignee' => 'no_change' }
          }
        ).merge(project_id: ['global'])

        expect(flash[:notice]).to be_nil
        expect(flash[:warning]).to be_present
      end
    end

    # Core's own two loops reach a malformed matrix as a String and raise
    # NoMethodError on each_value, which is a 500 rather than a rejection.
    # ProjectWorkflowsController has guarded its copy since WP4.
    it 'rejects a malformed matrix rather than raising' do
      patch :update, params: matrix_params('nonsense').merge(project_id: ['global'])

      expect(response).to have_http_status(:found)
      expect(WorkflowTransition.count).to eq(0)
    end

    it 'rejects a malformed permissions matrix rather than raising' do
      patch :update_permissions, params: {
        role_id: [role.id], tracker_id: [tracker.id], project_id: ['global'],
        used_statuses_only: '0', permissions: 'nonsense'
      }

      expect(response).to have_http_status(:found)
      expect(WorkflowPermission.count).to eq(0)
    end

    # One transaction over the whole selection, as #duplicate already had: a
    # failure half way through otherwise leaves some of the selected workflows
    # rewritten and the rest untouched.
    it 'writes the whole selection or none of it' do
      [project, other_project].each { |target| give_own_workflow(target, tracker, role) }
      writer = RedmineProjectWorkflows::Services::TransitionWriter
      calls = 0
      allow(writer).to receive(:replace_transitions_for_project_id).and_wrap_original do |original, *args|
        calls += 1
        raise ActiveRecord::StatementInvalid, 'boom' if calls > 1

        original.call(*args)
      end

      expect do
        patch :update, params: matrix_params(
          old_status.id.to_s => { new_status.id.to_s => { 'always' => '1' } }
        ).merge(project_id: [project.id.to_s, other_project.id.to_s])
      end.to raise_error(ActiveRecord::StatementInvalid)

      expect(WorkflowTransition.count).to eq(0)
    end
  end
end
