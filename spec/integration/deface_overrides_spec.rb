# frozen_string_literal: true
#
# Guards that every Deface override still matches its anchor in the host
# Redmine's views. A silently unmatched override produces no error, only a
# missing project selector, so this must be asserted per supported version.
#
require_relative '../spec_helper'

describe WorkflowsController, type: :controller do
  render_views
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members,
           :member_roles, :enabled_modules

  before { @request.session[:user_id] = 1 }

  let(:role)    { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }

  it 'injects the project selector into the transitions page' do
    get :edit, params: { role_id: [role.id], tracker_id: [tracker.id],
                         project_id: ['global'], used_statuses_only: '0' }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('project_id[]')
  end

  it 'injects the project selector into the field permissions page' do
    get :permissions, params: { role_id: [role.id], tracker_id: [tracker.id],
                                project_id: ['global'] }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('project_id[]')
  end

  it 'injects both project selectors into the copy page' do
    get :copy
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('source_project_id')
    expect(response.body).to include('target_project_ids')
  end
end
