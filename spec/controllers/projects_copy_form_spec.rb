# frozen_string_literal: true

require_relative '../spec_helper'

# The plugin's item on Redmine's *Copy project* form.
#
# This is INV-9's discipline applied to a seam that is not a Deface anchor. The
# checkbox reaches the page through core's own
# `view_projects_copy_only_items` hook, which sits inside the copy fieldset on
# 5.1, 6.1 and 7.0 alike -- so no override is needed and the count stays at
# fifteen. But an extension point can be removed as silently as a selector can
# stop matching: core would simply stop calling it, the checkbox would vanish,
# every copy would carry the workflow again, and nothing else in the suite would
# notice. So it is asserted here, against the real rendered page, on every
# supported version.
#
# Copying a project is administrator-only on all three
# (`before_action :require_admin, only: [:copy, ...]`), which is why the only
# authorization example here is the negative one.
describe ProjectsController, type: :controller do
  render_views

  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules, :projects_trackers

  let(:project) { projects(:projects_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:role) { roles(:roles_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:key) { RedmineProjectWorkflows::Services::ProjectWorkflowCopier::COPY_ONLY_KEY }

  before { ProjectWorkflowScope.delete_all }

  describe 'GET copy' do
    before { @request.session[:user_id] = 1 }

    it 'offers the workflow among the things to copy, ticked' do
      get :copy, params: { id: project.id }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_copy_item)))
      expect(response.body).to match(/name="only\[\]"[^>]*value="#{Regexp.escape(key)}"[^>]*checked/)
    end

    # Core writes "(N)" after every item on that form, so the reader can see
    # what a tick would actually bring across before they press Copy.
    it 'says how many workflows the project has' do
      give_own_workflow(project, tracker, role)
      give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

      get :copy, params: { id: project.id }

      expect(response.body).to include("#{I18n.t(:label_project_workflow_copy_item)} (2)")
    end

    it 'says (0) for a project that runs no workflow of its own' do
      get :copy, params: { id: project.id }

      expect(response.body).to include("#{I18n.t(:label_project_workflow_copy_item)} (0)")
    end

    # WP14. The count has to be what a tick brings across, not what the project
    # holds. A copy takes the source's trackers with it, so a scope the source
    # kept for a tracker it has since disabled is not copied -- and counting it
    # would promise one more workflow than arrives.
    it 'counts only the workflows a copy would actually carry' do
      disabled_tracker = Tracker.create!(name: 'Not on this project', default_status_id: status.id)
      give_own_workflow(project, tracker, role)
      give_own_workflow(project, disabled_tracker, role)

      get :copy, params: { id: project.id }

      expect(project.trackers).not_to include(disabled_tracker)
      expect(response.body).to include("#{I18n.t(:label_project_workflow_copy_item)} (1)")
    end
  end

  it 'is not offered to a non-administrator, because the whole screen is not' do
    @request.session[:user_id] = 2

    get :copy, params: { id: project.id }

    expect(response).not_to have_http_status(:ok)
    expect(response.body).not_to include(ERB::Util.html_escape(I18n.t(:label_project_workflow_copy_item)))
  end
end
