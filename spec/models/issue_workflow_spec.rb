# frozen_string_literal: true

require_relative '../spec_helper'

describe Issue, type: :model do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :members, :member_roles

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:user) { users(:users_002) }
  let(:global_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  before do
    member = Member.where(project: project, user: user).first_or_initialize
    member.roles = [role] if member.new_record? || member.roles.empty?
    member.save!

    WorkflowTransition.where(tracker_id: tracker.id, role_id: role.id).delete_all
  end

  it 'uses only global transitions for new issues in projects without overrides' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: 0,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: 0,
      new_status_id: project_status.id,
      project_id: other_project.id,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, author: user)

    statuses = issue.new_statuses_allowed_to(user, true)

    expect(statuses).to include(global_status)
    expect(statuses).not_to include(project_status)
  end

  it 'prefers project-specific transitions over global ones for new issues' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: 0,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: 0,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, author: user)

    statuses = issue.new_statuses_allowed_to(user, true)

    expect(statuses).to include(project_status)
    expect(statuses).not_to include(global_status)
  end

  it 'falls back to the default status when no transitions are defined' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: 0,
      new_status_id: project_status.id,
      project_id: other_project.id,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, author: user)

    statuses = issue.new_statuses_allowed_to(user, true)

    expect(statuses).to contain_exactly(issue.default_status)
  end
end
