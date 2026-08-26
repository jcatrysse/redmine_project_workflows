# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::TransitionQuery do
  fixtures :projects, :roles, :trackers, :issue_statuses, :users, :enumerations

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



  it 'ignores a project row when the project has no scope' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)
    statuses = described_class.allowed_statuses(
      issue: issue, user: user, initial_status: old_status, author: true, assignee: false
    )

    expect(statuses).to eq([global_status])
  end

  # INV-4. Core's own query names no project_id, so it would read this project's
  # rows together with the neighbour's; the plugin's never does.
  it 'never reads another project rows' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: project_status.id,
      project_id: projects(:projects_002).id,
      author: false,
      assignee: false
    )
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)
    statuses = described_class.allowed_statuses(
      issue: issue, user: user, initial_status: old_status, author: true, assignee: false
    )

    expect(statuses).to eq([global_status])
  end

  it 'allows nothing for a scope without rules' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )
    give_own_workflow(project, tracker, role)

    issue = Issue.new(project: project, tracker: tracker, status: old_status, author: user)
    statuses = described_class.allowed_statuses(
      issue: issue, user: user, initial_status: old_status, author: true, assignee: false
    )

    expect(statuses).to eq([])
  end

  it 'prefers project transitions over global ones for scoped roles' do
    give_own_workflow(project, tracker, role)
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
