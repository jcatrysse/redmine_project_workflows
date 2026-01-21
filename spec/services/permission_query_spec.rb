# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::PermissionQuery do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:user) { users(:users_002) }
  let(:status) { issue_statuses(:issue_statuses_001) }

  before do
    member = Member.where(project: project, user: user).first_or_initialize
    member.roles = [role] if member.new_record? || member.roles.empty?
    member.save!
  end

  it 'detects project overrides for permissions' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    expect(described_class.override_active?(project_id: project.id, tracker_id: tracker.id, role_ids: [role.id])).to be(true)
  end

  it 'returns project rules when overrides exist' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'required',
      project_id: nil
    )
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    issue = Issue.new(project: project, tracker: tracker, status: status, author: user)

    rules = described_class.rules_for(issue: issue, user: user, old_status_id: status.id)

    expect(rules.map(&:rule)).to eq(['readonly'])
  end
end
