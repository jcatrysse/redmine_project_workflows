# frozen_string_literal: true

require_relative '../spec_helper'

# WP15 item 2 -- every action of the project screens against every kind of
# visitor, as one table.
#
# INV-7 says each project-scoped action authorizes against the project in its
# own path and that no request parameter can widen that. Until now that was
# asserted action by action, wherever an example happened to need it: `#transitions`
# and `#enable` were covered from six angles each and `#permissions`, `#graph`,
# `#inherit` and `#clear` from none. A per-action table cannot have that shape of
# gap -- an action added to the controller without a row here fails the last
# example in this file, which asks the router which actions exist rather than
# trusting the list.
#
# **Why a table rather than more prose examples.** The interesting property is
# uniformity: every action answers the *same* way to the same visitor, and the
# two that differ (`#enable` on a role the project is not offered, `#graph` with
# the drawing switched off) differ for a stated reason. A table shows that at a
# glance and makes a new action's omission loud.
# Every action of the controller, with the verb its route carries and the
# parameters that action needs beyond the three every one of them takes.
# `#enable` is listed with `source: 'empty'` so that a permitted run writes an
# empty scope rather than copying the generic workflow: what is under test here
# is who may reach it, and the cheaper of the two variants says that just as
# well.
PROJECT_WORKFLOW_ACTIONS = [
  [:get,   :transitions,        {}],
  [:get,   :permissions,        {}],
  [:get,   :compare,            { rule_type: ProjectWorkflowScope::TRANSITIONS }],
  [:get,   :graph,              {}],
  [:patch, :update_transitions, { transitions: {} }],
  [:patch, :update_permissions, { permissions: {} }],
  [:post,  :enable,             { rule_type: ProjectWorkflowScope::TRANSITIONS, source: 'empty' }],
  [:delete, :inherit,           { rule_type: ProjectWorkflowScope::TRANSITIONS }],
  [:post, :clear,             { rule_type: ProjectWorkflowScope::TRANSITIONS }]
].freeze

# Which of them write. A refused write has to have written nothing, and that
# is a stronger claim than the status code -- a 403 rendered after the write
# would still be a 403.
PROJECT_WORKFLOW_WRITES = %i[update_transitions update_permissions enable inherit clear].freeze

describe ProjectWorkflowsController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers

  # jsmith holds roles_001 in projects_001 and roles_002 in projects_002, so a
  # permission added to roles_001 is a permission in one project and not in the
  # other. rhill (users_004) holds no membership anywhere.
  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:other_role) { roles(:roles_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:foreign_tracker) { trackers(:trackers_003) }

  def params_for(action_params, overrides = {})
    { project_id: project.id, tracker_id: tracker.id, role_id: role.id }
      .merge(action_params).merge(overrides)
  end

  def call(verb, action, action_params, overrides = {})
    public_send(verb, action, params: params_for(action_params, overrides))
  end

  # The state every action can act on: the project runs its own workflow for
  # this tracker and role, so nothing is refused for a reason other than
  # authorization. Without it `#update_transitions` would answer with a redirect
  # and a "still inheriting" warning for *every* visitor, and the table would be
  # asserting that instead.
  before { give_own_workflow(project, tracker, role) }

  # --- the six visitors -------------------------------------------------------

  # Nobody. Redmine sends an anonymous visitor to the sign-in page rather than
  # answering 403, on writes as well as reads -- core's own `require_login`
  # redirects for every verb and only trims the back_url on non-GET requests.
  describe 'an anonymous visitor' do
    PROJECT_WORKFLOW_ACTIONS.each do |verb, action, action_params|
      it "is sent to the login page by ##{action}" do
        call(verb, action, action_params)

        expect(response).to redirect_to(/login/)
      end
    end
  end

  # Someone with an account but no membership in this project. The permission is
  # granted on roles_001, which rhill does not hold anywhere -- so this is the
  # case where the permission exists in the installation and does not reach the
  # visitor.
  describe 'a logged-in visitor who is not a member of the project' do
    before do
      role.add_permission!(:view_project_workflow_rules, :manage_project_workflow_rules)
      @request.session[:user_id] = 4
    end

    PROJECT_WORKFLOW_ACTIONS.each do |verb, action, action_params|
      it "is refused by ##{action}" do
        call(verb, action, action_params)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe 'a member of the project holding neither permission' do
    before { @request.session[:user_id] = 2 }

    PROJECT_WORKFLOW_ACTIONS.each do |verb, action, action_params|
      it "is refused by ##{action}" do
        call(verb, action, action_params)

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # The reading permission alone. Every screen opens; every write is refused,
  # and writes nothing.
  describe 'a member who may only view the workflow' do
    before do
      role.add_permission!(:view_project_workflow_rules)
      @request.session[:user_id] = 2
    end

    PROJECT_WORKFLOW_ACTIONS.each do |verb, action, action_params|
      if PROJECT_WORKFLOW_WRITES.include?(action)
        it "is refused by ##{action}, and it writes nothing" do
          expect { call(verb, action, action_params) }
            .not_to(change { [ProjectWorkflowScope.count, WorkflowRule.count] })

          expect(response).to have_http_status(:forbidden)
        end
      else
        it "may open ##{action}" do
          call(verb, action, action_params)

          expect(response).to have_http_status(:ok)
        end
      end
    end

    # The consequence of the split, stated once: the screens render read-only.
    it 'sees the matrix as a reference rather than as a form' do
      get :transitions, params: params_for({})

      expect(assigns(:editable)).to be(false)
    end
  end

  # The managing permission alone -- deliberately *without* the reading one,
  # because the two are separate grants and a manager who was never given
  # `view_project_workflow_rules` must still be able to work. Every action of the
  # controller names both permissions in `init.rb`, and this is what asserts it.
  describe 'a member who may manage the workflow' do
    before do
      role.add_permission!(:manage_project_workflow_rules)
      @request.session[:user_id] = 2
    end

    PROJECT_WORKFLOW_ACTIONS.each do |verb, action, action_params|
      it "is answered by ##{action}" do
        call(verb, action, action_params)

        # A write redirects back to the screen it was submitted from; a read
        # renders. Neither is 403 or 404, which is the whole assertion.
        expect(response).to have_http_status(PROJECT_WORKFLOW_WRITES.include?(action) ? :found : :ok)
      end
    end

    it 'sees the matrix as a form' do
      get :transitions, params: params_for({})

      expect(assigns(:editable)).to be(true)
    end
  end

  # An administrator holds no project permission at all in the fixtures, and
  # reaches everything through `User#admin?`.
  describe 'an administrator with no project permission' do
    before { @request.session[:user_id] = 1 }

    PROJECT_WORKFLOW_ACTIONS.each do |verb, action, action_params|
      it "is answered by ##{action}" do
        call(verb, action, action_params)

        expect(response).to have_http_status(PROJECT_WORKFLOW_WRITES.include?(action) ? :found : :ok)
      end
    end
  end

  # --- cross-project substitution ---------------------------------------------
  #
  # "Authorized on A, path project B, tracker and role from A." This is the
  # attack INV-7 is written against, and the reason the project comes from the
  # path and the tracker and role are intersected with lists built from it.

  describe 'a user authorized in one project naming another in the path' do
    before do
      # The permission is granted on roles_001, which jsmith holds in
      # projects_001. In projects_002 the same user holds roles_002, which has
      # neither permission -- so the very same person, tracker and role are
      # involved and only the project differs.
      role.add_permission!(:view_project_workflow_rules, :manage_project_workflow_rules)
      @request.session[:user_id] = 2
    end

    PROJECT_WORKFLOW_ACTIONS.each do |verb, action, action_params|
      it "is refused by ##{action}" do
        public_send(verb, action, params: { project_id: other_project.id, tracker_id: tracker.id,
                                            role_id: role.id }.merge(action_params))

        expect(response).to have_http_status(:forbidden)
      end
    end

    it 'writes nothing into the project it named' do
      PROJECT_WORKFLOW_WRITES.each do |action|
        verb, _name, action_params = PROJECT_WORKFLOW_ACTIONS.detect { |_v, name, _p| name == action }
        expect do
          public_send(verb, action, params: { project_id: other_project.id, tracker_id: tracker.id,
                                              role_id: role.id }.merge(action_params))
        end.not_to(change { [ProjectWorkflowScope.count, WorkflowRule.count] })
      end
    end
  end

  # The other half of the substitution: the project *is* the one the visitor is
  # authorized in, and the tracker or the role belongs somewhere else. Those are
  # picked out of lists built from the project, so a foreign id names nothing --
  # 404 rather than 403, because the visitor may look at this project's workflow
  # and it is the combination that does not exist.
  describe 'a tracker or a role from another project' do
    before do
      role.add_permission!(:view_project_workflow_rules, :manage_project_workflow_rules)
      @request.session[:user_id] = 2
    end

    PROJECT_WORKFLOW_ACTIONS.each do |verb, action, action_params|
      it "answers 404 for a role with no member and no scope here, from ##{action}" do
        call(verb, action, action_params, role_id: roles(:roles_004).id)

        expect(response).to have_http_status(:not_found)
      end

      it "answers 404 for a tracker the project has not enabled, from ##{action}" do
        # Disabled here rather than looked for: every tracker in the fixtures is
        # enabled on projects_001, and a `skip` would have made nine of these
        # examples silently assert nothing.
        project.trackers = project.trackers - [foreign_tracker]

        call(verb, action, action_params, tracker_id: foreign_tracker.id)

        expect(response).to have_http_status(:not_found)
      end
    end
  end

  # --- the two deliberate exceptions ------------------------------------------

  # `#enable` is the one action a role with no member in the project is not
  # offered, even to a manager: taking a *new* workflow over for people who are
  # not members of this project stays an administrator's job (finding F05). It
  # is 403 and not 404 because the combination does exist -- it is the action
  # that is not on offer.
  describe '#enable on a role that already has a scope but no member here' do
    let(:unused_role) { roles(:roles_005) }

    before do
      role.add_permission!(:manage_project_workflow_rules)
      @request.session[:user_id] = 2
      give_own_workflow(project, tracker, unused_role)
    end

    it 'is refused' do
      post :enable, params: params_for({ rule_type: ProjectWorkflowScope::TRANSITIONS, source: 'empty' },
                                       role_id: unused_role.id)

      expect(response).to have_http_status(:forbidden)
    end

    # ...while the undo actions on the same combination are not, which is the
    # whole reason such a row is shown at all.
    it 'can still be returned to inheritance' do
      delete :inherit, params: params_for({ rule_type: ProjectWorkflowScope::TRANSITIONS },
                                          role_id: unused_role.id)

      expect(response).to have_http_status(:found)
      expect(own_workflow?(project, tracker, unused_role)).to be(false)
    end
  end

  # `#graph` answers 404 rather than 403 with the drawing switched off: there is
  # no such screen on the installation, and no permission would help (WP14).
  describe '#graph with the drawing switched off' do
    before do
      Setting.plugin_redmine_project_workflows = { 'graph_enabled' => '0' }
      role.add_permission!(:view_project_workflow_rules, :manage_project_workflow_rules)
    end

    after { Setting.clear_cache }

    it 'answers 404 to a member who may manage the workflow' do
      @request.session[:user_id] = 2

      get :graph, params: params_for({})

      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 to an administrator' do
      @request.session[:user_id] = 1

      get :graph, params: params_for({})

      expect(response).to have_http_status(:not_found)
    end

    # ...and still refuses the visitor who could not have opened it either way,
    # so the switch cannot be used to learn whether a project exists.
    it 'still refuses a visitor who is not a member' do
      @request.session[:user_id] = 4

      get :graph, params: params_for({})

      expect(response).to have_http_status(:forbidden)
    end
  end

  # --- the gap-closer ---------------------------------------------------------

  # What makes the table above a gate rather than a list: an action added to the
  # controller and not to PROJECT_WORKFLOW_ACTIONS fails here. Asked of the routes rather than of
  # the class, because that is what decides whether a request can reach it at
  # all.
  it 'covers every action the routes can reach on this controller' do
    routed = Rails.application.routes.routes.filter_map do |route|
      defaults = route.defaults
      defaults[:action].to_sym if defaults[:controller] == 'project_workflows'
    end.uniq

    expect(routed).not_to be_empty, 'the plugin\'s project workflow routes are gone'
    expect(PROJECT_WORKFLOW_ACTIONS.map { |_verb, action, _params| action }).to match_array(routed)
  end
end
