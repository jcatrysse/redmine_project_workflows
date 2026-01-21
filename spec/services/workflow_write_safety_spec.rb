# frozen_string_literal: true

require_relative '../spec_helper'

describe 'Workflow global write safety' do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }

  it 'keeps project transitions when global transitions are replaced' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      new_status_id: new_status.id,
      project_id: project.id,
      author: false,
      assignee: false
    )

    transitions = {
      status.id.to_s => {
        new_status.id.to_s => { 'always' => '0' }
      }
    }

    expect {
      WorkflowTransition.replace_transitions([tracker], [role], transitions)
    }.not_to change {
      WorkflowTransition.where(project_id: project.id).count
    }
  end

  it 'keeps global transitions when project transitions are replaced' do
    WorkflowTransition.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      new_status_id: new_status.id,
      project_id: nil,
      author: false,
      assignee: false
    )

    transitions = {
      status.id.to_s => {
        new_status.id.to_s => { 'always' => '1' }
      }
    }

    expect {
      RedmineProjectWorkflows::Services::TransitionWriter.replace_transitions(project, [tracker], [role], transitions)
    }.not_to change {
      WorkflowTransition.where(project_id: nil).count
    }
  end

  it 'keeps project permissions when global permissions are replaced' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    permissions = {
      status.id.to_s => { 'subject' => '' }
    }

    expect {
      WorkflowPermission.replace_permissions([tracker], [role], permissions)
    }.not_to change {
      WorkflowPermission.where(project_id: project.id).count
    }
  end

  it 'keeps global permissions when project permissions are replaced' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: nil
    )

    permissions = {
      status.id.to_s => { 'subject' => 'required' }
    }

    expect {
      RedmineProjectWorkflows::Services::PermissionWriter.replace_permissions(project, [tracker], [role], permissions)
    }.not_to change {
      WorkflowPermission.where(project_id: nil).count
    }
  end
end
