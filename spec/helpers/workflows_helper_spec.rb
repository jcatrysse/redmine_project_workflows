# frozen_string_literal: true

require_relative '../spec_helper'

describe WorkflowsHelper, type: :helper do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:field_name) { 'subject' }
  let(:new_status) { issue_statuses(:issue_statuses_002) }

  before do
    helper.instance_variable_set(:@roles, [role])
    helper.instance_variable_set(:@trackers, [tracker])
    helper.instance_variable_set(:@projects_for_update, [project, other_project])
  end

  it 'treats full project coverage as a checked transition' do
    html = helper.transition_tag(2, status, new_status, 'always')

    expect(html).to include('type="checkbox"')
  end

  it 'uses no-change when not all projects share the same permission' do
    permissions = {
      status.id => {
        field_name => ['readonly']
      }
    }

    html = helper.field_permission_tag(permissions, status, field_name, [role])

    expect(html).to include('no_change')
  end

  it 'treats full project and global coverage as a checked transition' do
    helper.instance_variable_set(:@global_selected, true)

    html = helper.transition_tag(3, status, new_status, 'always')

    expect(html).to include('type="checkbox"')
  end
end
