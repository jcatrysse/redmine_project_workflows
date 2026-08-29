# frozen_string_literal: true

require_relative '../spec_helper'

# WP12 / ADR-003. The plugin's own administration area: the four screens the
# project dimension moved onto, out of core's workflow views and out of a
# 468-line patch on core's controller.
#
# Almost every example here was written against `WorkflowsController` while the
# project dimension lived there, and moved unchanged when the screens did -- the
# file drives the controller by action name, so the move was the class, five
# path helpers and the comments that named core's callback order. That is the
# point of keeping them: what an administrator can do did not change, and a
# large refactoring that quietly changed it would be worse than one that did not
# happen.
#
# What is asserted *because* the screens are the plugin's, and could not be on
# core's: authorization runs before any finder (finding G01), and no work at all
# is done for a request that is going to be refused (finding F05).
#
# What each screen renders -- the selector, the scope panel, the note above the
# matrix, the summary cells -- is in spec/views/project_workflow_rules/.
describe ProjectWorkflowRulesController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  # A third project, so that a selection can hold more populations than it holds
  # bad values -- which is what finding F01 of the follow-up run was about.
  let(:third_project) { projects(:projects_003) }
  let(:role) { roles(:roles_001) }
  let(:target_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:target_tracker) { trackers(:trackers_002) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }
  let(:other_project_status) { issue_statuses(:issue_statuses_004) }

  # The smallest selection either matrix accepts: one tracker, one role, and no
  # project -- which is the generic workflow.
  let(:selection_params) do
    { tracker_id: [tracker.id.to_s], role_id: [role.id.to_s] }
  end

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
        edit_project_workflow_rules_path(project_id: ['all'], tracker_id: [tracker.id],
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
        permissions_project_workflow_rules_path(project_id: ['all'], tracker_id: [tracker.id],
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
      edit_project_workflow_rules_path(
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

  # F14. These two examples used to assert that a *field-first* payload --
  # permissions[<field>][<status>] -- was accepted and written, which
  # `normalize_permissions_params` made true by transposing it. That method is
  # gone, and these are **inverted rather than deleted**, because inverting says
  # strictly more: such a payload is now refused by the writer's whitelist and
  # the screen says so.
  #
  # The finding said there was "no spec" for the transposition. There were these
  # two, and they are the reason the deletion needed a decision rather than a
  # tidy-up. What justifies it: no screen on any supported Redmine produces the
  # shape. WorkflowsHelper#field_permission_tag emits
  # `permissions[<status>][<field>]` on 5.1, 6.1 and 7.0 -- checked in all three
  # checkouts -- and so does the plugin's own project-level grid, which calls the
  # same helper. Core's own update_permissions names its block variables `field`
  # and `rule_by_status_id`, as though the payload were field-first; that is
  # stale naming in core, not a second shape.
  #
  # The transposition also had a live defect: a *mixed* payload, where one key
  # was not numeric, took the transposed branch and silently discarded the real
  # matrix. Refusing a request outright is better than reinterpreting it.
  it 'refuses a field-first permissions payload rather than transposing it' do
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

    post :update_permissions, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global', project.id.to_s],
      used_statuses_only: '0',
      permissions: { 'subject' => { old_status.id.to_s => 'readonly' } }
    }

    expect(WorkflowPermission.count).to eq(0)
    expect(flash[:notice]).to be_nil
    # Both sentences: nothing was saved, and how much was refused. The second
    # arrived with F06 of this same run.
    #
    # This assertion read `count: 2` until F01 of the follow-up run, with a
    # comment explaining the 2 as "one rejected leaf per project of the
    # selection, and the selection is 'global' plus one project". That was the
    # defect written down as though it were the specification: the payload
    # carries **one** leaf, and the sentence it feeds says "%{count} submitted
    # values were not accepted". The number of populations the selection resolves
    # into is not a property of the submission. So this is a corrected
    # assertion, not a relaxed one -- the count it now demands is the smaller
    # number *because* the larger one was wrong, and MatrixSaveResult#+ is where
    # the correction lives.
    expect(flash[:warning]).to include(I18n.t(:notice_project_workflow_save_nothing_applied))
    expect(flash[:warning]).to include(
      I18n.t(:notice_project_workflow_save_rejected_values, count: 1)
    )
  end

  # And the shape every screen actually submits still works, for both
  # populations of the same selection -- which is what the two deleted examples
  # were really covering.
  it 'writes a status-first permissions payload for both populations' do
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

    post :update_permissions, params: {
      role_id: [role.id],
      tracker_id: [tracker.id],
      project_id: ['global', project.id.to_s],
      used_statuses_only: '0',
      permissions: { old_status.id.to_s => { 'subject' => 'readonly' } }
    }

    [nil, project.id].each do |project_id|
      expect(
        WorkflowPermission.find_by(tracker_id: tracker.id, role_id: role.id,
                                   old_status_id: old_status.id, field_name: 'subject',
                                   project_id: project_id)
      ).to have_attributes(rule: 'readonly')
    end
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
      copy_project_workflow_rules_path(
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
      copy_project_workflow_rules_path(
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
  # before anyone has checked who is asking: /workflows/edit told an anonymous
  # visitor 404 for a project id that does not exist and a login redirect for one
  # that does. On this controller the callback order is the plugin's to choose
  # and it chooses authorization first (ADR-003), which is the whole reason these
  # screens are here rather than on core's -- but the answers still have to be
  # asserted, because getting the order right once is not the same as keeping it.
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

    # WP13, audit finding F08. The transaction around a matrix save is right; what
    # was not bounded is what goes inside it. A selection of all projects x all
    # trackers x all roles rewrites every cell of every combination in one
    # transaction, and the row count -- unlike the statement count, which is
    # constant per project -- grows with the selection.
    #
    # The refusal is before the transaction opens, so a save that is too large
    # costs one count and no rows. Above the ceiling and nowhere else: the
    # examples below are the boundary from both sides.
    describe 'a save larger than the ceiling' do
      after { Setting.clear_cache }

      def one_cell
        matrix_params(old_status.id.to_s => { new_status.id.to_s => { 'always' => '1' } })
      end

      it 'writes nothing and says why' do
        Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '1' }
        give_own_workflow(project, tracker, role)

        patch :update, params: one_cell.merge(project_id: [project.id.to_s, 'global'])

        expect(WorkflowTransition.count).to eq(0)
        expect(flash[:error]).to eq(
          I18n.t(:error_project_workflow_save_too_large, count: 2, ceiling: 1)
        )
        expect(flash[:notice]).to be_nil
      end

      # One cell, one tracker, one role, one scope is exactly one rule -- the
      # ceiling is a ceiling, not a limit to stay under.
      it 'lets a save that lands exactly on the ceiling through' do
        Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '1' }

        patch :update, params: one_cell.merge(project_id: ['global'])

        expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
        expect(flash[:error]).to be_nil
      end

      # 0 is the escape hatch for an installation that has measured its own
      # database, and it must not read as "refuse everything".
      it 'refuses nothing when the ceiling is 0' do
        Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '0' }

        patch :update, params: one_cell.merge(project_id: ['global'])

        expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
        expect(flash[:error]).to be_nil
      end

      # The field permissions matrix is the other half of the same screen and
      # counts in the same unit -- one leaf per (status, field).
      it 'refuses an oversized field permissions save too' do
        Setting.plugin_redmine_project_workflows = { 'bulk_write_ceiling' => '1' }

        patch :update_permissions, params: {
          role_id: [role.id], tracker_id: [tracker.id], used_statuses_only: '0',
          project_id: ['global'],
          permissions: { old_status.id.to_s => { 'subject' => 'readonly', 'due_date' => 'required' } }
        }

        expect(WorkflowPermission.count).to eq(0)
        expect(flash[:error]).to be_present
      end
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

    # F02 (2026-08-27-bundled-followup). The same guard, and the shape it did not
    # cover: `?transitions[]=x` arrives as a plain Array, and `Array#to_h` raises
    # TypeError on it -- inside the guard, before any whitelist ran. So the one
    # method written to turn a malformed matrix into a rejection answered 500 for
    # a malformed matrix of that shape, on all four save entry points.
    #
    # These assert the **absence** of the 500 and not the presence of a branch:
    # an Array has to be refused exactly as the String above is, which is what
    # `have_http_status(:found)` says -- a redirect happened, so the action ran to
    # its end. Rails re-raises in the test environment, so the old code fails
    # these with the TypeError itself rather than with a wrong status.
    it 'rejects an array transitions payload rather than raising' do
      patch :update, params: matrix_params(['x']).merge(project_id: ['global'])

      expect(response).to have_http_status(:found)
      expect(WorkflowTransition.count).to eq(0)
    end

    it 'rejects an array permissions payload rather than raising' do
      patch :update_permissions, params: {
        role_id: [role.id], tracker_id: [tracker.id], project_id: ['global'],
        used_statuses_only: '0', permissions: %w[x y]
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
  # F01. The copy screen writes `workflows` for every target project and only
  # then reads `project_workflow_scopes` to decide which combinations need a
  # scope. That is the check-then-act shape 0.1.2 removed from the two matrix
  # writers and the two scope actions by giving them a locked read -- and the
  # copy was left out of, while docs/design.md went on claiming every path took
  # scope rows before workflow rows.
  #
  # The quiet consequence, reproduced from Rails with two live connections
  # before this was written: for a combination whose scope has no rules under it
  # the copy's delete locks nothing, so a concurrent return to the generic
  # workflow never collides. The copy reads a scope row the return has deleted
  # but not committed, concludes the combination is already scoped, creates
  # nothing, and commits its rules under a scope that is gone -- one rule in
  # `workflows` invisible to the resolver (INV-3), no error, and
  # "Successful update" on the screen.
  #
  # Asserted here as statement order on one connection, which is deterministic
  # and cheap on all nine cells. The two-connection outcome examples for the
  # same lock are in spec/services/workflow_concurrency_spec.rb; a third one for
  # this path would need a timing window in nine cells to assert the property
  # this example already pins.
  describe 'the lock the copy screen takes' do
    before { skip('the adapter has no row locking to assert') unless row_locking? }

    def duplicate_into_project
      post :duplicate, params: {
        source_tracker_id: tracker.id.to_s,
        source_role_id: role.id.to_s,
        source_project_id: 'global',
        target_tracker_ids: [target_tracker.id.to_s],
        target_role_ids: [target_role.id.to_s],
        target_project_ids: [project.id.to_s]
      }
    end

    it 'is taken on the scope rows before the copy writes a rule' do
      give_own_workflow(project, target_tracker, target_role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: old_status.id, new_status_id: new_status.id)

      statements = statements_during { duplicate_into_project }

      expect(index_of_scope_lock(statements)).not_to be_nil
      expect(index_of_first_rule_write(statements)).not_to be_nil
      expect(index_of_scope_lock(statements)).to be < index_of_first_rule_write(statements)
    end

    # The lock has to cover the combination whose scope carries no rules -- the
    # own *empty* workflow -- because that is the one the copy's own delete
    # cannot lock for it, and the one the quiet interleaving needs.
    it 'covers a scope that has no rules under it' do
      give_own_workflow(project, target_tracker, target_role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: old_status.id, new_status_id: new_status.id)

      # What the FOR UPDATE statement itself returned, not what it was asked
      # for: the row ids travel as bind parameters, so the SQL text cannot say
      # which rows were locked.
      locked = nil
      scope_writer = RedmineProjectWorkflows::Services::ScopeWriter
      allow(scope_writer).to receive(:lock_scopes_for_copy).and_wrap_original do |original, **kwargs|
        locked = original.call(**kwargs)
      end

      duplicate_into_project

      expect(locked).to include([project.id, target_tracker.id, target_role.id])
    end

    # A copy whose only target is the generic workflow has no scope to lock and
    # must not go looking for one: the generic workflow is the one thing that
    # cannot be inherited (INV-3). It is not unlocked, though -- since WP13 it
    # takes the plugin's own coordination row instead (audit finding F07), in
    # WorkflowRule.copy_for_project, which is also the path **Redmine's own**
    # copy screen writes generic rules through.
    it 'is taken on the plugin\'s own row, not a scope row, for a copy into the generic workflow' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: old_status.id, new_status_id: new_status.id)
      give_own_workflow(project, tracker, role)

      statements = statements_during do
        post :duplicate, params: {
          source_tracker_id: tracker.id.to_s,
          source_role_id: role.id.to_s,
          source_project_id: project.id.to_s,
          target_tracker_ids: [target_tracker.id.to_s],
          target_role_ids: [target_role.id.to_s],
          target_project_ids: ['global']
        }
      end

      expect(index_of_scope_lock(statements)).to be_nil
      expect(index_of_write_lock(statements)).not_to be_nil
      expect(index_of_first_rule_write(statements)).not_to be_nil
      expect(index_of_write_lock(statements)).to be < index_of_first_rule_write(statements)
    end

    # Both rule types, because a copy replaces both: it deletes the target
    # pair's transitions *and* its field permissions before it inserts, so a
    # coordination row for only one of them would leave the other exactly as
    # unlocked as it was.
    it 'covers both rule types for a copy into the generic workflow' do
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: old_status.id, new_status_id: new_status.id)
      give_own_workflow(project, tracker, role)

      post :duplicate, params: {
        source_tracker_id: tracker.id.to_s,
        source_role_id: role.id.to_s,
        source_project_id: project.id.to_s,
        target_tracker_ids: [target_tracker.id.to_s],
        target_role_ids: [target_role.id.to_s],
        target_project_ids: ['global']
      }

      expect(ProjectWorkflowWriteLock.where(tracker_id: target_tracker.id, role_id: target_role.id)
                                     .pluck(:rule_type).sort)
        .to eq(ProjectWorkflowScope::RULE_TYPES.sort)
    end
  end
  # F05, and the reason ADR-003 is worth its diff. Core declares
  # find_trackers_roles_and_statuses_for_edit *before* require_admin,
  # byte-identically on 5.1, 6.1 and 7.0. With ?project_id[]=all&tracker_id[]=all
  # an unauthenticated request ran Project.sorted.map(&:id) over every project
  # row, a scope query with an IN list of every project id, and an OR query with
  # a branch per (project, tracker) -- all before anyone had checked who was
  # asking. Noise on fifty projects; tens of milliseconds and megabytes of
  # ActiveRecord objects per anonymous GET on five thousand, repeatable at will.
  #
  # On core's controller the only available fix was a guard clause inside the
  # patched finder: a second, scoped require_admin was rejected in
  # docs/DECISIONS.md:93 and is worse than it looks, because ActiveSupport's
  # callback dedupe compares only kind and filter -- `only:` is a separate :if
  # condition -- so `prepend_before_action :require_admin, only: [...]` would
  # DELETE core's unconditional registration and leave index, copy and duplicate
  # ungated (F18). Here there is nothing to work around: `require_admin` is
  # simply declared first. These examples are what says so.
  describe 'the work the administration matrices do before authorization' do
    def edit_the_whole_installation
      get :edit, params: { project_id: ['all'], tracker_id: ['all'], role_id: [role.id.to_s] }
    end

    it 'runs no plugin query for an unauthenticated request' do
      @request.session[:user_id] = nil

      statements = statements_during { edit_the_whole_installation }

      expect(statements.grep(/project_workflow_scopes/i)).to be_empty
      expect(statements.grep(/\bfrom\s+\W?workflows\W/i)).to be_empty
      expect(assigns(:statuses)).to be_nil
    end

    it 'runs no plugin query for a logged-in non-administrator' do
      @request.session[:user_id] = 2

      statements = statements_during { edit_the_whole_installation }

      expect(response).to have_http_status(:forbidden)
      expect(statements.grep(/project_workflow_scopes/i)).to be_empty
      expect(assigns(:projects)).to be_nil
    end

    # The guard prepares data and does not authorize -- require_admin still
    # decides -- so an administrator must see exactly what they saw before.
    it 'still prepares everything for an administrator' do
      edit_the_whole_installation

      expect(response).to have_http_status(:ok)
      expect(assigns(:statuses)).to be_present
      expect(assigns(:projects)).to be_present
    end
  end

  # F06 (2026-08-27-bundled). The count is only worth having if it reaches the
  # screen. A save whose whitelist dropped some entries but not all used to get
  # `notice_successful_update` and nothing else -- `written` was positive, so the
  # partial refusal was invisible.
  describe 'a save the whitelist partly refused' do
    def matrix_params(transitions)
      { role_id: [role.id], tracker_id: [tracker.id], used_statuses_only: '0',
        transitions: transitions }
    end

    it 'reports the save and the part that was refused' do
      give_own_workflow(project, tracker, role)

      patch :update, params: matrix_params(
        old_status.id.to_s => { new_status.id.to_s => { 'always' => '1', 'author' => 'not_a_value' } }
      ).merge(project_id: [project.id.to_s])

      expect(flash[:notice]).to eq(I18n.t(:notice_successful_update))
      expect(flash[:warning]).to eq(
        I18n.t(:notice_project_workflow_save_rejected_values, count: 1)
      )
    end

    # A save with nothing refused must not acquire the sentence.
    it 'says nothing about refusals when there were none' do
      give_own_workflow(project, tracker, role)

      patch :update, params: matrix_params(
        old_status.id.to_s => { new_status.id.to_s => { 'always' => '1' } }
      ).merge(project_id: [project.id.to_s])

      expect(flash[:notice]).to eq(I18n.t(:notice_successful_update))
      expect(flash[:warning]).to be_nil
    end

    # And the two warnings coexist rather than one replacing the other: a
    # selection can both leave an inheriting combination alone and have had a
    # value refused.
    #
    # The two counts in this example are deliberately different numbers, and
    # that is the point of it after F01 of the follow-up run: `skipped` is 1
    # because one of the two selected projects still inherits -- a count of
    # combinations, and it adds across the selection -- while `rejected` is 1
    # because the request carried one unacceptable value, whatever the selection
    # was resolved into. It asserted `count: 2` for the refusal before, which
    # was the multiplication rather than the requirement; corrected, not
    # weakened.
    it 'says both when a combination was skipped and a value refused' do
      give_own_workflow(project, tracker, role)

      patch :update, params: matrix_params(
        old_status.id.to_s => { new_status.id.to_s => { 'always' => '1', 'author' => 'not_a_value' } }
      ).merge(project_id: [project.id.to_s, other_project.id.to_s])

      expect(flash[:warning]).to include(
        I18n.t(:notice_project_workflow_save_skipped_inheriting, count: 1)
      )
      expect(flash[:warning]).to include(
        I18n.t(:notice_project_workflow_save_rejected_values, count: 1)
      )
    end

    # The shape F01 was actually filed about: many populations, one bad value.
    # Three projects and 'global' is four populations of one submission, and the
    # operator has to be told about one refused value rather than four. With the
    # summing #+ this reported four, and no example in the suite could see it,
    # because both examples that named the number had encoded the multiplied one.
    it 'reports one refused value once however many projects the selection holds' do
      [project, other_project, third_project].each { |target| give_own_workflow(target, tracker, role) }

      patch :update, params: matrix_params(
        old_status.id.to_s => { new_status.id.to_s => { 'always' => '1', 'author' => 'not_a_value' } }
      ).merge(project_id: ['global', project.id.to_s, other_project.id.to_s, third_project.id.to_s])

      expect(flash[:notice]).to eq(I18n.t(:notice_successful_update))
      expect(flash[:warning]).to eq(
        I18n.t(:notice_project_workflow_save_rejected_values, count: 1)
      )
    end
  end

  describe 'authorization' do
    # Every action, from one list, so that a new action cannot be added without
    # appearing here. INV-7: these are administration screens and they stay
    # administrator-only.
    let(:every_action) do
      { index: :get, edit: :get, permissions: :get, copy: :get,
        update: :patch, update_permissions: :patch, duplicate: :post }
    end

    it 'sends an anonymous visitor to the login page, whatever it asks for' do
      @request.session[:user_id] = nil

      every_action.each do |action, verb|
        public_send(verb, action, params: selection_params)
        expect(response).to redirect_to(%r{/login}), "#{action} did not ask who was asking"
      end
    end

    # 403 rather than a redirect, because this user *is* logged in: Redmine's own
    # require_admin answers a signed-in non-administrator with a forbidden page.
    it 'refuses a signed-in non-administrator' do
      @request.session[:user_id] = 2

      every_action.each do |action, verb|
        public_send(verb, action, params: selection_params)
        expect(response).to have_http_status(:forbidden), "#{action} let a non-administrator in"
      end
    end

    # The reason these screens are here rather than on core's controller.
    # Core declares its finders *before* require_admin, so /workflows/edit
    # answered an anonymous visitor 404 for a project id that does not exist and
    # a login redirect for one that does -- which is a list of existing project
    # ids, handed out before anyone had checked who was asking (finding G01).
    #
    # Here the callback order is the plugin's to choose. Both answers are the
    # login page.
    #
    # The status and the destination, not the whole Location: Redmine 5.1 appends
    # a `back_url` and 6.1 and 7.0 do not, and that parameter is the visitor's own
    # request echoed back -- it cannot tell them anything they did not already
    # send. What would be a leak is a *different kind* of answer for the two ids,
    # which is what core's own screen gives.
    it 'tells an anonymous visitor nothing about which project ids exist' do
      @request.session[:user_id] = nil

      get :edit, params: selection_params.merge(project_id: [project.id.to_s])
      existing = [response.status, URI.parse(response.location).path]
      get :edit, params: selection_params.merge(project_id: ['999999'])

      expect([response.status, URI.parse(response.location).path]).to eq(existing)
      expect(existing).to eq([302, '/login'])
    end
  end

  # The area needs no Deface anchor to be reachable, which is what let ADR-003
  # delete ten of them: `Redmine::MenuManager.map :admin_menu` is a stable
  # extension point on all three supported versions.
  describe 'the way in' do
    it 'is registered in the administration menu, pointing at the summary' do
      item = Redmine::MenuManager.items(:admin_menu).detect { |node| node.name == :project_workflow_rules }

      expect(item).to be_present
      # Redmine's MenuManager roots the controller when it stores the item, so the
      # leading slash is core's and not something init.rb passed.
      expect(item.url).to eq(controller: '/project_workflow_rules', action: 'index')
    end
  end

  # The plugin's own screen always renders the target project selector with the
  # generic workflow preselected and its blank option disabled, so a request
  # carrying no target project at all is a deliberate deselection or a hand-built
  # POST -- and every write on this screen first *deletes* what the target pair
  # already had. It is reported rather than silently applied to the generic
  # workflow, which is what core's own screen does with the same request and goes
  # on doing (docs/DECISIONS.md; reversible in one branch).
  it 'refuses a target selection with no project in it' do
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                               old_status_id: old_status.id, new_status_id: new_status.id)

    post :duplicate, params: { source_tracker_id: tracker.id, source_role_id: role.id,
                               target_tracker_ids: [tracker.id], target_role_ids: [role.id] }

    expect(response).to render_template(:copy)
    expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_target))
  end
end
