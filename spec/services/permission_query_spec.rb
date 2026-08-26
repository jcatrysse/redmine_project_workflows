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



  def global_rule(rule = 'required')
    WorkflowPermission.create!(
      tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
      field_name: 'subject', rule: rule, project_id: nil
    )
  end

  def rules_for(target = project)
    issue = Issue.new(project: target, tracker: tracker, status: status, author: user)
    described_class.rules_for(issue: issue, user: user, old_status_id: status.id)
  end

  it 'ignores a project row when the project has no scope' do
    global_rule
    WorkflowPermission.create!(
      tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
      field_name: 'subject', rule: 'readonly', project_id: project.id
    )

    expect(rules_for.map(&:rule)).to eq(['required'])
  end

  # INV-4: a neighbour's rows are never part of this project's answer.
  it 'never reads another project rows' do
    global_rule
    WorkflowPermission.create!(
      tracker_id: tracker.id, role_id: role.id, old_status_id: status.id,
      field_name: 'subject', rule: 'readonly', project_id: projects(:projects_002).id
    )

    expect(rules_for.map(&:rule)).to eq(['required'])
  end

  it 'applies no rule at all for a permissions scope without rules' do
    global_rule
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

    expect(rules_for).to eq([])
  end

  it 'is not affected by a transitions scope' do
    global_rule
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::TRANSITIONS)

    expect(rules_for.map(&:rule)).to eq(['required'])
  end

  it 'returns project rules for a scoped role' do
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
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
