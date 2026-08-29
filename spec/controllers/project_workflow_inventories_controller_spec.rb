# frozen_string_literal: true

require_relative '../spec_helper'

describe ProjectWorkflowInventoriesController, type: :controller do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }

  def rows
    assigns(:rows).map { |row| [row.project.id, row.tracker.id, row.role.id] }
  end

  describe 'authorization' do
    # INV-7. The inventory names every project that has taken over a workflow,
    # so it is an administrator screen until WP4 gives it a per-project entry
    # point with its own permission.
    it 'sends an anonymous visitor to the login page' do
      get :index
      expect(response).to redirect_to(/login/)
    end

    it 'refuses a logged-in non-administrator' do
      @request.session[:user_id] = 2
      get :index
      expect(response).to have_http_status(:forbidden)
    end

    it 'answers an administrator' do
      @request.session[:user_id] = 1
      get :index
      expect(response).to have_http_status(:ok)
    end
  end

  context 'as an administrator' do
    before { @request.session[:user_id] = 1 }

    it 'lists only the projects that decided something, by default' do
      give_own_workflow(project, tracker, role)

      get :index

      expect(assigns(:deviations_only)).to be(true)
      expect(rows).to eq([[project.id, tracker.id, role.id]])
    end

    it 'lists every combination when asked to' do
      get :index, params: { deviations_only: '0' }

      expect(assigns(:deviations_only)).to be(false)
      expect(assigns(:row_count))
        .to eq(Project.count * Tracker.count * Role.sorted.count(&:consider_workflow?))
    end

    it 'narrows to the projects asked for' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(other_project, tracker, role)

      get :index, params: { project_id: [other_project.id.to_s] }

      expect(rows).to eq([[other_project.id, tracker.id, role.id]])
    end

    it 'narrows to one kind of rule' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      get :index, params: { rule_type: ProjectWorkflowScope::TRANSITIONS }

      expect(assigns(:rule_types)).to eq([ProjectWorkflowScope::TRANSITIONS])
      expect(rows).to eq([])
    end

    it 'shows both kinds of rule when none is asked for' do
      get :index
      expect(assigns(:rule_types)).to eq(ProjectWorkflowScope::RULE_TYPES)
    end

    it 'counts the project\'s own rules and not the generic ones' do
      give_own_workflow(project, tracker, role)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: s1.id, new_status_id: s2.id, project_id: nil)
      WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id,
                                 old_status_id: s1.id, new_status_id: s2.id, project_id: project.id)

      get :index

      cell = assigns(:rows).first.cells[ProjectWorkflowScope::TRANSITIONS]
      expect(cell.rule_count).to eq(1)
      expect(cell.state).to eq(:own)
    end

    describe 'a filter value that does not resolve' do
      # A filter is a form the operator can correct, so it is a message and a
      # narrowed result rather than a 404 -- unlike the scope action links,
      # which the screen generates itself.
      it 'is dropped, reported, and does not take the rest of the filter with it' do
        give_own_workflow(project, tracker, role)
        give_own_workflow(other_project, tracker, role)

        get :index, params: { project_id: [project.id.to_s, '99999999'] }

        expect(response).to have_http_status(:ok)
        expect(flash.now[:warning]).to eq(I18n.t(:error_project_workflow_inventory_filter))
        expect(rows).to eq([[project.id, tracker.id, role.id]])
      end

      # A filter that survives nothing must list nothing. Treating it as "no
      # filter" would answer a request for one project with every project.
      it 'lists nothing when the whole filter was invalid' do
        give_own_workflow(project, tracker, role)

        get :index, params: { project_id: ['99999999'] }

        expect(response).to have_http_status(:ok)
        expect(rows).to eq([])
      end

      it 'does not let a loosely cast id widen the selection' do
        give_own_workflow(project, tracker, role)
        give_own_workflow(other_project, tracker, role)

        # Project.where(id: ['1e5']) resolves to project 1 in Rails; matching
        # against the loaded list rather than the database is what stops it.
        get :index, params: { project_id: ["#{project.id}e5"] }

        expect(rows).to eq([])
        expect(flash.now[:warning]).to be_present
      end

      it 'reports an unknown kind of rule' do
        get :index, params: { rule_type: 'sideways' }

        expect(response).to have_http_status(:ok)
        expect(assigns(:rule_types)).to eq(ProjectWorkflowScope::RULE_TYPES)
        expect(flash.now[:warning]).to be_present
      end
    end

    it 'answers a page number past the end with an empty page' do
      give_own_workflow(project, tracker, role)

      get :index, params: { page: '99' }

      expect(response).to have_http_status(:ok)
      expect(assigns(:row_count)).to eq(1)
      expect(assigns(:rows)).to eq([])
    end

    describe 'the rendered page' do
      render_views

      it 'names each state in words' do
        give_own_workflow(project, tracker, role)

        get :index

        expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_state_own_empty)))
      end

      it 'links each row into the two matrices, pre-filled' do
        give_own_workflow(project, tracker, role)

        get :index

        # The plugin's own matrices. Since ADR-003 core's screens read no project
        # parameter at all, so a link into them carrying one would land the
        # reader on the generic matrix believing it was the project's.
        expect(response.body).to match(
          %r{project_workflow_rules/edit\?[^"']*project_id(%5B%5D|\[\])=#{project.id}}
        )
        expect(response.body).to match(
          %r{project_workflow_rules/permissions\?[^"']*project_id(%5B%5D|\[\])=#{project.id}}
        )
      end

      it 'offers a sentence and two ways on when there is nothing to list' do
        get :index

        expect(response.body).to include(ERB::Util.html_escape(I18n.t(:text_project_workflow_inventory_empty)))
        expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_inventory_show_all)))
        expect(response.body).to include(ERB::Util.html_escape(I18n.t(:button_project_workflow_inventory_open_matrices)))
      end

      it 'keeps the other filters when it offers to drop the deviations one' do
        get :index, params: { tracker_id: [tracker.id.to_s] }

        expect(response.body).to match(/deviations_only=0/)
        expect(response.body).to match(/tracker_id(%5B%5D|\[\])=#{tracker.id}/)
      end
    end
  end

  # WP6: the inventory says who last changed each workflow, so an administrator
  # looking at a deviation can see where it came from.
  describe 'the audit line' do
    render_views

    before { @request.session[:user_id] = 1 }

    def enable_for(user)
      RedmineProjectWorkflows::Services::ScopeWriter.enable(
        project_ids: [project.id], tracker_ids: [tracker.id], role_ids: [role.id],
        rule_type: ProjectWorkflowScope::TRANSITIONS, copy_generic: false, user: user
      )
    end

    # Rendered rather than asserted on `assigns`, because the sentence is built
    # by core's `authoring` helper and a helper the plugin has not named in the
    # controller raises only when the view actually runs.
    it 'names the user who last changed the rules' do
      enable_for(users(:users_002))

      get :index

      expect(response.body).to include('project-workflow-scope-audit')
      expect(response.body).to include(users(:users_002).name)
    end

    it 'says nothing where the combination inherits' do
      enable_for(users(:users_002))

      get :index

      # The transitions cell carries the line; the permissions cell of the same
      # row inherits, so it must not.
      expect(response.body.scan('project-workflow-scope-audit').size).to eq(1)
    end

    # WP6: the third entry point. The comparison is a project screen, so this
    # link leads out of the administration section -- which is what the work
    # package asked for, "reachable from the inventory and from the matrix".
    it 'links every deviating cell to the comparison' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::TRANSITIONS)

      get :index

      path = project_workflow_compare_path(project, tracker_id: tracker.id, role_id: role.id,
                                                    rule_type: ProjectWorkflowScope::TRANSITIONS)
      expect(response.body).to include(ERB::Util.html_escape(path))
      # The same row's permissions cell inherits, so it gets no link.
      expect(response.body.scan('project-workflow-compare-link').size).to eq(1)
    end

    # A scope the WP1 backfill wrote has a time and no author, and "Updated by
    # Anonymous" would name somebody who was not there.
    it 'says nothing for a scope written with nobody logged in' do
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::TRANSITIONS)

      get :index

      expect(response.body).not_to include('project-workflow-scope-audit')
    end

    # WP13, audit finding F09, and the half of it this page deliberately does
    # **not** take. Archived projects left the selectors that decide what to
    # write, because a workflow written for one governs nothing. They did not
    # leave this page: it is a report, and an archived project running its own
    # workflow is exactly the row somebody needs to see -- before they unarchive
    # it, not after.
    it 'still reports an archived project that runs its own workflow' do
      give_own_workflow(other_project, tracker, role, ProjectWorkflowScope::TRANSITIONS)
      other_project.update!(status: Project::STATUS_ARCHIVED)

      get :index

      expect(assigns(:rows).map { |row| row.project.id }).to include(other_project.id)
    end
  end
end
