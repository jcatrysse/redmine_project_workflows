# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::TransitionQuery do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:user) { users(:users_002) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:global_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  before do
    member = Member.where(project: project, user: user).first_or_initialize
    member.roles = [role] if member.new_record? || member.roles.empty?
    member.save!
  end

  it 'detects project overrides for transitions' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    expect(described_class.override_active?(project_id: project.id, tracker_id: tracker.id, role_ids: [role.id])).to be(true)
  end

  it 'prefers project transitions over global ones for overridden roles' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)

    statuses = described_class.allowed_statuses(
      issue: issue,
      user: user,
      initial_status: old_status,
      author: true,
      assignee: false
    )

    expect(statuses).to include(project_status)
    expect(statuses).not_to include(global_status)
  end
end
