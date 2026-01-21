# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::PermissionWriter do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:status) { issue_statuses(:issue_statuses_001) }
  let(:other_status) { issue_statuses(:issue_statuses_002) }

  it 'replaces permissions for selected fields without deleting unrelated rules' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'priority_id',
      rule: 'required',
      project_id: project.id
    )

    permissions = {
      status.id.to_s => {
        'subject' => 'required'
      }
    }

    described_class.replace_permissions(project, [tracker], [role], permissions)

    expect(
      WorkflowPermission.where(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'priority_id',
        project_id: project.id
      )
    ).to exist
    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'required')
  end

  it 'keeps permissions for other statuses intact' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: other_status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    permissions = {
      status.id.to_s => {
        'subject' => 'required'
      }
    }

    described_class.replace_permissions(project, [tracker], [role], permissions)

    expect(
      WorkflowPermission.where(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: other_status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to exist
  end

  it 'accepts action controller parameters when replacing permissions' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    permissions = ActionController::Parameters.new(
      status.id.to_s => {
        'subject' => 'required'
      }
    )

    described_class.replace_permissions(project, [tracker], [role], permissions)

    expect(
      WorkflowPermission.find_by(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to have_attributes(rule: 'required')
  end

  it 'skips deleting permissions when no fields are provided for a status' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    permissions = {
      status.id.to_s => {}
    }

    described_class.replace_permissions(project, [tracker], [role], permissions)

    expect(
      WorkflowPermission.where(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to exist
  end

  it 'does not raise when permissions are nil' do
    WorkflowPermission.create!(
      tracker_id: tracker.id,
      role_id: role.id,
      old_status_id: status.id,
      field_name: 'subject',
      rule: 'readonly',
      project_id: project.id
    )

    expect do
      described_class.replace_permissions(project, [tracker], [role], nil)
    end.not_to raise_error

    expect(
      WorkflowPermission.where(
        tracker_id: tracker.id,
        role_id: role.id,
        old_status_id: status.id,
        field_name: 'subject',
        project_id: project.id
      )
    ).to exist
  end
end
