# frozen_string_literal: true

require_relative '../spec_helper'

# Duplicating a role or a tracker (claude F03). Core's Role#copy_workflow_rules
# and Tracker#copy_workflow_rules go through WorkflowRule.copy, which sees the
# generic rules only, so the copy arrived without the project overrides -- and
# without the scopes that make project rules visible at all (INV-3).
describe 'Copying a role or a tracker' do
  fixtures :projects, :roles, :trackers, :issue_statuses

  let(:project) { projects(:projects_001) }
  let(:other_project) { projects(:projects_002) }
  let(:source_role) { roles(:roles_001) }
  let(:tracker) { trackers(:trackers_001) }
  let(:source_tracker) { trackers(:trackers_001) }
  let(:old_status) { issue_statuses(:issue_statuses_001) }
  let(:new_status) { issue_statuses(:issue_statuses_002) }

  before do
    WorkflowRule.delete_all
    ProjectWorkflowScope.delete_all
  end

  def transition(tracker_id:, role_id:, project_id: nil, from: old_status, to: new_status)
    WorkflowTransition.create!(
      tracker_id: tracker_id, role_id: role_id,
      old_status_id: from.id, new_status_id: to.id,
      project_id: project_id, author: false, assignee: false
    )
  end

  def permission(tracker_id:, role_id:, project_id: nil, field: 'due_date', rule: 'required')
    WorkflowPermission.create!(
      tracker_id: tracker_id, role_id: role_id,
      old_status_id: old_status.id, field_name: field, rule: rule,
      project_id: project_id
    )
  end

  describe 'a role' do
    let(:target_role) { Role.create!(name: 'Copied role', permissions: %i[add_issues edit_issues]) }

    it 'carries the generic rules, as core does' do
      transition(tracker_id: tracker.id, role_id: source_role.id)

      target_role.copy_workflow_rules(source_role)

      expect(WorkflowTransition.where(role_id: target_role.id, project_id: nil).count).to eq(1)
    end

    it "carries a project's rules and the scope that makes them visible" do
      give_own_workflow(project, tracker, source_role)
      transition(tracker_id: tracker.id, role_id: source_role.id, project_id: project.id)

      target_role.copy_workflow_rules(source_role)

      expect(WorkflowTransition.where(role_id: target_role.id, project_id: project.id).count).to eq(1)
      expect(own_workflow?(project, tracker, target_role)).to be(true)
    end

    it 'carries an own empty workflow as an own empty workflow' do
      give_own_workflow(project, tracker, source_role)
      transition(tracker_id: tracker.id, role_id: source_role.id)

      target_role.copy_workflow_rules(source_role)

      # The source project answers for itself and permits nothing. Dropping the
      # scope would silently return the copy to the generic workflow (INV-3).
      expect(own_workflow?(project, tracker, target_role)).to be(true)
      expect(WorkflowTransition.where(role_id: target_role.id, project_id: project.id).count).to eq(0)
    end

    it 'carries the field permissions and their own scope separately' do
      give_own_workflow(project, tracker, source_role, ProjectWorkflowScope::PERMISSIONS)
      permission(tracker_id: tracker.id, role_id: source_role.id, project_id: project.id)

      target_role.copy_workflow_rules(source_role)

      expect(WorkflowPermission.where(role_id: target_role.id, project_id: project.id).count).to eq(1)
      expect(own_workflow?(project, tracker, target_role, ProjectWorkflowScope::PERMISSIONS)).to be(true)
      # Taking over transitions and taking over field permissions are separate
      # decisions (ADR-001); the copy must not invent the other one.
      expect(own_workflow?(project, tracker, target_role, ProjectWorkflowScope::TRANSITIONS)).to be(false)
    end

    it 'leaves a project that the source does not override alone' do
      give_own_workflow(project, tracker, source_role)
      transition(tracker_id: tracker.id, role_id: source_role.id, project_id: project.id)

      target_role.copy_workflow_rules(source_role)

      expect(own_workflow?(other_project, tracker, target_role)).to be(false)
      expect(WorkflowTransition.where(role_id: target_role.id, project_id: other_project.id).count).to eq(0)
    end

    it 'touches no rule of the source role' do
      give_own_workflow(project, tracker, source_role)
      transition(tracker_id: tracker.id, role_id: source_role.id, project_id: project.id)
      transition(tracker_id: tracker.id, role_id: source_role.id)

      expect { target_role.copy_workflow_rules(source_role) }
        .not_to(change { WorkflowRule.where(role_id: source_role.id).count })
    end
  end

  describe 'a tracker' do
    let(:target_tracker) do
      Tracker.create!(name: 'Copied tracker', default_status_id: old_status.id)
    end

    it "carries a project's rules and the scope that makes them visible" do
      give_own_workflow(project, source_tracker, source_role)
      transition(tracker_id: source_tracker.id, role_id: source_role.id, project_id: project.id)

      target_tracker.copy_workflow_rules(source_tracker)

      expect(WorkflowTransition.where(tracker_id: target_tracker.id, project_id: project.id).count).to eq(1)
      expect(own_workflow?(project, target_tracker, source_role)).to be(true)
    end

    it 'carries the generic rules for every role that considers the workflow' do
      transition(tracker_id: source_tracker.id, role_id: source_role.id)

      target_tracker.copy_workflow_rules(source_tracker)

      expect(WorkflowTransition.where(tracker_id: target_tracker.id, project_id: nil).count).to eq(1)
    end
  end

  describe 'the administration copy screen' do
    let(:target_role) { Role.create!(name: 'Screen target', permissions: [:add_issues]) }

    it 'still copies the generic workflow alone' do
      give_own_workflow(project, tracker, source_role)
      transition(tracker_id: tracker.id, role_id: source_role.id, project_id: project.id)
      transition(tracker_id: tracker.id, role_id: source_role.id)

      # Core's own entry point, which the screen falls through to when no
      # project is selected. "Copy the generic workflow" must not quietly mean
      # "copy every project's workflow too".
      WorkflowRule.copy(tracker, source_role, tracker, target_role)

      expect(WorkflowTransition.where(role_id: target_role.id, project_id: nil).count).to eq(1)
      expect(WorkflowTransition.where(role_id: target_role.id, project_id: project.id).count).to eq(0)
      expect(own_workflow?(project, tracker, target_role)).to be(false)
    end
  end
end
