# frozen_string_literal: true

require_relative '../spec_helper'

# WP14, audit finding F03. Core deletes every workflow row naming a status it is
# destroying; the plugin's scope rows survive, and a scope with no rules is an
# own *empty* workflow rather than nothing at all (INV-3). This service is what
# lets the administrator be told which projects that happened to.
describe RedmineProjectWorkflows::Services::StatusDeletionImpact do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:tracker) { trackers(:trackers_001) }
  let(:other_tracker) { trackers(:trackers_002) }
  let(:role) { roles(:roles_001) }
  let(:other_role) { roles(:roles_002) }
  let(:doomed) { issue_statuses(:issue_statuses_001) }
  let(:survivor) { issue_statuses(:issue_statuses_002) }
  let(:third) { issue_statuses(:issue_statuses_003) }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
  end

  def transition(target_project, from, to, project_tracker: tracker, project_role: role)
    WorkflowTransition.create!(tracker_id: project_tracker.id, role_id: project_role.id,
                               project_id: target_project&.id,
                               old_status_id: from&.id || 0, new_status_id: to&.id || 0)
  end

  def permission(target_project, status, field: 'assigned_to_id')
    WorkflowPermission.create!(tracker_id: tracker.id, role_id: role.id, project_id: target_project&.id,
                               old_status_id: status.id, new_status_id: 0,
                               field_name: field, rule: 'readonly')
  end

  def impact
    described_class.of(doomed.id)
  end

  it 'names a project workflow whose every rule mentions the status' do
    give_own_workflow(project, tracker, role)
    transition(project, doomed, survivor)

    expect(impact.count).to eq(1)
    expect(impact.project_ids).to eq([project.id])
    expect(impact.combinations.first.rule_type).to eq(ProjectWorkflowScope::TRANSITIONS)
  end

  it 'says nothing about a workflow that keeps a rule of its own' do
    give_own_workflow(project, tracker, role)
    transition(project, doomed, survivor)
    transition(project, survivor, third)

    expect(impact.any?).to be(false)
  end

  # The rule rows of a project with no scope apply to nothing (INV-3), so
  # counting one would report a workflow that is not in force.
  it 'ignores project rules that no scope makes real' do
    transition(project, doomed, survivor)

    expect(impact.any?).to be(false)
  end

  # INV-4, and the reason the count exists at all: the generic workflow is not a
  # project's decision, so emptying it is core's business and not a warning.
  it 'ignores the generic workflow' do
    transition(nil, doomed, survivor)

    expect(impact.any?).to be(false)
  end

  it 'ignores a scope that already held no rule' do
    give_own_workflow(project, tracker, role)

    expect(impact.any?).to be(false)
  end

  # The scope lookup matches the whole key. A scope for the same project and
  # tracker under a different role must not answer for this one.
  it 'does not let one project scope answer for another role' do
    give_own_workflow(project, tracker, other_role)
    transition(project, doomed, survivor, project_role: role)

    expect(impact.any?).to be(false)
  end

  it 'counts each rule type separately' do
    give_own_workflow(project, tracker, role)
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
    transition(project, doomed, survivor)
    permission(project, doomed)

    expect(impact.count).to eq(2)
    expect(impact.combinations.map(&:rule_type)).to contain_exactly(
      ProjectWorkflowScope::TRANSITIONS, ProjectWorkflowScope::PERMISSIONS
    )
  end

  # A permissions scope keeps its rules when a transitions scope loses all of
  # its own: the two are separate decisions (ADR-001).
  it 'does not report a rule type that keeps a rule' do
    give_own_workflow(project, tracker, role)
    give_own_workflow(project, tracker, role, ProjectWorkflowScope::PERMISSIONS)
    transition(project, doomed, survivor)
    permission(project, survivor)

    expect(impact.count).to eq(1)
    expect(impact.combinations.first.rule_type).to eq(ProjectWorkflowScope::TRANSITIONS)
  end

  it 'finds a rule that names the status as the target of a move' do
    give_own_workflow(project, tracker, role)
    transition(project, survivor, doomed)

    expect(impact.count).to eq(1)
  end

  it 'reports every affected project once, whatever the number of combinations' do
    [project, other_project].each do |target|
      [tracker, other_tracker].each do |target_tracker|
        give_own_workflow(target, target_tracker, role)
        transition(target, doomed, survivor, project_tracker: target_tracker)
      end
    end

    expect(impact.count).to eq(4)
    expect(impact.project_ids).to contain_exactly(project.id, other_project.id)
  end

  it 'reports nothing for a status no rule names' do
    give_own_workflow(project, tracker, role)
    transition(project, survivor, third)

    expect(impact.any?).to be(false)
  end

  # The entry pseudo-status is stored as old_status_id 0 and is not an
  # IssueStatus. A status whose id is genuinely 0 does not exist, so nothing
  # here may be answered by the zero rows.
  it 'does not confuse the new-issue pseudo-status with a real one' do
    give_own_workflow(project, tracker, role)
    transition(project, nil, survivor)

    expect(impact.any?).to be(false)
  end

  it 'refuses a status id that is not a number' do
    expect { described_class.of('one') }.to raise_error(ArgumentError)
  end
end
