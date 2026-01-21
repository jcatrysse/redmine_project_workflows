# frozen_string_literal: true

require_relative '../spec_helper'

describe Project, type: :model do
  fixtures :projects, :roles, :trackers, :issue_statuses, :enabled_modules

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:global_status) { issue_statuses(:issue_statuses_002) }
  let(:project_status) { issue_statuses(:issue_statuses_003) }

  before do
    project.enabled_modules << EnabledModule.new(name: 'issue_tracking') if project.enabled_modules.empty?
    other_project.enabled_modules << EnabledModule.new(name: 'issue_tracking') if other_project.enabled_modules.empty?
    project.trackers << tracker unless project.trackers.include?(tracker)
    other_project.trackers << tracker unless other_project.trackers.include?(tracker)
  end

  it 'returns only statuses from global workflows when no project overrides exist' do
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

    status_ids = project.rolled_up_statuses.pluck(:id)

    expect(status_ids).to include(global_status.id)
    expect(status_ids).not_to include(project_status.id)
  end

  it 'returns project-specific statuses for overridden roles' do
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

    status_ids = project.rolled_up_statuses.pluck(:id)

    expect(status_ids).to include(project_status.id)
    expect(status_ids).not_to include(global_status.id)
  end

  it 'returns empty statuses when the project has no trackers' do
    target_project = other_project
    target_project.trackers.clear
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

    status_ids = target_project.rolled_up_statuses.pluck(:id)

    expect(status_ids).to be_empty
  end
end
