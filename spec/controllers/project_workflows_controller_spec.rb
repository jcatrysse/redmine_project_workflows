# frozen_string_literal: true

require_relative '../spec_helper'

# WP4. The only place in the plugin where a non-administrator writes workflow
# data, so authorization carries the heaviest coverage: no permission, view
# only, manage, and an attempt to reach a project the permission was not given
# for (INV-7).
describe ProjectWorkflowsController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers

  # jsmith holds roles_001 in projects_001 and roles_002 in projects_002, so a
  # permission added to roles_001 is a permission in one project and not in the
  # other -- which is exactly the case INV-7 is about.
  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:other_role) { roles(:roles_002) }
  let(:unused_role) { roles(:roles_003) }
  let(:tracker) { trackers(:trackers_001) }
  let(:foreign_tracker) { trackers(:trackers_003) }
  let(:new_status) { issue_statuses(:issue_statuses_001) }
  let(:assigned) { issue_statuses(:issue_statuses_002) }
  let(:resolved) { issue_statuses(:issue_statuses_003) }

  def transitions_params(extra = {})
    { project_id: project.id, tracker_id: tracker.id, role_id: role.id }.merge(extra)
  end

  def generic_transition(from, to)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                               old_status_id: from.id, new_status_id: to.id)
  end

  def own_transition(from, to)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                               old_status_id: from.id, new_status_id: to.id)
  end

  def log_in(user_id, *permissions)
    role.add_permission!(*permissions) if permissions.any?
    @request.session[:user_id] = user_id
  end

  describe 'authorization' do
    it 'sends an anonymous visitor to the login page' do
      get :transitions, params: transitions_params

      expect(response).to redirect_to(/login/)
    end

    it 'refuses a member of the project who holds neither permission' do
      log_in(2)

      get :transitions, params: transitions_params

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses somebody who is not a member of the project at all' do
      # rhill holds no membership anywhere in the fixtures, so the permission on
      # roles_001 is one this user never gets.
      log_in(4, :view_project_workflow)

      get :transitions, params: transitions_params

      expect(response).to have_http_status(:forbidden)
    end

    it 'answers a member who may view the workflow' do
      log_in(2, :view_project_workflow)

      get :transitions, params: transitions_params

      expect(response).to have_http_status(:ok)
      expect(assigns(:editable)).to be(false)
    end

    it 'refuses a save from a member who may only view the workflow' do
      log_in(2, :view_project_workflow)
      give_own_workflow(project, tracker, role)

      patch :update_transitions, params: transitions_params(
        transitions: { new_status.id.to_s => { assigned.id.to_s => { 'always' => '1' } } }
      )

      expect(response).to have_http_status(:forbidden)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'refuses a scope action from a member who may only view the workflow' do
      log_in(2, :view_project_workflow)

      post :enable, params: transitions_params(rule_type: ProjectWorkflowScope::TRANSITIONS)

      expect(response).to have_http_status(:forbidden)
      expect(own_workflow?(project, tracker, role)).to be(false)
    end

    it 'answers a member who may manage the workflow' do
      log_in(2, :manage_project_workflow)
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      expect(response).to have_http_status(:ok)
      expect(assigns(:editable)).to be(true)
    end

    # INV-7: the permission is held through roles_001, which jsmith holds in
    # projects_001 only. The other project must be out of reach even though the
    # very same user, the very same tracker and the very same role are involved.
    it 'refuses the same user on a project the permission does not cover' do
      log_in(2, :manage_project_workflow)

      get :transitions, params: transitions_params(project_id: other_project.id, role_id: other_role.id)

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses a write to a project the permission does not cover' do
      log_in(2, :manage_project_workflow)

      post :enable, params: { project_id: other_project.id, tracker_id: tracker.id,
                              role_id: other_role.id, rule_type: ProjectWorkflowScope::TRANSITIONS }

      expect(response).to have_http_status(:forbidden)
      expect(own_workflow?(other_project, tracker, other_role)).to be(false)
    end

    it 'answers an administrator without any project permission' do
      @request.session[:user_id] = 1

      get :transitions, params: transitions_params

      expect(response).to have_http_status(:ok)
    end

    it 'refuses everyone once issue tracking is switched off for the project' do
      log_in(2, :manage_project_workflow)
      project.enabled_module_names = project.enabled_module_names - ['issue_tracking']

      get :transitions, params: transitions_params

      expect(response).to have_http_status(:forbidden)
    end
  end

  # The tracker and the role are picked out of lists built from the project, so
  # a parameter can only ever name something the project already offers.
  describe 'the tracker and the role' do
    before { log_in(2, :manage_project_workflow) }

    it 'answers 404 for a tracker the project has not enabled' do
      project.trackers = project.trackers - [foreign_tracker]

      get :transitions, params: transitions_params(tracker_id: foreign_tracker.id)

      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 for a role that has no member in the project' do
      get :transitions, params: transitions_params(role_id: unused_role.id)

      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 for a tracker id of the wrong shape' do
      # Project.where(id: ['1e5']) resolves to project 1, so the shape of an id
      # is not something to rely on -- the value is matched against a loaded
      # list instead of being queried.
      get :transitions, params: transitions_params(tracker_id: "#{tracker.id}e0")

      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 for a rule type the plugin does not have' do
      post :enable, params: transitions_params(rule_type: 'everything')

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the transitions matrix' do
    before { log_in(2, :manage_project_workflow) }

    # "The generic workflow is visible read-only, as a reference" -- WP4. A
    # project that inherits has no rules of its own to show, and the generic
    # ones are exactly what applies to it (INV-5).
    it 'shows the generic workflow read-only while the project inherits' do
      generic_transition(new_status, assigned)

      get :transitions, params: transitions_params

      expect(assigns(:own_workflow)).to be(false)
      expect(assigns(:editable)).to be(false)
      expect(assigns(:workflows)['always'].map(&:new_status_id)).to eq([assigned.id])
    end

    it "shows the project's own rules once it has taken the workflow over" do
      generic_transition(new_status, assigned)
      give_own_workflow(project, tracker, role)
      own_transition(new_status, resolved)

      get :transitions, params: transitions_params

      expect(assigns(:own_workflow)).to be(true)
      expect(assigns(:editable)).to be(true)
      expect(assigns(:workflows)['always'].map(&:new_status_id)).to eq([resolved.id])
    end

    # An own *empty* workflow is a deliberate configuration (INV-3), so the
    # matrix opens editable and empty rather than falling back to the generic
    # rules.
    it 'shows an own empty workflow as empty rather than as the generic one' do
      generic_transition(new_status, assigned)
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      expect(assigns(:workflows)['always']).to eq([])
      expect(assigns(:editable)).to be(true)
    end

    it 'falls back to every status when the own workflow is empty' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      expect(assigns(:statuses).size).to eq(IssueStatus.count)
    end

    it 'shows every status when the used-statuses filter is switched off' do
      generic_transition(new_status, assigned)

      get :transitions, params: transitions_params(used_statuses_only: '0')

      expect(assigns(:used_statuses_only)).to be(false)
      expect(assigns(:statuses).size).to eq(IssueStatus.count)
    end

    it 'narrows to the statuses the workflow uses when it is switched on' do
      generic_transition(new_status, assigned)

      get :transitions, params: transitions_params

      expect(assigns(:used_statuses_only)).to be(true)
      expect(assigns(:statuses).map(&:id)).to contain_exactly(new_status.id, assigned.id)
    end

    # INV-6: nothing is inherited between projects. A scope on the parent says
    # nothing about the child, and resolving is one row lookup rather than a
    # walk up the tree.
    it 'ignores a scope the parent project has' do
      # The private child of eCookbook, where jsmith is also a member.
      child = projects(:projects_005)
      give_own_workflow(project, tracker, role)
      @request.session[:user_id] = 1

      get :transitions, params: transitions_params(project_id: child.id)

      expect(assigns(:own_workflow)).to be(false)
    end
  end

  describe 'saving the transitions matrix' do
    before { log_in(2, :manage_project_workflow) }

    # INV-1: a project write never touches generic rows.
    it 'writes the project rules and leaves the generic ones alone' do
      generic_transition(new_status, assigned)
      give_own_workflow(project, tracker, role)

      patch :update_transitions, params: transitions_params(
        transitions: { new_status.id.to_s => { resolved.id.to_s => { 'always' => '1' } } }
      )

      expect(response).to redirect_to(
        project_workflow_transitions_path(project, tracker_id: tracker.id, role_id: role.id,
                                                  used_statuses_only: nil)
      )
      expect(WorkflowTransition.where(project_id: project.id).pluck(:new_status_id)).to eq([resolved.id])
      expect(WorkflowTransition.where(project_id: nil).pluck(:new_status_id)).to eq([assigned.id])
    end

    # The three actions of INV-3 stay the only way to take a workflow over: the
    # writers would otherwise create the scope, turning "save" into "enable" on
    # a screen that never offered an editable grid.
    it 'refuses to save while the project inherits, and writes nothing' do
      generic_transition(new_status, assigned)

      patch :update_transitions, params: transitions_params(
        transitions: { new_status.id.to_s => { resolved.id.to_s => { 'always' => '1' } } }
      )

      expect(flash[:warning]).to eq(I18n.t(:notice_project_workflow_not_own))
      expect(own_workflow?(project, tracker, role)).to be(false)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'writes only the tracker and role the request named' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(project, trackers(:trackers_002), role)

      patch :update_transitions, params: transitions_params(
        transitions: { new_status.id.to_s => { resolved.id.to_s => { 'always' => '1' } } }
      )

      expect(WorkflowTransition.where(project_id: project.id).pluck(:tracker_id)).to eq([tracker.id])
    end
  end

  describe 'the field permissions matrix' do
    before { log_in(2, :manage_project_workflow) }

    it 'shows the generic rules read-only while the project inherits' do
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: new_status.id, field_name: 'due_date', rule: 'readonly')

      get :permissions, params: transitions_params

      expect(assigns(:editable)).to be(false)
      expect(assigns(:permissions)[new_status.id]['due_date']).to eq(['readonly'])
    end

    it "shows the project's own rules once it has taken the workflow over" do
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: new_status.id, field_name: 'due_date', rule: 'readonly')
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: new_status.id, field_name: 'start_date', rule: 'required')

      get :permissions, params: transitions_params

      expect(assigns(:editable)).to be(true)
      expect(assigns(:permissions)[new_status.id]).to eq('start_date' => ['required'])
    end

    it 'writes the project rules and leaves the generic ones alone' do
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: new_status.id, field_name: 'due_date', rule: 'readonly')
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      patch :update_permissions, params: transitions_params(
        permissions: { new_status.id.to_s => { 'start_date' => 'required' } }
      )

      expect(WorkflowPermission.where(project_id: project.id).pluck(:field_name)).to eq(['start_date'])
      expect(WorkflowPermission.where(project_id: nil).pluck(:field_name)).to eq(['due_date'])
    end

    it 'refuses to save while the project inherits' do
      patch :update_permissions, params: transitions_params(
        permissions: { new_status.id.to_s => { 'start_date' => 'required' } }
      )

      expect(flash[:warning]).to eq(I18n.t(:notice_project_workflow_not_own))
      expect(WorkflowPermission.count).to eq(0)
    end
  end

  describe 'the rendered page' do
    render_views

    before { log_in(2, :manage_project_workflow) }

    it 'says the generic workflow is only a reference, and offers no form' do
      generic_transition(new_status, assigned)

      get :transitions, params: transitions_params

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_readonly_generic)))
      expect(response.body).not_to include('id="workflow_form"')
      expect(response.body).to include('disabled="disabled"')
    end

    it 'offers the form once the project has its own workflow' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      expect(response.body).to include('id="workflow_form"')
      # The route helper rather than a hand-written path: Redmine addresses a
      # project by its identifier, and the header's filter form -- which posts
      # back to the current path -- carries the id, so a loose pattern would
      # match that one instead.
      expect(response.body).to include(%(action="#{project_workflow_transitions_path(project)}"))
    end

    # The state has to be readable as text, not only as a colour (INV-3).
    it 'names the state in words and offers the actions that would change it' do
      get :transitions, params: transitions_params

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_inherits)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_copy)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_empty)))
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_inherit)))
    end

    it 'offers emptying and returning once the project has taken over' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_clear)))
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_inherit)))
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_copy)))
    end

    it 'offers no action at all to somebody who may only view the workflow' do
      role.add_permission!(:view_project_workflow)
      role.remove_permission!(:manage_project_workflow)

      get :transitions, params: transitions_params

      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_enable_copy)))
    end

    # The writer deletes every rule of a submitted (old status, new status) pair
    # before re-inserting what was sent, so a form that left the author and
    # assignee grids out would silently drop those rules on every save.
    it 'submits all three transition grids, not only the unconditional one' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      %w[always author assignee].each do |rule|
        expect(response.body).to include(%(name="transitions[#{new_status.id}][#{assigned.id}][#{rule}]"))
      end
    end

    it 'renders the field permissions matrix read-only as words' do
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: new_status.id, field_name: 'due_date', rule: 'readonly')

      get :permissions, params: transitions_params

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_readonly)))
      expect(response.body).not_to include('id="workflow_form"')
    end

    it 'renders the field permissions matrix as selects once it may be edited' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      get :permissions, params: transitions_params

      expect(response.body).to include('id="workflow_form"')
      expect(response.body).to match(/name="permissions\[#{new_status.id}\]\[due_date\]"/)
    end
  end

  # The three actions of INV-3, each acting on this project and this one
  # combination and on nothing else.
  describe 'the three actions' do
    before { log_in(2, :manage_project_workflow) }

    it 'gives the project its own workflow as a copy of the generic one' do
      generic_transition(new_status, assigned)

      post :enable, params: transitions_params(rule_type: ProjectWorkflowScope::TRANSITIONS, source: 'copy')

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id).pluck(:new_status_id)).to eq([assigned.id])
      expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
    end

    it 'gives the project its own empty workflow when asked to' do
      generic_transition(new_status, assigned)

      post :enable, params: transitions_params(rule_type: ProjectWorkflowScope::TRANSITIONS, source: 'empty')

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'empties the matrix and keeps the scope' do
      give_own_workflow(project, tracker, role)
      own_transition(new_status, resolved)

      post :clear, params: transitions_params(rule_type: ProjectWorkflowScope::TRANSITIONS)

      expect(own_workflow?(project, tracker, role)).to be(true)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'returns the project to inheritance, scope and rules together' do
      give_own_workflow(project, tracker, role)
      own_transition(new_status, resolved)

      delete :inherit, params: transitions_params(rule_type: ProjectWorkflowScope::TRANSITIONS)

      expect(own_workflow?(project, tracker, role)).to be(false)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'acts on one rule type at a time' do
      post :enable, params: transitions_params(rule_type: ProjectWorkflowScope::PERMISSIONS)

      expect(own_workflow?(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)).to be(true)
      expect(own_workflow?(project, tracker, role, ProjectWorkflowScope::TRANSITIONS)).to be(false)
    end

    it 'says so when there was nothing to change' do
      give_own_workflow(project, tracker, role)

      post :enable, params: transitions_params(rule_type: ProjectWorkflowScope::TRANSITIONS)

      expect(flash[:warning]).to eq(I18n.t(:notice_project_workflow_scope_unchanged))
    end

    it 'comes back to the settings tab when that is where it was asked from' do
      back_url = "/projects/#{project.identifier}/settings/project_workflows"

      post :enable, params: transitions_params(rule_type: ProjectWorkflowScope::TRANSITIONS,
                                               back_url: back_url)

      expect(response).to redirect_to(back_url)
    end

    it 'ignores a way back that points off this installation' do
      post :enable, params: transitions_params(rule_type: ProjectWorkflowScope::TRANSITIONS,
                                               back_url: 'http://example.test/elsewhere')

      expect(response).to redirect_to(
        project_workflow_transitions_path(project, tracker_id: tracker.id, role_id: role.id,
                                                   used_statuses_only: nil)
      )
    end

    it 'comes back to the matrix when that is where it was asked from' do
      post :enable, params: transitions_params(rule_type: ProjectWorkflowScope::TRANSITIONS)

      expect(response).to redirect_to(
        project_workflow_transitions_path(project, tracker_id: tracker.id, role_id: role.id,
                                                   used_statuses_only: nil)
      )
    end
  end
end
