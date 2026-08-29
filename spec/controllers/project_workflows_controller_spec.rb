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

  # The row of INV-3 actions, cut out of the page: the rest of a Redmine screen
  # is full of adjacent anchors, so a pattern about "two links side by side" has
  # to be scoped to the one place that is being asserted about.
  def scope_actions
    response.body[%r{<span class="project-workflow-scope-actions">.*?</span>}m]
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
      log_in(4, :view_project_workflow_rules)

      get :transitions, params: transitions_params

      expect(response).to have_http_status(:forbidden)
    end

    it 'answers a member who may view the workflow' do
      log_in(2, :view_project_workflow_rules)

      get :transitions, params: transitions_params

      expect(response).to have_http_status(:ok)
      expect(assigns(:editable)).to be(false)
    end

    it 'refuses a save from a member who may only view the workflow' do
      log_in(2, :view_project_workflow_rules)
      give_own_workflow(project, tracker, role)

      patch :update_transitions, params: transitions_params(
        transitions: { new_status.id.to_s => { assigned.id.to_s => { 'always' => '1' } } }
      )

      expect(response).to have_http_status(:forbidden)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'refuses a scope action from a member who may only view the workflow' do
      log_in(2, :view_project_workflow_rules)

      post :enable, params: transitions_params(rule_type: ProjectWorkflowScope::TRANSITIONS)

      expect(response).to have_http_status(:forbidden)
      expect(own_workflow?(project, tracker, role)).to be(false)
    end

    it 'answers a member who may manage the workflow' do
      log_in(2, :manage_project_workflow_rules)
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      expect(response).to have_http_status(:ok)
      expect(assigns(:editable)).to be(true)
    end

    # INV-7: the permission is held through roles_001, which jsmith holds in
    # projects_001 only. The other project must be out of reach even though the
    # very same user, the very same tracker and the very same role are involved.
    it 'refuses the same user on a project the permission does not cover' do
      log_in(2, :manage_project_workflow_rules)

      get :transitions, params: transitions_params(project_id: other_project.id, role_id: other_role.id)

      expect(response).to have_http_status(:forbidden)
    end

    it 'refuses a write to a project the permission does not cover' do
      log_in(2, :manage_project_workflow_rules)

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
      log_in(2, :manage_project_workflow_rules)
      project.enabled_module_names = project.enabled_module_names - ['issue_tracking']

      get :transitions, params: transitions_params

      expect(response).to have_http_status(:forbidden)
    end
  end

  # The tracker and the role are picked out of lists built from the project, so
  # a parameter can only ever name something the project already offers.
  describe 'the tracker and the role' do
    before { log_in(2, :manage_project_workflow_rules) }

    it 'answers 404 for a tracker the project has not enabled' do
      project.trackers = project.trackers - [foreign_tracker]

      get :transitions, params: transitions_params(tracker_id: foreign_tracker.id)

      expect(response).to have_http_status(:not_found)
    end

    it 'answers 404 for a role that has no member in the project' do
      get :transitions, params: transitions_params(role_id: unused_role.id)

      expect(response).to have_http_status(:not_found)
    end

    # F05. The tab's rows come from the roles that have members in the project,
    # so a scope a system administrator created for a role with no members --
    # Non member, Anonymous, or an ordinary role whose last member has left --
    # was in force and had no line on the one screen meant to answer "why can
    # nobody move issues here". The role is now visible, and reachable, wherever
    # it already has a scope. What it still does not get is the offer to take a
    # *new* workflow over: that is the decision of 2026-08-26 and it stands.
    describe 'a role with no member that already has a scope' do
      before { give_own_workflow(project, tracker, unused_role) }

      it 'can be opened' do
        get :transitions, params: transitions_params(role_id: unused_role.id)

        expect(response).to have_http_status(:ok)
        expect(assigns(:role)).to eq(unused_role)
      end

      it 'can be returned to the generic workflow' do
        log_in(2, :manage_project_workflow_rules)

        delete :inherit, params: transitions_params(
          role_id: unused_role.id, rule_type: ProjectWorkflowScope::TRANSITIONS
        )

        expect(own_workflow?(project, tracker, unused_role)).to be(false)
      end

      it 'is not offered a new workflow of its own' do
        log_in(2, :manage_project_workflow_rules)

        post :enable, params: transitions_params(
          role_id: unused_role.id, rule_type: ProjectWorkflowScope::PERMISSIONS
        )

        expect(response).to have_http_status(:forbidden)
        expect(own_workflow?(project, tracker, unused_role, ProjectWorkflowScope::PERMISSIONS)).to be(false)
      end
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
    before { log_in(2, :manage_project_workflow_rules) }

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
    before { log_in(2, :manage_project_workflow_rules) }

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

    # F06, the project screen's half. `update_transitions` set the success
    # notice whenever `params[:transitions]` was present, so a payload the
    # whitelist dropped in its entirety -- which changes nothing, by design --
    # reported a successful save; and so did a save that lost the race against a
    # concurrent return to the generic workflow, which the writer refuses.
    describe 'a save that could not be applied' do
      it 'does not claim success when the whole payload was rejected' do
        give_own_workflow(project, tracker, role)
        own_transition(new_status, assigned)

        patch :update_transitions, params: transitions_params(
          transitions: { new_status.id.to_s => { resolved.id.to_s => { 'sometimes' => '1' } } }
        )

        expect(flash[:notice]).to be_nil
        expect(flash[:warning]).to be_present
        expect(WorkflowTransition.where(project_id: project.id).pluck(:new_status_id)).to eq([assigned.id])
      end

      it 'does not claim success when the field permissions payload was rejected' do
        give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

        patch :update_permissions, params: transitions_params(
          permissions: { new_status.id.to_s => { 'no_such_field' => 'required' } }
        )

        expect(flash[:notice]).to be_nil
        expect(flash[:warning]).to be_present
      end

      # The scope disappears between the check and the write -- somebody else
      # pressed "return to the generic workflow" in between. WriteCoordinator
      # locks the scope rows, so the writer refuses the pair; what was missing
      # was the screen saying so instead of "Successful update".
      it 'reports the refusal when the scope went away between the check and the write' do
        give_own_workflow(project, tracker, role)
        coordinator = RedmineProjectWorkflows::Services::WriteCoordinator
        allow(coordinator).to receive(:writable_pairs).and_return([])

        patch :update_transitions, params: transitions_params(
          transitions: { new_status.id.to_s => { resolved.id.to_s => { 'always' => '1' } } }
        )

        expect(flash[:notice]).to be_nil
        expect(flash[:warning]).to eq(I18n.t(:notice_project_workflow_not_own))
      end
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
    before { log_in(2, :manage_project_workflow_rules) }

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

  # F02 (2026-08-27-bundled-followup). MatrixParams#to_plain_hash exists to make a
  # malformed matrix a rejection rather than a crash, and its comment says so --
  # but it asked `respond_to?(:to_h)`, and an Array answers yes and then raises
  # TypeError from `['x'].to_h`. `?transitions[]=x` is how Rails hands that over.
  # So the guard raised inside itself, before any whitelist ran, on the two
  # project entry points and the two administration ones.
  #
  # Both examples assert the **absence** of the 500: the action reaches its
  # redirect and writes nothing, exactly as it does for the String payload that
  # was already covered. Asserting that a new branch exists would prove nothing.
  # Rails re-raises in the test environment, so on the old code these fail with
  # `TypeError: wrong element type String at 0` rather than with a wrong status.
  describe 'a payload that is an array rather than a matrix' do
    before { log_in(2, :manage_project_workflow_rules) }

    it 'rejects it rather than raising, on the transitions matrix' do
      give_own_workflow(project, tracker, role)

      patch :update_transitions, params: transitions_params(transitions: ['x'])

      expect(response).to have_http_status(:found)
      expect(WorkflowTransition.where(project_id: project.id).count).to eq(0)
    end

    it 'rejects it rather than raising, on the field permissions matrix' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      patch :update_permissions, params: transitions_params(permissions: %w[x y])

      expect(response).to have_http_status(:found)
      expect(WorkflowPermission.where(project_id: project.id).count).to eq(0)
    end
  end

  describe 'the rendered page' do
    render_views

    before { log_in(2, :manage_project_workflow_rules) }

    # Redmine 5.1 draws icons from CSS classes; 6.0 and later from SVG sprites.
    # Both shapes go through RedmineProjectWorkflows::VersionHelper, so both
    # branches are asserted here rather than assumed.
    #
    # Asks the production predicate rather than restating its condition. It used
    # to restate it -- `ApplicationController.helpers.respond_to?(:sprite_icon)`
    # -- and a neighbouring plugin back-porting that method made the two agree
    # on the wrong answer (finding F02 of 2026-08-28-claude-plugin-compat-5.1).
    # A spec that spells out the same test as the code it guards can only ever
    # be wrong in the same direction.
    def core_renders_sprites?
      RedmineProjectWorkflows::VersionHelper.core_sprite_icons?
    end

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

    # Finding F05. The two links were rendered with nothing but ERB newline
    # whitespace between them, so a browser showed "Give own workflow (copy of
    # the generic one) Give own empty workflow" as one run of text -- and the
    # second of the pair is the most consequential action either screen offers.
    # A pipe is Redmine's own idiom for adjacent links in running text.
    #
    # Red against the previous commit in both examples: the pattern found the
    # two anchors adjacent with only whitespace between them.
    it 'separates the two actions it offers so they do not read as one sentence' do
      get :transitions, params: transitions_params

      expect(scope_actions).to match(%r{</a>\s*\|\s*<a}m)
    end

    it 'separates the two undo actions the same way' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      expect(scope_actions).to match(%r{</a>\s*\|\s*<a}m)
    end

    it 'offers no action at all to somebody who may only view the workflow' do
      role.add_permission!(:view_project_workflow_rules)
      role.remove_permission!(:manage_project_workflow_rules)

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

    # WP5. The row and column actions come from the same two overrides on core's
    # own workflows/_form, so the project matrix gets them without a screen of
    # its own -- but a cell here is exactly one workflow, so there is nothing for
    # "no change" to mean and it is not offered.
    it 'offers the row and column actions on a matrix it may edit' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      expect(response.body).to include(
        %(data-project-workflow-target="table.transitions-always .new-status-#{assigned.id}:not(:disabled)")
      )
      expect(response.body).to include('data-project-workflow-multiplier="1"')
      expect(response.body).not_to include('data-project-workflow-value="no_change"')
    end

    # The read-only grid is the plugin's own partial, not core's, so the actions
    # are not in it -- and must not be: there is nothing here to change.
    it 'offers no row or column action while the project inherits' do
      generic_transition(new_status, assigned)

      get :transitions, params: transitions_params

      expect(response.body).not_to include('project-workflow-bulk-action')
    end

    # A cell of a project matrix is one workflow, so the sentence that explains
    # a mixed cell would be explaining something that cannot happen here.
    it 'does not explain a mixed cell on a matrix that cannot have one' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      expect(response.body).not_to include('project-workflow-bulk-note')
    end

    # WP6. A project matrix has row and column actions once it is editable, so
    # it gets the counter and the undo -- but a cell there is one workflow, so
    # the note above them still says nothing.
    it 'offers the counter and the undo on an editable project matrix' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      expect(response.body).to include('id="project-workflow-bulk-undo"')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_bulk_unsaved)))
    end

    # A read-only matrix renders the plugin's own grid rather than core's
    # workflows/_form, so the Deface overrides that put the actions there never
    # run and there is nothing to undo.
    it 'does not offer them on a matrix that cannot be edited' do
      get :transitions, params: transitions_params

      expect(response.body).not_to include('project-workflow-bulk-action')
      expect(response.body).not_to include('id="project-workflow-bulk-undo"')
    end

    it 'does not offer them on the field permissions matrix' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      get :permissions, params: transitions_params

      expect(response.body).not_to include('id="project-workflow-bulk-undo"')
    end

    it 'draws the collapsible legend the way the host draws icons' do
      give_own_workflow(project, tracker, role)

      get :transitions, params: transitions_params

      # Core keeps the class on every version, for spacing.
      expect(response.body).to include('icon icon-collapsed')
      if core_renders_sprites?
        expect(response.body).to include('icon--angle-right')
      else
        expect(response.body).not_to include('icon--angle-right')
      end
    end

    it 'draws the field group expander the way the host draws icons' do
      get :permissions, params: transitions_params

      expect(response.body).to include('expander icon icon-expanded')
      if core_renders_sprites?
        expect(response.body).to include('icon--angle-down')
      else
        expect(response.body).not_to include('icon--angle-down')
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
    before { log_in(2, :manage_project_workflow_rules) }

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

  # WP6: what this project's own workflow says that the generic one does not.
  describe '#compare' do
    def compare_params(extra = {})
      transitions_params({ rule_type: ProjectWorkflowScope::TRANSITIONS }.merge(extra))
    end

    describe 'authorization' do
      it 'sends an anonymous visitor to the login page' do
        get :compare, params: compare_params

        expect(response).to redirect_to(/login/)
      end

      it 'refuses a member who holds neither permission' do
        log_in(2)

        get :compare, params: compare_params

        expect(response).to have_http_status(:forbidden)
      end

      # Read-only, so the read permission is enough -- and nothing here can be
      # widened by a parameter: the project comes from the path.
      it 'answers somebody who may only view the workflow' do
        log_in(2, :view_project_workflow_rules)

        get :compare, params: compare_params

        expect(response).to have_http_status(:ok)
      end

      # INV-7: jsmith holds roles_001 in projects_001 only, so the permission
      # added there must not reach projects_002.
      it 'refuses the same user in a project the permission was not given for' do
        log_in(2, :view_project_workflow_rules)

        get :compare, params: compare_params(project_id: other_project.id)

        expect(response).to have_http_status(:forbidden)
      end

      it 'answers 404 for a rule type it does not know' do
        log_in(2, :view_project_workflow_rules)

        get :compare, params: compare_params(rule_type: 'everything')

        expect(response).to have_http_status(:not_found)
      end

      # The link from the administration inventory leads here, and the project's
      # configuration may have moved on since the scope was created. Which
      # refusal comes back depends on what changed, and docs/design.md now
      # carries the table -- it said 404 for all of it until the WP6 review
      # checked it. These two examples are what keeps that table true.
      it 'answers 404 for a tracker the project does not have' do
        log_in(2, :view_project_workflow_rules)
        project.trackers = project.trackers - [foreign_tracker]

        get :compare, params: compare_params(tracker_id: foreign_tracker.id)

        expect(response).to have_http_status(:not_found)
      end

      it 'answers 403 for a project whose issue tracking module is disabled' do
        log_in(2, :view_project_workflow_rules)
        project.enabled_module_names = project.enabled_module_names - ['issue_tracking']

        get :compare, params: compare_params

        expect(response).to have_http_status(:forbidden)
      end
    end

    describe 'what it says' do
      render_views

      before { log_in(2, :view_project_workflow_rules) }

      it 'says there is nothing to compare while the project inherits' do
        generic_transition(new_status, assigned)

        get :compare, params: compare_params

        expect(assigns(:comparison)).to be_nil
        expect(response.body)
          .to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_compare_inherits)))
      end

      it 'lists a transition the project has and the generic workflow does not' do
        give_own_workflow(project, tracker, role)
        own_transition(new_status, assigned)

        get :compare, params: compare_params

        expect(assigns(:comparison).differences.size).to eq(1)
        expect(response.body)
          .to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_compare_project_only)))
      end

      it 'says the two are identical when they are' do
        give_own_workflow(project, tracker, role)
        generic_transition(new_status, assigned)
        own_transition(new_status, assigned)

        get :compare, params: compare_params

        expect(assigns(:comparison)).to be_identical
        expect(response.body)
          .to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_compare_identical)))
      end

      # An own empty workflow is a deliberate state, not an absence, so every
      # generic rule is a difference from it.
      it 'lists every generic rule against an own empty workflow' do
        give_own_workflow(project, tracker, role)
        generic_transition(new_status, assigned)
        generic_transition(assigned, resolved)

        get :compare, params: compare_params

        expect(assigns(:comparison).differences.map(&:state)).to eq(%i[generic_only generic_only])
        expect(response.body)
          .to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_compare_generic_only)))
      end

      # The footnote for a rule the matrix cannot reach: a core field the tracker
      # has since had disabled is still a difference, and no control on a project
      # screen can change it.
      it 'says so when a difference names a field the tracker no longer offers' do
        give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
        WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                   old_status_id: new_status.id, field_name: 'due_date',
                                   rule: 'required')
        tracker.update!(core_fields: Tracker::CORE_FIELDS - ['due_date'])

        get :compare, params: compare_params(rule_type: ProjectWorkflowScope::PERMISSIONS)

        expect(response.body)
          .to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_compare_unreachable_field)))
      end

      it 'stays quiet about it when every difference names a field the matrix has' do
        give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
        WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                   old_status_id: new_status.id, field_name: 'due_date',
                                   rule: 'required')

        get :compare, params: compare_params(rule_type: ProjectWorkflowScope::PERMISSIONS)

        expect(response.body)
          .not_to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_compare_unreachable_field)))
      end

      it 'compares the field permissions when asked for them' do
        give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
        WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: project.id,
                                   old_status_id: new_status.id, field_name: 'due_date',
                                   rule: 'required')

        get :compare, params: compare_params(rule_type: ProjectWorkflowScope::PERMISSIONS)

        expect(assigns(:comparison).rule_type).to eq(ProjectWorkflowScope::PERMISSIONS)
        expect(response.body).to include(ERB::Util.html_escape(I18n.t(:field_due_date)))
        expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_required)))
      end
    end

    describe 'the link to it' do
      render_views

      before { log_in(2, :view_project_workflow_rules) }

      let(:compare_path) do
        project_workflow_compare_path(project, tracker_id: tracker.id, role_id: role.id,
                                               rule_type: ProjectWorkflowScope::TRANSITIONS)
      end

      it 'is on the matrix once the project has its own workflow' do
        give_own_workflow(project, tracker, role)

        get :transitions, params: transitions_params

        expect(response.body).to include(ERB::Util.html_escape(compare_path))
      end

      # Nothing to compare, so no link: the page it leads to would only say so.
      it 'is absent from the matrix while the project inherits' do
        get :transitions, params: transitions_params

        expect(response.body).not_to include(ERB::Util.html_escape(compare_path))
      end
    end
  end

  # F17. Both update actions guard on their matrix parameter and, when it is
  # absent, fell through to `redirect_to matrix_path` with no flash at all.
  # Reachable only through a hand-built PATCH or an API client that omits the
  # matrix, so the practical impact is negligible -- it was the one remaining
  # path on this screen that said nothing, and the whole lesson of the earlier
  # F06 was that a screen must not stay quiet about having done nothing.
  #
  # The existing key, not a new one: it already reads "Nothing was saved. Either
  # no cell was changed, or the values submitted were not accepted", and it is
  # already translated in all eight locale files.
  describe 'a save that carries no matrix at all' do
    before do
      log_in(2, :manage_project_workflow_rules)
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::TRANSITIONS)
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
    end

    it 'says nothing was saved rather than redirecting silently' do
      patch :update_transitions, params: transitions_params

      expect(response).to redirect_to(
        project_workflow_transitions_path(project, tracker_id: tracker.id, role_id: role.id,
                                                   used_statuses_only: nil)
      )
      expect(flash[:warning]).to eq(I18n.t(:notice_project_workflow_save_nothing_applied))
      expect(flash[:notice]).to be_nil
    end

    it 'says the same on the field permissions matrix' do
      patch :update_permissions, params: transitions_params

      expect(flash[:warning]).to eq(I18n.t(:notice_project_workflow_save_nothing_applied))
      expect(flash[:notice]).to be_nil
    end

    # And it must not have become the message for a save that did something.
    it 'is not said for a save that wrote a rule' do
      patch :update_transitions, params: transitions_params(
        transitions: { new_status.id.to_s => { assigned.id.to_s => { 'always' => '1' } } }
      )

      expect(flash[:notice]).to eq(I18n.t(:notice_successful_update))
      expect(flash[:warning]).to be_nil
    end
  end
end
