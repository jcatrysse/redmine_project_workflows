# frozen_string_literal: true

require_relative '../spec_helper'

describe RedmineProjectWorkflows::Services::ScopeState do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:other) { projects(:projects_002) }
  let(:role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:s1) { issue_statuses(:issue_statuses_001) }
  let(:s2) { issue_statuses(:issue_statuses_002) }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
  end

  def state(projects: [project], roles: [role])
    described_class.new(
      project_ids: projects, tracker_ids: [tracker], role_ids: roles,
      rule_type: ProjectWorkflowScope::TRANSITIONS
    )
  end

  def project_rule(target)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: target.id,
                               old_status_id: s1.id, new_status_id: s2.id)
  end

  it 'reports an empty selection as nothing to say' do
    expect(state(projects: []).any?).to be(false)
    expect(state(projects: []).state).to eq(:none)
  end

  it 'reports inheritance when no scope exists' do
    project_rule(project) # rules alone are not a decision

    expect(state.state).to eq(:inherits)
    expect(state.inheriting).to eq(1)
    expect(state.scoped?).to be(false)
    expect(state.enable_possible?).to be(true)
  end

  it 'reports an own workflow when the scope has rules' do
    give_own_workflow(project, tracker, role)
    project_rule(project)

    expect(state.state).to eq(:own)
    expect(state.own).to eq(1)
    expect(state.enable_possible?).to be(false)
  end

  it 'reports an own empty workflow when the scope has none' do
    give_own_workflow(project, tracker, role)

    expect(state.state).to eq(:own_empty)
    expect(state.own_empty).to eq(1)
    expect(state.scoped?).to be(true)
  end

  it 'reports a mixed selection with all three counts' do
    give_own_workflow(project, tracker, role)
    project_rule(project)
    give_own_workflow(other, tracker, role)
    third = Project.create!(name: 'State third', identifier: 'state-third')

    result = state(projects: [project, other, third])

    expect(result.state).to eq(:mixed)
    expect([result.own, result.own_empty, result.inheriting]).to eq([1, 1, 1])
    expect(result.total).to eq(3)
  end

  # INV-4: a generic rule must never be counted towards a project's state.
  it 'does not count generic rules as a project workflow' do
    give_own_workflow(project, tracker, role)
    WorkflowTransition.create!(tracker_id: tracker.id, role_id: role.id, project_id: nil,
                               old_status_id: s1.id, new_status_id: s2.id)

    expect(state.state).to eq(:own_empty)
  end

  it 'does not count another project rules' do
    give_own_workflow(project, tracker, role)
    project_rule(other)

    expect(state.state).to eq(:own_empty)
  end

  it 'counts the other rule type separately' do
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)

    expect(state.state).to eq(:inherits)
  end
end
