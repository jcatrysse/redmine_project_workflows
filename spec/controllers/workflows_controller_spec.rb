# frozen_string_literal: true

require_relative '../spec_helper'

# What Redmine's own workflow administration screens do once the `workflows`
# table has a project dimension in it: exactly what Redmine does, for the
# generic workflow, and nothing else (ADR-003).
#
# This file used to be 1,956 lines describing the project dimension bolted onto
# core's controller. All of that moved to
# spec/controllers/project_workflow_rules_controller_spec.rb with the screens
# themselves; what is left is the one property core's screens now have to have,
# asserted from both ends -- they read and write the generic workflow only, and
# a `project_id` parameter is ignored rather than honoured.
#
# The second half of that is not a formality. `WorkflowsControllerPatch` no
# longer includes `WorkflowSelection`, so nothing here consults
# `params[:project_id]`; an id in the query string of a core workflow URL is a
# stale bookmark from before WP12, and the wrong answer to it would be to act on
# it (INV-7).
describe WorkflowsController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  before { @request.session[:user_id] = 1 }

  def transition(project_id, from: old_status, to: new_status)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project_id,
                               old_status_id: from.id, new_status_id: to.id)
  end

  def selection
    { role_id: [role.id.to_s], tracker_id: [tracker.id.to_s], used_statuses_only: '0' }
  end

  # WP3 / claude F01. Core's own body groups every workflow row by tracker and
  # role with no project_id predicate at all (INV-4), so a project that had taken
  # one tracker over made the generic workflow look like it had rules it does not
  # have.
  describe 'the summary' do
    it 'counts the generic workflow alone' do
      transition(nil)
      give_own_workflow(project, tracker, role)
      transition(project.id, to: project_status)

      get :index

      expect(assigns(:workflow_counts)[[tracker.id, role.id]]).to eq(1)
    end

    it 'counts nothing when only a project has rules' do
      give_own_workflow(project, tracker, role)
      transition(project.id)

      get :index

      expect(assigns(:workflow_counts)).to be_empty
    end

    it 'ignores a project_id parameter' do
      transition(nil)
      give_own_workflow(project, tracker, role)
      transition(project.id, to: project_status)

      get :index, params: { project_id: [project.id.to_s] }

      expect(response).to have_http_status(:ok)
      expect(assigns(:workflow_counts)[[tracker.id, role.id]]).to eq(1)
    end
  end

  describe 'the transitions matrix' do
    it 'reads the generic workflow alone' do
      transition(nil)
      give_own_workflow(project, tracker, role)
      transition(project.id, to: project_status)

      get :edit, params: selection

      expect(assigns(:workflows)['always'].map(&:project_id)).to eq([nil])
    end

    it 'ignores a project_id parameter rather than honouring it' do
      give_own_workflow(project, tracker, role)
      transition(project.id)

      get :edit, params: selection.merge(project_id: [project.id.to_s])

      expect(response).to have_http_status(:ok)
      expect(assigns(:workflows)['always']).to be_empty
    end

    # A project id that names nothing used to be a 404 from a before_action, and
    # that callback ran before require_admin -- which is finding G01. Now the
    # parameter is not read at all, so there is nothing to answer 404 about.
    it 'renders for a project id that names nothing, because it reads none' do
      transition(nil)

      get :edit, params: selection.merge(project_id: ['99999999'])

      expect(response).to have_http_status(:ok)
    end
  end

  # The "only display statuses that are used by this tracker" checkbox. Core's
  # own query carries no project_id either, so a status that only some project's
  # own workflow uses grew a row on the generic matrix.
  describe 'the used-statuses filter' do
    it 'offers the statuses the generic workflow uses, and no project\'s' do
      transition(nil)
      give_own_workflow(project, tracker, role)
      transition(project.id, from: new_status, to: project_status)

      get :edit, params: { role_id: [role.id.to_s], tracker_id: [tracker.id.to_s] }

      expect(assigns(:statuses)).to include(old_status, new_status)
      expect(assigns(:statuses)).not_to include(project_status)
    end
  end

  describe 'the field permissions matrix' do
    it 'reads the generic workflow alone' do
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                                 old_status_id: old_status.id, field_name: 'subject', rule: 'readonly')
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: old_status.id, field_name: 'subject', rule: 'required')

      get :permissions, params: selection

      expect(assigns(:permissions)[old_status.id]['subject']).to eq(['readonly'])
    end

    it 'ignores a project_id parameter' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: old_status.id, field_name: 'subject', rule: 'required')

      get :permissions, params: selection.merge(project_id: [project.id.to_s])

      expect(response).to have_http_status(:ok)
      expect(assigns(:permissions)[old_status.id]['subject']).to be_nil
    end
  end

  # INV-1. Core's own update calls WorkflowTransition.replace_transitions, which
  # the plugin routes through TransitionWriter with project_id fixed at nil --
  # which is why #update needs no patch of its own. These are what says so: a
  # generic save must not reach a project's rows, and a project_id in the request
  # must not make it.
  describe 'saving' do
    let(:matrix) { { old_status.id.to_s => { new_status.id.to_s => { 'always' => '1' } } } }

    it 'writes the generic workflow and leaves a project\'s rules untouched' do
      give_own_workflow(project, tracker, role)
      transition(project.id, to: project_status)

      patch :update, params: selection.merge(transitions: matrix)

      expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
      expect(WorkflowTransition.where(project_id: project.id).pluck(:new_status_id)).to eq([project_status.id])
    end

    it 'writes the generic workflow even when the request names a project' do
      give_own_workflow(project, tracker, role)

      patch :update, params: selection.merge(project_id: [project.id.to_s], transitions: matrix)

      expect(WorkflowTransition.where(project_id: nil).count).to eq(1)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'writes the generic field permissions and leaves a project\'s untouched' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
      WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                 old_status_id: old_status.id, field_name: 'subject', rule: 'required')

      patch :update_permissions,
            params: selection.merge(permissions: { old_status.id.to_s => { 'subject' => 'readonly' } })

      expect(WorkflowPermission.where(project_id: nil).pluck(:rule)).to eq(['readonly'])
      expect(WorkflowPermission.where(project_id: project.id).pluck(:rule)).to eq(['required'])
    end
  end

  # Core's own copy screen, unpatched since ADR-003. It copies between trackers
  # and roles of the generic workflow; WorkflowRule.copy is routed through the
  # plugin's copier, and what that must not do is reach a project's rules.
  describe 'copying' do
    let(:target_tracker) { trackers(:trackers_002) }

    it 'renders without the plugin\'s project selectors' do
      get :copy

      expect(response).to have_http_status(:ok)
      expect(assigns(:source_project_id)).to be_nil
    end

    it 'copies the generic workflow and leaves every project alone' do
      transition(nil)
      give_own_workflow(project, tracker, role)
      transition(project.id, to: project_status)

      post :duplicate, params: { source_tracker_id: tracker.id, source_role_id: role.id,
                                 target_tracker_ids: [target_tracker.id], target_role_ids: [role.id] }

      expect(WorkflowTransition.where(project_id: nil, tracker_id: target_tracker.id).count).to eq(1)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(1)
      expect(ProjectWorkflowScope.where(project_id: project.id, tracker_id: target_tracker.id)).to be_empty
    end
  end

  # The screens stay administrator-only, which is core's own rule and not
  # something the plugin may relax.
  describe 'authorization' do
    it 'sends an anonymous visitor to the login page' do
      @request.session[:user_id] = nil

      get :edit, params: selection

      expect(response).to redirect_to(%r{/login})
    end

    it 'refuses a signed-in non-administrator' do
      @request.session[:user_id] = 2

      get :edit, params: selection

      expect(response).to have_http_status(:forbidden)
    end
  end
end
