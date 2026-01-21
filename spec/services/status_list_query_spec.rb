# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::StatusListQuery do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:global_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  it 'returns global statuses when no project overrides exist' do
    WorkflowTransition.delete_all
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
      project_id: other_project.id,
      author: false,
      assignee: false
    )

    status_ids = described_class.status_ids_for_project(
      project: project,
      trackers: tracker,
      role_ids: [role.id]
    )

    expect(status_ids).to include(global_status.id)
    expect(status_ids).not_to include(project_status.id)
  end

  it 'prefers project statuses over global ones for overridden roles' do
    WorkflowTransition.delete_all
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

    status_ids = described_class.status_ids_for_project(
      project: project,
      trackers: tracker,
      role_ids: [role.id]
    )

    expect(status_ids).to include(project_status.id)
    expect(status_ids).not_to include(global_status.id)
  end

  it 'returns empty when trackers are missing' do
    status_ids = described_class.status_ids_for_project(
      project: project,
      trackers: [],
      role_ids: [role.id]
    )

    expect(status_ids).to be_empty
  end

  it 'returns empty when role ids are missing' do
    status_ids = described_class.status_ids_for_project(
      project: project,
      trackers: tracker,
      role_ids: []
    )

    expect(status_ids).to be_empty
  end

  it 'returns empty when role ids are missing even with transitions present' do
    WorkflowTransition.delete_all
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    status_ids = described_class.status_ids_for_project(
      project: project,
      trackers: tracker,
      role_ids: []
    )

    expect(status_ids).to be_empty
  end

  it 'uses workflow roles when role ids are nil' do
    WorkflowTransition.delete_all
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: old_status.id,
      new_status_id: global_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    status_ids = described_class.status_ids_for_project(
      project: project,
      trackers: tracker,
      role_ids: nil
    )

    expect(status_ids).to include(global_status.id)
  end
end
