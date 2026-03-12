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



  it 'returns false when only global permissions exist' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: nil
    )

    expect(described_class.override_active?(tracker_id: tracker.id, role_ids: [role.id])).to be(false)
  end

  it 'returns false when no permissions exist at all' do
    expect(described_class.override_active?(tracker_id: tracker.id, role_ids: [role.id])).to be(false)
  end

  it 'detects permission overrides when they exist on another project for the same tracker and role' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: projects(:projects_002).id
    )

    expect(described_class.override_active?(tracker_id: tracker.id, role_ids: [role.id])).to be(true)
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

    expect(described_class.override_active?(tracker_id: tracker.id, role_ids: [role.id])).to be(true)
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
