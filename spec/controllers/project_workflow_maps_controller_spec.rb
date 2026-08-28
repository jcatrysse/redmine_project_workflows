# frozen_string_literal: true

require_relative '../spec_helper'

# WP8. The panel behind the link beside the status list on the issue form.
#
# It carries no permission of its own -- it reveals the workflow governing an
# issue the reader is already looking at -- so the authorization examples are
# about the two things that stand in for one: Issue.visible for a saved issue,
# and the project plus +add_issues+ for the new-issue form. And about what a
# request parameter must *not* be able to do (INV-7).
describe ProjectWorkflowMapsController, type: :controller do
  render_views

  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers, :enumerations,
           :issues

  let(:project) { projects(:projects_001) }
  let(:private_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:foreign_tracker) { trackers(:trackers_003) }
  let(:new_status) { issue_statuses(:issue_statuses_001) }
  let(:assigned) { issue_statuses(:issue_statuses_002) }
  let(:closed) { issue_statuses(:issue_statuses_005) }
  let(:second_role) { roles(:roles_002) }

  def generic_transition(from, to, role_id: role.id, author: false, assignee: false)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role_id, project_id: nil,
                               old_status_id: from.respond_to?(:id) ? from.id : from,
                               new_status_id: to.id, author: author, assignee: assignee)
  end

  def own_transition(from, to)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                               old_status_id: from.respond_to?(:id) ? from.id : from,
                               new_status_id: to.id)
  end

  def an_issue(in_project: project, status: new_status, author_id: 2)
    Issue.create!(project: in_project, tracker: tracker, status: status,
                  author_id: author_id, subject: 'workflow map spec')
  end

  # Every string on the panel comes out of the locale files, so an assertion says
  # which key it is looking for rather than repeating the English.
  def escaped(key)
    ERB::Util.html_escape(I18n.t(key))
  end

  describe 'authorization for a saved issue' do
    it 'shows the panel to somebody who can see the issue' do
      issue = an_issue
      @request.session[:user_id] = 2

      get :show, params: { issue_id: issue.id }

      expect(response).to have_http_status(:ok)
    end

    # Issue.visible, not Issue.find: an issue in a project the reader cannot see
    # must be indistinguishable from one that does not exist.
    it 'answers 404 for an issue the reader cannot see' do
      issue = an_issue(in_project: private_project)
      private_project.update!(is_public: false)
      Member.where(project: private_project, user_id: 2).destroy_all
      @request.session[:user_id] = 2

      get :show, params: { issue_id: issue.id }

      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 for an issue that does not exist' do
      @request.session[:user_id] = 2

      get :show, params: { issue_id: 0 }

      expect(response).to have_http_status(:not_found)
    end

    # An archived project's issues are not visible at all: Issue.visible goes
    # through allowed_to_condition, which restricts a read permission to projects
    # that are active or closed. So this is 404, not 403 -- unlike the new-issue
    # path, where the finder matches and allowed_to? is what says no.
    it 'answers 404 for an issue in an archived project' do
      issue = an_issue
      project.reload.archive
      @request.session[:user_id] = 2

      get :show, params: { issue_id: issue.id }

      expect(response).to have_http_status(:not_found)
    end

    # A closed project is read-only, not invisible, so the panel still describes
    # it -- and reading a workflow is a read action everywhere else in the plugin.
    it 'still describes an issue in a closed project' do
      generic_transition(new_status, assigned)
      issue = an_issue
      project.reload.close
      @request.session[:user_id] = 2

      get :show, params: { issue_id: issue.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(assigned.name)
    end

    # INV-7. With an issue in hand the project is the issue's, and a project_id
    # in the request is not consulted at all -- so it cannot move the panel onto
    # another project's workflow.
    it 'ignores a project named by the request' do
      issue = an_issue
      own_transition(new_status, closed)
      give_own_workflow(private_project, tracker, role)
      @request.session[:user_id] = 2

      get :show, params: { issue_id: issue.id, project_id: private_project.id }

      expect(assigns(:project)).to eq(project)
    end
  end

  describe 'authorization for the new-issue form' do
    it 'shows the panel to somebody who may add an issue here' do
      @request.session[:user_id] = 2

      get :show, params: { project_id: project.id, tracker_id: tracker.id }

      expect(response).to have_http_status(:ok)
      expect(assigns(:project)).to eq(project)
    end

    it 'sends an anonymous visitor away when the project is not public' do
      project.update!(is_public: false)

      get :show, params: { project_id: project.id, tracker_id: tracker.id }

      expect(response).to have_http_status(:redirect).or have_http_status(:forbidden)
    end

    # A project whose module is disabled gives 403 rather than 404: the finder
    # matched, and it is allowed_to? that says no.
    it 'refuses a project with issue tracking switched off' do
      EnabledModule.where(project_id: project.id, name: 'issue_tracking').destroy_all
      @request.session[:user_id] = 2

      get :show, params: { project_id: project.id, tracker_id: tracker.id }

      expect(response).to have_http_status(:forbidden)
    end

    it 'answers 404 for a project that does not exist' do
      @request.session[:user_id] = 2

      get :show, params: { project_id: 'no-such-project' }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'the tracker' do
    # INV-7. The parameter picks from a list built from the project, so it can
    # only ever name a tracker the project already offers.
    it 'refuses a tracker the project has not enabled, on the new-issue form' do
      project.trackers = [tracker]
      @request.session[:user_id] = 2

      get :show, params: { project_id: project.id, tracker_id: foreign_tracker.id }

      expect(response).to have_http_status(:not_found)
    end

    it 'falls back to the issue own tracker when the parameter names nothing' do
      issue = an_issue
      project.trackers = [tracker]
      @request.session[:user_id] = 2

      get :show, params: { issue_id: issue.id, tracker_id: foreign_tracker.id }

      expect(response).to have_http_status(:ok)
      expect(assigns(:tracker)).to eq(issue.tracker)
    end

    # The form re-renders whenever the tracker changes, so the link is rebuilt
    # with it and the panel has to follow -- otherwise it would describe a
    # workflow the status list is no longer showing.
    it 'follows a tracker change the form has made' do
      other_tracker = trackers(:trackers_002)
      project.trackers << other_tracker unless project.trackers.include?(other_tracker)
      issue = an_issue
      @request.session[:user_id] = 2

      get :show, params: { issue_id: issue.id, tracker_id: other_tracker.id }

      expect(assigns(:tracker)).to eq(other_tracker)
    end
  end

  describe 'what the panel says' do
    before { @request.session[:user_id] = 2 }

    it 'names the state and the moves the generic workflow allows' do
      generic_transition(new_status, assigned)
      issue = an_issue

      get :show, params: { issue_id: issue.id }

      expect(response.body).to include(escaped(:label_project_workflow_map))
      expect(response.body).to include(escaped(:label_project_workflow_state_inherits))
      expect(response.body).to include(assigned.name)
    end

    # The case the panel exists for: an empty status list with no explanation is
    # indistinguishable from a broken plugin (INV-3).
    it 'says so when the project workflow is deliberately empty' do
      give_own_workflow(project, tracker, role)
      issue = an_issue

      get :show, params: { issue_id: issue.id }

      expect(response.body).to include(escaped(:label_project_workflow_state_own_empty))
      expect(response.body).to include(escaped(:text_project_workflow_map_own_empty))
      expect(response.body).to include(escaped(:text_project_workflow_map_no_outgoing))
    end

    # Finding F02. The sentence was rendered whenever *any* of the reader's roles
    # was in the own_empty state, and it is absolute -- "no change of status is
    # permitted". A reader holding two roles, one overridden-and-empty and one
    # with rules, was told nothing was permitted beside a form offering a full
    # status list. The panel's whole job is to explain that list.
    #
    # Red against the previous commit on the middle two expectations: the
    # absolute sentence was present and the per-role one did not exist.
    it 'does not say nothing is permitted when only one of the reader\'s roles is empty' do
      member = Member.find_by(user_id: 2, project_id: project.id)
      member.roles << second_role
      give_own_workflow(project, tracker, role)
      generic_transition(new_status, assigned, role_id: second_role.id)
      issue = an_issue

      get :show, params: { issue_id: issue.id }

      expect(assigns(:map).role_states.map(&:state)).to contain_exactly(:own_empty, :inherits)
      expect(response.body).not_to include(escaped(:text_project_workflow_map_own_empty))
      expect(response.body).to include(escaped(:text_project_workflow_map_own_empty_some))
      expect(response.body).to include(assigned.name)
    end

    # The other direction, so that the fix is pinned both ways: with every role
    # of the reader's in that state the absolute sentence is the true one and
    # must not be softened into the per-role hedge.
    it 'still says nothing is permitted when every one of the reader\'s roles is empty' do
      member = Member.find_by(user_id: 2, project_id: project.id)
      member.roles << second_role
      give_own_workflow(project, tracker, role)
      give_own_workflow(project, tracker, second_role)
      issue = an_issue

      get :show, params: { issue_id: issue.id }

      expect(assigns(:map).uniform_state).to eq(:own_empty)
      expect(response.body).to include(escaped(:text_project_workflow_map_own_empty))
      expect(response.body).not_to include(escaped(:text_project_workflow_map_own_empty_some))
    end

    it 'says why a move the workflow allows is not on offer' do
      generic_transition(new_status, assigned, author: true)
      issue = an_issue(author_id: 3)

      get :show, params: { issue_id: issue.id }

      expect(response.body).to include(assigned.name)
      expect(response.body).to include(escaped(:text_project_workflow_map_requires_author))
    end

    it 'says what leads into the current status' do
      generic_transition(new_status, assigned)
      issue = an_issue(status: assigned)

      get :show, params: { issue_id: issue.id }

      expect(response.body).to include(escaped(:label_project_workflow_map_leads_here))
      expect(response.body).to include(new_status.name)
    end

    it 'describes the new-issue node on the new-issue form' do
      generic_transition(0, new_status)

      get :show, params: { project_id: project.id, tracker_id: tracker.id }

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_issue_new)))
      expect(response.body).to include(new_status.name)
    end

    # A link that answers 403 is worse than no link, so the offer is gated on the
    # very action the target authorizes.
    it 'offers no link into the project workflow tab without the permission' do
      generic_transition(new_status, assigned)
      issue = an_issue

      get :show, params: { issue_id: issue.id }

      expect(response.body).not_to include('/workflow/transitions')
    end

    it 'offers the link once the reader may open that tab' do
      role.add_permission!(:view_project_workflow_rules)
      generic_transition(new_status, assigned)
      issue = an_issue

      get :show, params: { issue_id: issue.id }

      expect(response.body).to include(ERB::Util.html_escape(
                                         project_workflow_transitions_path(project, tracker_id: tracker.id,
                                                                                   role_id: role.id)
                                       ))
    end

    # An administrator reading a combination the project inherits is sent to the
    # generic workflow, because that is the one that governs -- pre-filled with
    # this project, tracker and role.
    it 'sends an administrator to the generic matrix while the project inherits' do
      generic_transition(new_status, assigned)
      issue = an_issue
      @request.session[:user_id] = 1

      get :show, params: { issue_id: issue.id }

      expect(response.body).to match(%r{href="[^"]*/workflows/edit\?[^"]*project_id(%5B%5D|\[\])=#{project.id}})
    end

    # The standalone page is what a browser without JavaScript lands on, and it
    # is navigated to rather than opened over the form, so it needs a way back.
    # The modal has none: it is closed, not left.
    it 'offers a way back from the standalone page but not from the modal' do
      generic_transition(new_status, assigned)
      issue = an_issue

      get :show, params: { issue_id: issue.id }
      expect(response.body).to include(issue_path(issue))

      get :show, params: { issue_id: issue.id }, xhr: true, format: :js
      expect(response.body).not_to include('contextual')
    end

    it 'answers the JavaScript request by filling core own modal' do
      generic_transition(new_status, assigned)
      issue = an_issue

      get :show, params: { issue_id: issue.id }, xhr: true, format: :js

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("$('#ajax-modal').html(")
      expect(response.body).to include("showModal('ajax-modal'")
    end
  end

  # The plugin's other controllers are behind a permission and are asserted to be
  # so structurally. This one is not, deliberately, so the assertion here is the
  # opposite one: that it has exactly one action, so a second could not be added
  # without a decision about how it is authorized.
  it 'has one action and no permission of its own' do
    actions = described_class.action_methods - ApplicationController.action_methods

    expect(actions.to_a).to eq(['show'])
    %i[view_project_workflow_rules manage_project_workflow_rules].each do |name|
      expect(Redmine::AccessControl.permission(name).actions)
        .not_to include('project_workflow_maps/show')
    end
  end
end
