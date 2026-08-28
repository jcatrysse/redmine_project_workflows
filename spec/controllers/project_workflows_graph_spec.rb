# frozen_string_literal: true

require_relative '../spec_helper'

# WP9. The workflow as a drawing, on the project screen.
#
# A file of its own beside project_workflows_controller_spec.rb, which is about
# the two matrices and the three scope actions and is already long. What is
# tested here is what is different about this action: it is the only one that
# takes a *selection* of roles, and the registration trap -- an action missing
# from init.rb answers 403 for everybody, administrators included, with no error
# anywhere that says why.
describe ProjectWorkflowsController, type: :controller do
  # The drawing is markup rather than a collection, so most of what is asserted
  # here is only in the rendered page: a viewBox that clips, a status name that
  # is not escaped and a selector that should not be there are all invisible to
  # an assertion on an instance variable.
  render_views

  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers

  # jsmith holds roles_001 in projects_001 and roles_002 in projects_002, so a
  # permission added to roles_001 is a permission in one project and not in the
  # other -- the case INV-7 is about.
  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:other_role) { roles(:roles_002) }
  # An ordinary role with no member in projects_001, so the project does not
  # offer it unless a scope brings it in.
  let(:unused_role) { roles(:roles_003) }
  let(:tracker) { trackers(:trackers_001) }
  let(:foreign_tracker) { trackers(:trackers_003) }
  let(:new_status) { issue_statuses(:issue_statuses_001) }
  let(:assigned) { issue_statuses(:issue_statuses_002) }
  let(:closed) { issue_statuses(:issue_statuses_005) }

  def graph_params(extra = {})
    { project_id: project.id, tracker_id: tracker.id }.merge(extra)
  end

  # +from+ may be 0, which is core's "new issue" pseudo-status and is not an
  # IssueStatus at all -- it is the entry point of every drawing here.
  def transition(from, to, project_id: nil, role_id: nil)
    WorkflowTransition.create!(
      tracker_id: tracker.id, role_id: role_id || role.id, project_id: project_id,
      old_status_id: from.respond_to?(:id) ? from.id : from,
      new_status_id: to.respond_to?(:id) ? to.id : to
    )
  end

  # Redmine's fixtures enable trackers 1, 2 and 3 on projects_001, so a tracker
  # the project has *not* enabled has to be made rather than found.
  def disable_foreign_tracker
    project.trackers = project.trackers.to_a - [foreign_tracker]
  end

  # ...and both roles_001 and roles_002 have members in projects_001, so the
  # one-role case has to be made too.
  def leave_one_role
    MemberRole.joins(:member).where(members: { project_id: project.id }, role_id: other_role.id).destroy_all
  end

  # The plugin's own <svg>, cut out of the page. Redmine's layout renders its
  # icon sprite into the same response, so every assertion about "the drawing"
  # has to be scoped or it is an assertion about core's chrome.
  def graph_svg
    response.body[%r{<svg[^>]*class="project-workflow-graph-svg".*?</svg>}m]
  end

  def log_in(user_id, *permissions)
    role.add_permission!(*permissions) if permissions.any?
    @request.session[:user_id] = user_id
  end

  before { RedmineProjectWorkflows::Services::Resolver.reset_cache! }

  describe 'authorization' do
    it 'sends an anonymous visitor to the login page' do
      get :graph, params: graph_params

      expect(response).to redirect_to(/login/)
    end

    it 'is 403 for a member without either workflow permission' do
      log_in(2)

      get :graph, params: graph_params

      expect(response).to have_http_status(:forbidden)
    end

    it 'is reachable with view_project_workflow' do
      transition(new_status, assigned)
      log_in(2, :view_project_workflow)

      get :graph, params: graph_params

      expect(response).to have_http_status(:ok)
    end

    # The registration trap, and the reason it carries a spec rather than a
    # comment: an action missing from a permission's action list in init.rb is a
    # 403 on a route that looks perfectly written, for administrators too, with
    # nothing anywhere naming the cause. A member holding only the *manage*
    # permission may plainly see the screen they are allowed to change.
    it 'is reachable with manage_project_workflow alone' do
      log_in(2, :manage_project_workflow)

      get :graph, params: graph_params

      expect(response).to have_http_status(:ok)
    end

    it 'cannot be widened to another project by a parameter' do
      # The permission is on roles_001, which jsmith holds in projects_001 only.
      # A second project_id among the parameters must not move the screen: the
      # project comes from the path and from nowhere else (INV-7).
      log_in(2, :view_project_workflow)

      get :graph, params: { project_id: other_project.id, tracker_id: tracker.id,
                            role_id: [other_role.id] }

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe 'what the selection may name' do
    before { log_in(2, :view_project_workflow) }

    it 'is 404 for a tracker the project has not enabled' do
      disable_foreign_tracker

      get :graph, params: graph_params(tracker_id: foreign_tracker.id)

      expect(response).to have_http_status(:not_found)
    end

    it 'is 404 for a role the project does not offer' do
      # Rather than quietly drawing something else under this role's name.
      get :graph, params: graph_params(role_id: [unused_role.id])

      expect(response).to have_http_status(:not_found)
    end

    it 'is 404 for a role id that names nothing' do
      get :graph, params: graph_params(role_id: %w[1e5])

      expect(response).to have_http_status(:not_found)
    end

    it 'does not raise on a role_id that is not a list of ids at all' do
      # A hand-built request can send anything. It has to answer, not 500.
      get :graph, params: graph_params(role_id: { 'x' => 'y' })

      expect(response).to have_http_status(:not_found)
    end

    it 'offers a role that has no member here but already holds a scope' do
      # Finding F05's population: a workflow the project runs and its tab would
      # otherwise not list. visible_roles, not roles.
      give_own_workflow(project, tracker, unused_role)

      get :graph, params: graph_params(role_id: [unused_role.id])

      expect(response).to have_http_status(:ok)
      expect(assigns(:roles)).to eq([unused_role])
    end
  end

  describe 'the default selection' do
    it "is the reader's own roles in this project" do
      log_in(2, :view_project_workflow)

      get :graph, params: graph_params

      expect(assigns(:roles)).to eq([role])
    end

    it 'is every role the project offers for a reader who holds none of them' do
      # An administrator, and anybody reaching the screen other than through a
      # membership. An empty drawing would be the wrong answer to "show me this
      # project's workflow".
      log_in(1)

      get :graph, params: graph_params

      expect(assigns(:roles)).to eq(assigns(:visible_roles))
      expect(assigns(:roles)).not_to be_empty
    end
  end

  describe 'what it draws' do
    before { log_in(2, :view_project_workflow) }

    it 'draws the generic workflow for a combination the project inherits' do
      transition(new_status, assigned)

      get :graph, params: graph_params

      expect(assigns(:graph).edges.map { |edge| [edge.old_status_id, edge.new_status_id] })
        .to eq([[new_status.id, assigned.id]])
      expect(assigns(:graph).uniform_state).to eq(:inherits)
      expect(response.body).to include(ERB::Util.html_escape(assigned.name))
    end

    it "draws the project's own workflow and never the generic one (INV-1, INV-5)" do
      transition(new_status, closed)
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, project_id: project.id)

      get :graph, params: graph_params

      expect(assigns(:graph).edges.map(&:new_status_id)).to eq([assigned.id])
    end

    it 'draws an own empty workflow as the starting point alone, and says why' do
      give_own_workflow(project, tracker, role)

      get :graph, params: graph_params

      expect(assigns(:graph)).to be_empty_workflow
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_graph_empty)))
      # One node -- core's "new issue" pseudo-status -- and no arrow at all.
      # Scoped to the drawing rather than to the page: Redmine's own layout is
      # full of <path> elements from its icon sprite, so an unscoped assertion
      # here is about core's chrome and not about the workflow.
      # Scoped to the drawing, and then to what makes a path an *arrow*: the
      # <marker> that defines the arrowhead is itself a <path>, and it is in
      # <defs> whether anything uses it or not.
      drawing = graph_svg
      expect(drawing.scan('<rect ').size).to eq(1)
      expect(drawing).not_to include('marker-end=')
    end

    # The defect the review of this package's own diff turned up: a drawing with
    # no arrows in it has two different causes, and they were being told with one
    # sentence keyed on `empty_workflow?` alone.
    #
    # Two of the three examples below are red against that version -- the first,
    # which had it claiming an own empty workflow for a project that inherits,
    # and the third, which had it listing every status the tracker uses under
    # "not used by the selected roles". The second passes either way: it is here
    # so that the fix is pinned in *both* directions, because keying the sentence
    # on the state rather than on the rules is only right if it still fires when
    # one role of several is the empty one.
    it 'does not claim an own empty workflow when the project simply inherits one with no rules' do
      # No rule anywhere for this combination, and no scope either: the project
      # follows a generic workflow that nobody has filled in. INV-3 -- the state
      # comes from the scope table, never from the absence of rules.
      get :graph, params: graph_params

      expect(assigns(:graph).uniform_state).to eq(:inherits)
      expect(assigns(:graph)).to be_empty_workflow
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_graph_nothing)))
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_graph_empty)))
    end

    it 'says an own empty workflow is deliberate even when another role has rules' do
      leave_one_role
      give_own_workflow(project, tracker, role)

      get :graph, params: graph_params

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_graph_empty)))
    end

    it 'lists no diagnostics for a workflow with no transition at all' do
      # Every status the tracker uses is "not used by the selected roles" there,
      # and thirty of them under that heading buries the sentence that explains
      # the whole thing.
      give_own_workflow(project, tracker, role)
      transition(new_status, assigned, role_id: other_role.id)

      get :graph, params: graph_params(role_id: [role.id])

      expect(assigns(:graph).unmentioned_nodes).not_to be_empty
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_graph_unmentioned)))
      expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_graph_diagnostics)))
    end

    it 'renders a viewBox that contains every path it drew' do
      # The clipping regression, asserted on the real page rather than only on
      # the layout: a viewBox is an attribute nothing validates, and an arc
      # outside it disappears with no error.
      transition(0, new_status)
      transition(new_status, assigned)
      transition(assigned, new_status)

      get :graph, params: graph_params

      view_box = response.body[/viewBox="([^"]+)"/, 1].split.map(&:to_i)
      points = response.body.scan(/ d="M ([^"]+)"/).flatten.join(' ').scan(/-?\d+/).map(&:to_i)
      expect(points.each_slice(2).map(&:first).max).to be <= view_box[2]
      expect(points.each_slice(2).map(&:last).max).to be <= view_box[3]
    end

    it 'names the statuses no role can reach and the ones with no way out' do
      transition(0, new_status)
      transition(new_status, closed)

      get :graph, params: graph_params

      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_graph_dead_end)))
    end

    it 'renders the table beneath the drawing as the readable twin' do
      transition(new_status, assigned)

      get :graph, params: graph_params

      expect(response.body).to include('project-workflow-graph-transitions')
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_graph_table)))
    end

    it 'puts no script, no style and no foreignObject inside the drawing' do
      transition(new_status, assigned)

      get :graph, params: graph_params

      svg = graph_svg
      expect(svg).not_to include('<script')
      expect(svg).not_to include('<style')
      expect(svg).not_to include('<foreignObject')
    end

    it 'escapes a status name into the drawing rather than letting it be markup' do
      new_status.update!(name: '<script>alert(1)</script>')

      transition(new_status, assigned)

      get :graph, params: graph_params

      expect(response.body).not_to include('<script>alert(1)</script>')
      expect(response.body).to include('&lt;script&gt;')
    end
  end

  describe 'the role selector' do
    before { log_in(2, :view_project_workflow) }

    it 'is offered when the project has more than one role to pick' do
      get :graph, params: graph_params

      expect(assigns(:visible_roles).size).to be > 1
      expect(response.body).to include('role_id[]')
    end

    it 'is omitted when there is only one thing to pick' do
      # A control with one option is a control that cannot be used.
      leave_one_role

      get :graph, params: graph_params

      expect(assigns(:visible_roles).size).to eq(1)
      expect(response.body).not_to include('role_id[]')
    end

    it 'draws the union of two selected roles' do
      transition(new_status, assigned)
      transition(new_status, closed, role_id: other_role.id)

      get :graph, params: graph_params(role_id: [role.id, other_role.id])

      expect(assigns(:graph).edges.map(&:new_status_id)).to contain_exactly(assigned.id, closed.id)
    end
  end
end
