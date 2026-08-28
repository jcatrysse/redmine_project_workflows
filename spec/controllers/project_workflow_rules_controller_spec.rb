# frozen_string_literal: true

require_relative '../spec_helper'

# WP12 / ADR-003. The plugin's own administration area: the four screens the
# project dimension moved onto, out of core's workflow views and out of a
# 468-line patch on core's controller.
#
# What this file is *for*, beyond repeating what the screens do: the properties
# that only hold because the screens are the plugin's. Authorization runs before
# any finder, every query carries a project_id predicate (INV-4), and taking a
# workflow over is never a side effect of pressing Save (INV-3).
#
# The behavioural depth -- every selection shape, every refused value, every
# message -- is in spec/controllers/workflows_controller_spec.rb, which still
# describes the same actions on core's controller while WP12 is in flight.
describe ProjectWorkflowRulesController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  let(:matrix_params) do
    { tracker_id: [tracker.id.to_s], role_id: [role.id.to_s] }
  end

  before { @request.session[:user_id] = 1 }

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
        public_send(verb, action, params: matrix_params)
        expect(response).to redirect_to(%r{/login}), "#{action} did not ask who was asking"
      end
    end

    # 403 rather than a redirect, because this user *is* logged in: Redmine's own
    # require_admin answers a signed-in non-administrator with a forbidden page.
    it 'refuses a signed-in non-administrator' do
      @request.session[:user_id] = 2

      every_action.each do |action, verb|
        public_send(verb, action, params: matrix_params)
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

      get :edit, params: matrix_params.merge(project_id: [project.id.to_s])
      existing = [response.status, URI.parse(response.location).path]
      get :edit, params: matrix_params.merge(project_id: ['999999'])

      expect([response.status, URI.parse(response.location).path]).to eq(existing)
      expect(existing).to eq([302, '/login'])
    end
  end

  describe 'the summary' do
    render_views

    it 'leaves a project\'s rules out of the generic totals (INV-4)' do
      transition(nil)
      give_own_workflow(project, tracker, role)
      transition(project.id)

      get :index

      expect(assigns(:workflow_counts)[[tracker.id, role.id]]).to eq(1)
    end

    it 'counts the selected project instead of the generic workflow' do
      transition(nil)
      give_own_workflow(project, tracker, role)
      transition(project.id)
      transition(project.id, project_status)

      get :index, params: { project_id: [project.id.to_s] }

      expect(assigns(:workflow_counts)[[tracker.id, role.id]]).to eq(2)
    end

    # The count is a link into the matrix, and it has to carry the selection or
    # the page would show one workflow's numbers and open another's.
    it 'links each count into the matrix for the workflow it counted' do
      give_own_workflow(project, tracker, role)
      transition(project.id)

      get :index, params: { project_id: [project.id.to_s] }

      expect(response.body).to include("project_id%5B%5D=#{project.id}")
      expect(response.body).to include('/project_workflow_rules/edit')
    end

    it 'answers 404 for a project id that names nothing' do
      get :index, params: { project_id: ['999999'] }

      expect(response).to have_http_status(:not_found)
    end
  end

  # The area needs no Deface anchor to be reachable, which is what lets ADR-003
  # delete eleven of them: `Redmine::MenuManager.map :admin_menu` is a stable
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

  describe 'the transitions matrix' do
    render_views

    it 'renders the generic workflow when no project is named' do
      transition(nil)

      get :edit, params: matrix_params

      expect(response).to have_http_status(:ok)
      expect(assigns(:workflows)['always'].map(&:project_id)).to eq([nil])
    end

    it 'renders the selected project\'s own rules, and core\'s own grid' do
      give_own_workflow(project, tracker, role)
      transition(project.id)
      transition(nil)

      get :edit, params: matrix_params.merge(project_id: [project.id.to_s])

      expect(assigns(:workflows)['always'].map(&:project_id)).to eq([project.id])
      # Core's workflows/_form partial, rendered unchanged (ADR-003).
      expect(response.body).to include('transitions[')
      # And the plugin's own selector above it, with the generic workflow named.
      expect(response.body).to include('name="project_id[]"')
      expect(response.body).to include(I18n.t(:label_project_workflows_global))
    end

    it 'carries the selection into the save as a hidden field, keeping "all" a keyword' do
      give_own_workflow(project, tracker, role)

      get :edit, params: matrix_params.merge(project_id: ['all'])

      expect(response.body).to include('name="project_id[]" value="all"')
      expect(response.body).not_to include("name=\"project_id[]\" value=\"#{project.id}\"")
    end

    it 'answers 404 for a project id that names nothing' do
      get :edit, params: matrix_params.merge(project_id: ['999999'])

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'saving the transitions matrix' do
    let(:matrix) { { old_status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } } }

    it 'writes to the named project and leaves the generic workflow alone (INV-1)' do
      give_own_workflow(project, tracker, role)

      patch :update, params: matrix_params.merge(project_id: [project.id.to_s], transitions: matrix)

      expect(WorkflowTransition.where(project_id: project.id).count).to eq(1)
      expect(WorkflowTransition.where(project_id: nil).count).to eq(0)
      expect(response).to redirect_to(%r{project_workflow_rules/edit})
    end

    # INV-3: a project that inherits keeps inheriting. Taking a workflow over is
    # one of the three scope actions, never a side effect of Save -- and the
    # screen says so rather than reporting a success over a table nothing
    # touched (finding F06).
    it 'skips a combination that still inherits, and says so' do
      patch :update, params: matrix_params.merge(project_id: [project.id.to_s], transitions: matrix)

      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
      expect(flash[:notice]).to be_nil
      expect(flash[:warning]).to be_present
    end

    # Core's own two loops reach a submitted matrix with `each_value`, so
    # `transitions[1]=x` arrives as a String and raises NoMethodError -- a 500
    # rather than a rejection (finding F02).
    it 'rejects a matrix of the wrong shape rather than raising' do
      give_own_workflow(project, tracker, role)

      patch :update, params: matrix_params.merge(project_id: [project.id.to_s], transitions: 'x')

      expect(response).to redirect_to(%r{project_workflow_rules/edit})
      expect(WorkflowTransition.count).to eq(0)
    end
  end

  describe 'the field permissions matrix' do
    render_views

    it 'reads the named project\'s rules and renders core\'s cells' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: old_status.id, field_name: 'subject', rule: 'readonly')

      get :permissions, params: matrix_params.merge(project_id: [project.id.to_s])

      expect(response).to have_http_status(:ok)
      expect(assigns(:permissions)[old_status.id]['subject']).to eq(['readonly'])
      expect(response.body).to include("permissions[#{old_status.id}][subject]")
    end

    it 'writes to the named project alone (INV-1)' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      patch :update_permissions,
            params: matrix_params.merge(project_id: [project.id.to_s],
                                        permissions: { old_status.id.to_s => { 'subject' => 'readonly' } })

      expect(WorkflowPermission.where(project_id: project.id).count).to eq(1)
      expect(WorkflowPermission.where(project_id: nil).count).to eq(0)
      expect(response).to redirect_to(%r{project_workflow_rules/permissions})
    end
  end

  describe 'the copy screen' do
    render_views

    it 'offers both project selectors' do
      get :copy

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('name="source_project_id"')
      expect(response.body).to include('name="target_project_ids[]"')
    end

    it 'copies the generic workflow into a project, and records the scope (INV-3)' do
      transition(nil)

      post :duplicate, params: { source_tracker_id: tracker.id, source_role_id: role.id,
                                 source_project_id: 'global',
                                 target_tracker_ids: [tracker.id], target_role_ids: [role.id],
                                 target_project_ids: [project.id.to_s] }

      expect(WorkflowTransition.where(project_id: project.id).count).to eq(1)
      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(response).to redirect_to(%r{project_workflow_rules/copy})
    end

    # A source tracker that names nothing resolves to nil in core, which is also
    # how "same as the target" is spelled -- so a stale form naming a deleted
    # tracker copied from *every* tracker instead of being reported (codex F01).
    it 'refuses a source tracker that names nothing rather than copying from all' do
      transition(nil)

      post :duplicate, params: { source_tracker_id: '999999', source_role_id: role.id,
                                 target_tracker_ids: [tracker.id], target_role_ids: [role.id],
                                 target_project_ids: [project.id.to_s] }

      expect(response).to render_template(:copy)
      expect(flash.now[:error]).to be_present
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    # The plugin's screen always renders the target selector with the generic
    # workflow preselected, so a request carrying no target project at all is a
    # hand-built one or a deliberate deselection. It is reported rather than
    # silently applied to the generic workflow, which is what core's own screen
    # does with the same request -- and core's screen keeps doing it.
    it 'refuses a target selection with no project in it' do
      transition(nil)

      post :duplicate, params: { source_tracker_id: tracker.id, source_role_id: role.id,
                                 target_tracker_ids: [tracker.id], target_role_ids: [role.id] }

      expect(response).to render_template(:copy)
      expect(flash.now[:error]).to eq(I18n.t(:error_workflow_copy_target))
    end
  end

  def transition(project_id, to = new_status)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project_id,
                               old_status_id: old_status.id, new_status_id: to.id)
  end
end
